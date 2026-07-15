import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:web_socket_channel/io.dart';

final _log = Logger("OpenAiRealtime");

/// Prebuilt voices for the OpenAI Realtime API. Names are sent verbatim as the
/// session `voice`; a self-hosted backend may accept a different set (or
/// ignore the field entirely).
// ignore: constant_identifier_names
enum OpenAiVoiceName {
  alloy,
  ash,
  ballad,
  coral,
  echo,
  sage,
  shimmer,
  verse,
  marin,
  cedar,
}

/// Minimal client for the OpenAI Realtime API over a websocket, speaking the
/// current **GA** interface (`session.type: realtime`, nested
/// `audio.{input,output}`, `response.output_audio.delta`). OpenAI disabled the
/// older beta shape; self-hosted OpenAI-Realtime-compatible stacks such as
/// huggingface/speech-to-speech also speak GA, so a single shape covers both.
///
/// Streams PCM16 mono audio up and receives PCM16 mono audio plus input/output
/// transcriptions back, always at [serverSampleRate] (24kHz, per the official
/// OpenAI Realtime API). The caller resamples to/from the Halo's 16kHz.
class OpenAiRealtime {
  /// PCM sample rate exchanged over the wire (the OpenAI Realtime API's rate)
  static const int serverSampleRate = 24000;

  IOWebSocketChannel? _channel;
  StreamSubscription? _channelSubs;
  bool _connected = false;
  bool _sessionReady = false;

  /// a reply is currently being generated (tracked off both response.created
  /// and the audio deltas, since some backends - e.g. jarvis in server-VAD mode
  /// - auto-create replies without emitting response.created)
  bool _responseActive = false;

  /// the user has barged in over the current reply: drop its trailing audio
  /// deltas (the server can't unsend audio it already streamed to us)
  bool _barged = false;

  /// response id of the reply currently streaming audio (may be null on
  /// backends that don't tag deltas, e.g. jarvis)
  String? _currentResponseId;

  /// response id we cancelled on barge-in. While barged, only deltas from THIS
  /// id are dropped; a delta from a new id (or any delta when ids are absent)
  /// clears the barge and plays - so the latch can never get stuck silencing
  /// every future reply if the backend omits response.done/created.
  String? _cancelledResponseId;

  /// true once the input transcription arrived as incremental deltas, so the
  /// terminal `.completed` transcript can be ignored (avoids duplication)
  bool _sawInputTranscriptDelta = false;

  /// true once the model's transcript arrived as incremental deltas this turn,
  /// so the terminal `.done` transcript can be ignored (avoids duplication)
  bool _sawOutputTranscriptDelta = false;

  /// decoded PCM16 response audio chunks (at the endpoint's sample rate)
  final void Function(Uint8List pcm) onAudio;

  /// the user spoke over the model: discard all buffered response audio
  final void Function() onInterrupted;

  /// true while response audio is still queued/playing on the phone or device.
  /// The barge-in logic needs this because a reply keeps playing out of the
  /// local buffer after the server has finished streaming it: the split analog
  /// of the Python sample's `_playback_pending()`.
  final bool Function()? isPlaybackPending;

  /// transcription of the user's speech (incremental fragments)
  final void Function(String text)? onInputTranscript;

  /// transcription of the model's speech (incremental fragments)
  final void Function(String text)? onOutputTranscript;

  final void Function()? onTurnComplete;

  /// connection state changes and other noteworthy events, for the UI log
  final void Function(String event)? onEvent;

  OpenAiRealtime({
    required this.onAudio,
    required this.onInterrupted,
    this.isPlaybackPending,
    this.onInputTranscript,
    this.onOutputTranscript,
    this.onTurnComplete,
    this.onEvent,
  });

  bool get isConnected => _connected;

