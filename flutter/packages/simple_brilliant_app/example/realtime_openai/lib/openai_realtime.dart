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
            'turn_detection': {'type': 'server_vad'},
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

      // response audio chunk (PCM16 at the endpoint's sample rate)
      case 'response.output_audio.delta':
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

      // barge-in: the server's VAD detected the user speaking; drop queued
      // response audio (the server cancels its own in-flight response)
      case 'input_audio_buffer.speech_started':
        _event('---Interrupted---');
        onInterrupted();
        break;

      case 'response.done':
        _sawOutputTranscriptDelta = false;
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