  /// Connect to the Realtime endpoint and configure the session. Returns true
  /// once the session is ready to accept audio.
  ///
  /// [endpoint] is the full websocket URL including any model query parameter,
  /// e.g. `wss://api.openai.com/v1/realtime?model=gpt-realtime` for OpenAI, or
  /// `ws://192.168.1.10:8765/v1/realtime` for a local stack. [apiKey] may be
  /// empty for a local backend that doesn't require auth.
  Future<bool> connect({
    required String endpoint,
    required String apiKey,
    required OpenAiVoiceName voice,
    required String systemInstruction,
  }) async {
    _event('Connecting to $endpoint');
    await disconnect();

    // Auth is header-based (unlike Gemini's ?key= query param); the bearer
    // token is only sent when set (a local backend may not need one).
    final headers = <String, dynamic>{
      if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
    };

    _channel = IOWebSocketChannel.connect(Uri.parse(endpoint), headers: headers);
    await _channel!.ready;

    _channelSubs = _channel!.stream.listen(
      _handleServerMessage,
      onError: (e) => _event('Websocket error: $e'),
      onDone: () {
        _event('Websocket closed'
            '${_channel?.closeCode != null ? ' (${_channel!.closeCode}: ${_channel!.closeReason})' : ''}');
        _connected = false;
        _sessionReady = false;
      },
    );

    // Configure the session (GA shape, 24kHz PCM per the official OpenAI
    // Realtime API). Server-side VAD makes the server auto-commit the input
    // buffer and auto-create responses (hands-off), and emit
    // `input_audio_buffer.speech_started` on barge-in.
    _channel!.sink.add(jsonEncode({
      'type': 'session.update',
      'session': {
        'type': 'realtime',
        'output_modalities': ['audio'],
        'instructions': systemInstruction,
        'audio': {
          'input': {
            'format': {'type': 'audio/pcm', 'rate': serverSampleRate},
            'transcription': {'model': 'whisper-1'},
            // interrupt_response lets the server stop generating on a barge-in;
            // the client still flushes its own queued playback (below), since
            // the server can't cancel audio it has already streamed to us.
            'turn_detection': {
              'type': 'server_vad',
              'interrupt_response': true,
            },
          },
          'output': {
            'format': {'type': 'audio/pcm', 'rate': serverSampleRate},
            'voice': voice.name,
          },
        },
      }
    }));

    _connected = true;

    // The server sends `session.created` on connect and `session.updated` after
    // our update; wait (bounded) for either. Lenient local backends may emit
    // neither - after the timeout, proceed anyway rather than failing.
    final start = DateTime.now();
    while (!_sessionReady && _connected) {
      if (DateTime.now().difference(start) > const Duration(seconds: 5)) {
        _event('No session ack after 5s - proceeding anyway');
        _sessionReady = true;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }
    return _connected && _sessionReady;
  }

  Future<void> disconnect() async {
    _connected = false;
    _sessionReady = false;
    _sawInputTranscriptDelta = false;
    _sawOutputTranscriptDelta = false;
    _responseActive = false;
    _barged = false;
    _currentResponseId = null;
    _cancelledResponseId = null;
    await _channelSubs?.cancel();
    _channelSubs = null;
    await _channel?.sink.close();
    _channel = null;
  }

  /// Append a chunk of PCM16 mono audio (at the endpoint's sample rate) to the
  /// input buffer. Server-side VAD handles commit + response creation.
  void sendAudio(Uint8List pcm) {
    if (!_sessionReady) return;

    final msg = {
      'type': 'input_audio_buffer.append',
      'audio': base64Encode(pcm),
    };
    _channel!.sink.add(jsonEncode(msg));
  }

  void _handleServerMessage(dynamic message) {
    final event = jsonDecode(
        message is String ? message : utf8.decode(message as List<int>));
    final type = event['type'] as String?;

    switch (type) {
      case 'session.created':
      case 'session.updated':
        if (!_sessionReady) {
          _sessionReady = true;
          _event('Session ready');
        }
        break;

      case 'response.created':
        _responseActive = true;
        _barged = false;
        _cancelledResponseId = null;
        _currentResponseId = event['response']?['id'] as String?;
        break;

      // response audio chunk (PCM16 at the endpoint's sample rate)
      case 'response.output_audio.delta':
        final rid = event['response_id'] as String?;
        if (_barged) {
          // drop ONLY the cancelled reply's tail; a delta from a new reply (or
          // any delta when the backend omits ids) means the barge is over
          final isCancelledTail = rid != null &&
              _cancelledResponseId != null &&
              rid == _cancelledResponseId;
          if (isCancelledTail) break;
          _barged = false;
          _cancelledResponseId = null;
        }
        // Track the active reply off the audio stream, not just
        // response.created: some backends (e.g. jarvis in server-VAD mode)
        // never emit response.created for auto-created replies.
        _currentResponseId = rid;
        _responseActive = true;
        final delta = event['delta'] as String?;
        if (delta != null) onAudio(base64Decode(delta));
        break;

      // model speech transcript (incremental)
      case 'response.output_audio_transcript.delta':
        final delta = event['delta'] as String?;
        if (delta != null) {
          _sawOutputTranscriptDelta = true;
          onOutputTranscript?.call(delta);
        }
        break;

      // model speech transcript (final); some backends (e.g.
      // huggingface/speech-to-speech) send it only here, not as deltas - use it
      // then, otherwise it duplicates the streamed fragments
      case 'response.output_audio_transcript.done':
        final transcript = event['transcript'] as String?;
        if (transcript != null && !_sawOutputTranscriptDelta) {
          onOutputTranscript?.call(transcript);
        }
        break;

      // user speech transcript (incremental, when the backend streams it)
      case 'conversation.item.input_audio_transcription.delta':
        final delta = event['delta'] as String?;
        if (delta != null) {
          _sawInputTranscriptDelta = true;
          onInputTranscript?.call(delta);
        }
        break;

      // user speech transcript (final); only use it if no deltas were streamed,
      // otherwise it duplicates the accumulated fragments
      case 'conversation.item.input_audio_transcription.completed':
        final transcript = event['transcript'] as String?;
        if (transcript != null && !_sawInputTranscriptDelta) {
          onInputTranscript?.call(transcript);
        }
        _sawInputTranscriptDelta = false;
        break;

      // barge-in: the server's VAD detected the user speaking over a reply.
      // The on-device AEC keeps the assistant's own voice out of the mic, so a
      // speech_started while a reply is playing is the user talking. Cancel the
      // server's reply and flush the queued playback (the server can't unsend
      // audio it already streamed to us, so the client must drain its buffer).
      case 'input_audio_buffer.speech_started':
        final pending = _responseActive || (isPlaybackPending?.call() ?? false);
        if (!_barged && pending) {
          // latch `barged` (to drop trailing deltas) only if a reply is still
          // generating; if it already completed there is no tail to drop and
          // latching would wrongly mute the next reply. Tag the cancelled reply
          // by id so only its tail is dropped.
          _barged = _responseActive;
          _cancelledResponseId = _responseActive ? _currentResponseId : null;
          _event('---Interrupted---');
          _channel?.sink.add(jsonEncode({'type': 'response.cancel'}));
          onInterrupted();
        }
        break;

      case 'response.done':
        _responseActive = false;
        _sawOutputTranscriptDelta = false;
        // Clear the barge latch so the NEXT reply plays. The queued playback was
        // already flushed at barge-in and the cancelled reply's tail deltas are
        // dropped by id, so there is nothing left to flush here.
        _barged = false;
        _cancelledResponseId = null;
        _currentResponseId = null;
        onTurnComplete?.call();
        break;

      case 'error':
        _event('Realtime error: ${event['error']?['message'] ?? event['error']}');
        break;

      default:
        _log.fine(() => 'Unhandled event: $type');
    }
  }

  void _event(String msg) {
    _log.info(msg);
    onEvent?.call(msg);
  }
}
