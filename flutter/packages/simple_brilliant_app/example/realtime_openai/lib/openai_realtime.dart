import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
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

  /// after this long with no new reply audio, treat the reply as no longer
  /// streaming. Used instead of a sticky "response active" flag: some backends
  /// (e.g. jarvis in server-VAD mode) send neither response.created nor
  /// response.done, so a flag keyed on those would stick and make every later
  /// user turn spuriously barge.
  static const Duration _playbackIdle = Duration(seconds: 1);

  /// time the last reply audio delta arrived (null if none yet / reply ended)
  DateTime? _lastAudioTime;

  /// Playback clock: the time the DEVICE finishes physically playing out
  /// everything sent to it so far. Advanced by [advancePlaybackClock] from the
  /// pacer (the true "audio sent to the device" point) - NOT from when a delta
  /// was received. The client streams a reply to the device faster than it plays
  /// (generation finishes in ~1-2s; playout takes several real-time seconds), so
  /// keying "is a reply playing?" on the client queue reopens the mic gate-off
  /// mid-playout and leaks the reply's tail to the server. Init to the epoch.
  DateTime _playUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// How long after [_playUntil] a reply still counts as playing, covering the
  /// on-device / in-flight buffer latency (the device buffers a few hundred ms
  /// ahead of the speaker). Matches the Python sample's PLAYBACK_TAIL_S.
  static const Duration _playbackTail = Duration(milliseconds: 600);

  // --- RMS barge-in gate (see [bargeRms]) -------------------------------------
  // While a reply is playing, hold the mic closed to the server and open it only
  // once the near-end AC-RMS confirms the wearer is talking OVER it, so the
  // assistant's post-AEC echo residual can't be transcribed as a phantom turn and
  // spiral on a sensitive server VAD. Ported verbatim from the Python sample.
  bool _gateOpen = false; // currently forwarding near-end during playback
  int _gateHot = 0; // consecutive above-threshold reads (to open)
  double _gatePeak = 0; // loudest read while arming (logged on open)
  double _gateQuietMs = 0; // accumulated sub-threshold audio (to close)
  final Queue<Uint8List> _preroll = ListQueue(); // onset back-fill on open

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

  /// transcription of the user's speech (incremental fragments). [turnId] is the
  /// input item id (null on backends that don't tag events); consecutive
  /// fragments sharing a turnId belong to the same utterance / chat bubble.
  final void Function(String text, String? turnId)? onInputTranscript;

  /// transcription of the model's speech (incremental fragments). [turnId] is
  /// the response id (null on backends that don't tag events); consecutive
  /// fragments sharing a turnId belong to the same reply / chat bubble.
  final void Function(String text, String? turnId)? onOutputTranscript;

  final void Function()? onTurnComplete;

  /// connection state changes and other noteworthy events, for the UI log
  final void Function(String event)? onEvent;

  /// RMS barge-in gate: near-end AC-RMS a mic read must clear to open the mic to
  /// the server WHILE a reply is playing, so the assistant's echo can't
  /// self-interrupt a sensitive server VAD. Worn-tuned: real barges opened at
  /// 475-1700, a stray echo/hallucination open landed ~337, so 400 sits in the
  /// gap. `bargeRms <= 0` disables the gate entirely (full duplex - use for a
  /// backend that doesn't trip on the residual, e.g. jarvis/Silero).
  final double bargeRms;

  /// consecutive above-threshold mic reads needed to open the gate (debounce;
  /// higher = fewer false barges, slightly slower onset). Clamped to >= 1.
  final int confirmFrames;

  /// sub-threshold audio after which an open gate re-closes (keep short so it
  /// doesn't forward echo into the next reply)
  final double hangoverMs;

  OpenAiRealtime({
    required this.onAudio,
    required this.onInterrupted,
    this.isPlaybackPending,
    this.onInputTranscript,
    this.onOutputTranscript,
    this.onTurnComplete,
    this.onEvent,
    this.bargeRms = 400.0,
    this.confirmFrames = 3,
    this.hangoverMs = 400.0,
  });

  /// [confirmFrames] with the Python sample's `max(1, ...)` floor applied
  int get _confirmFrames => confirmFrames < 1 ? 1 : confirmFrames;

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
    // Bound the handshake: an unreachable host / bad endpoint can otherwise leave
    // `.ready` pending indefinitely, stranding the caller in its "connecting"
    // (running) state with only a cancel FAB. On timeout or refusal, fail cleanly
    // so the caller can return to a usable state.
    try {
      await _channel!.ready.timeout(const Duration(seconds: 10));
    } catch (e) {
      _event('Failed to open connection: $e');
      await disconnect();
      return false;
    }

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
            // threshold (default 0.5) is raised to 0.6 so the assistant's own
            // residual echo (post-AEC bleed) is less likely to trip the VAD and
            // self-interrupt; raise further if it still self-interrupts, lower
            // if it misses genuine barge-ins.
            'turn_detection': {
              'type': 'server_vad',
              'threshold': 0.6,
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
    _lastAudioTime = null;
    _barged = false;
    _currentResponseId = null;
    _cancelledResponseId = null;
    _playUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _resetGate();
    // Never throw: closing a channel whose connection failed (e.g. a bad URL,
    // where `.ready` threw) can raise, and callers reset UI state after this -
    // an exception here must not prevent that.
    try {
      await _channelSubs?.cancel().timeout(const Duration(seconds: 2));
    } catch (_) {}
    _channelSubs = null;
    try {
      // Bounded: closing a websocket sink whose `.ready` rejected (e.g. the
      // connection was refused - wrong host/port) can hang forever, which would
      // stall connect()'s own cleanup and any cancel()/teardown that awaits this,
      // stranding the app in a transient state with no usable controls.
      await _channel?.sink.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
    _channel = null;
  }

  /// Append a chunk of PCM16 mono audio (at the endpoint's sample rate) to the
  /// input buffer, RMS-gated during playback. Server-side VAD handles commit +
  /// response creation.
  ///
  /// With the gate disabled ([bargeRms] <= 0) or when no reply is playing, the
  /// mic streams straight through - normal full-duplex listening / turn-taking.
  /// While a reply IS playing, the mic is held closed and only opened once the
  /// near-end AC-RMS clears the gate for [confirmFrames] consecutive reads, so
  /// the server never hears (and so never transcribes and answers) the
  /// assistant's own echo. On open we back-fill the buffered onset so the barge's
  /// first word isn't clipped; the gate then stays open through the utterance,
  /// re-closing after [hangoverMs] of near-silence. Ported from the Python
  /// sample's `_forward_mic`.
  void sendAudio(Uint8List pcm) {
    if (!_sessionReady) return;

    if (bargeRms <= 0 || !_playbackPending) {
      // gate disabled, or nothing playing: stream through; reset gate state
      _resetGate();
      _sendMic(pcm);
      return;
    }

    // DC-removed (AC) RMS: the echo residual is low-energy post-AEC even though
    // it is speech-shaped, so measure ENERGY (std), not level (see [bargeRms]).
    final rms = _acRms(pcm);
    final nSamples = pcm.lengthInBytes ~/ 2;
    final durMs = 1000.0 * nSamples / serverSampleRate;

    if (_gateOpen) {
      // stay open through the utterance; close after a beat of near-silence
      if (rms < bargeRms) {
        _gateQuietMs += durMs;
      } else {
        _gateQuietMs = 0;
      }
      if (_gateQuietMs < hangoverMs) {
        _sendMic(pcm);
        return;
      }
      _gateOpen = false; // fell quiet: re-close and re-arm below
      _gateHot = 0;
      _gateQuietMs = 0;
    }

    // gate closed: buffer the onset and count consecutive above-threshold reads
    _preroll.addLast(pcm);
    while (_preroll.length > _confirmFrames) {
      _preroll.removeFirst();
    }
    if (rms >= bargeRms) {
      _gateHot += 1;
      _gatePeak = math.max(_gatePeak, rms);
    } else {
      _gateHot = 0;
      _gatePeak = 0;
    }
    if (_gateHot >= _confirmFrames) {
      // confirmed near-end: open, back-fill the buffered onset, then stream.
      // Log the RMS that opened it: an open near the threshold (rather than well
      // above it) is echo leaking through - raise [bargeRms] if so.
      _event('[gate open] near-end rms=${_gatePeak.toStringAsFixed(0)}');
      _gateOpen = true;
      _gateQuietMs = 0;
      _gateHot = 0;
      _gatePeak = 0;
      for (final buffered in _preroll) {
        _sendMic(buffered);
      }
      _preroll.clear();
    }
    // else: closed + unconfirmed -> drop this block (echo-only); the server
    // never sees it, so it can't spiral
  }

  /// Actually append a mic block to the server input buffer (post-gate).
  void _sendMic(Uint8List pcm) {
    if (!_sessionReady) return;
    _channel!.sink.add(jsonEncode({
      'type': 'input_audio_buffer.append',
      'audio': base64Encode(pcm),
    }));
  }

  void _resetGate() {
    _gateOpen = false;
    _gateHot = 0;
    _gatePeak = 0;
    _gateQuietMs = 0;
    _preroll.clear();
  }

  /// DC-removed (AC) RMS over a PCM16 block: the standard deviation of the
  /// samples. Dart has no numpy, so compute it directly.
  double _acRms(Uint8List pcm) {
    final s = Int16List.view(
        pcm.buffer, pcm.offsetInBytes, pcm.lengthInBytes ~/ 2);
    if (s.length < 2) return 0;
    double mean = 0;
    for (final v in s) {
      mean += v;
    }
    mean /= s.length;
    double sq = 0;
    for (final v in s) {
      final d = v - mean;
      sq += d * d;
    }
    return math.sqrt(sq / s.length);
  }

  /// Advance the playback clock by [sent] - the real-time duration of the audio
  /// just dispatched to the DEVICE (fed from the pacer, the true "audio sent to
  /// the device" point). The barge gate stays armed for the whole physical
  /// playout, not just while the client queue is non-empty. See [_playUntil].
  void advancePlaybackClock(Duration sent) {
    final now = DateTime.now();
    _playUntil = (_playUntil.isAfter(now) ? _playUntil : now).add(sent);
  }

  /// True while the DEVICE is still playing a reply out (not merely while the
  /// client still holds audio): the injected queue check is a floor for the
  /// instant between enqueue and the first device send, ORed with the playback
  /// clock (+[_playbackTail]) which covers the physical playout the client
  /// queue has already drained ahead of. Split analog of the Python sample's
  /// `_playback_pending()`.
  bool get _playbackPending =>
      (isPlaybackPending?.call() ?? false) ||
      DateTime.now().isBefore(_playUntil.add(_playbackTail));

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
        // Mark the reply streaming off the audio stream (see _recentAudio):
        // some backends (e.g. jarvis in server-VAD mode) send neither
        // response.created nor response.done, so a fresh delta is the only
        // reliable "a reply is playing" signal.
        _currentResponseId = rid;
        _lastAudioTime = DateTime.now();
        final delta = event['delta'] as String?;
        if (delta != null) onAudio(base64Decode(delta));
        break;

      // model speech transcript (incremental); key the bubble by response id
      case 'response.output_audio_transcript.delta':
        final delta = event['delta'] as String?;
        if (delta != null) {
          _sawOutputTranscriptDelta = true;
          onOutputTranscript?.call(delta, _outputTurnId(event));
        }
        break;

      // model speech transcript (final); some backends (e.g.
      // huggingface/speech-to-speech) send it only here, not as deltas - use it
      // then, otherwise it duplicates the streamed fragments
      case 'response.output_audio_transcript.done':
        final transcript = event['transcript'] as String?;
        if (transcript != null && !_sawOutputTranscriptDelta) {
          onOutputTranscript?.call(transcript, _outputTurnId(event));
        }
        break;

      // user speech transcript (incremental, when the backend streams it); key
      // the bubble by input item id
      case 'conversation.item.input_audio_transcription.delta':
        final delta = event['delta'] as String?;
        if (delta != null) {
          _sawInputTranscriptDelta = true;
          onInputTranscript?.call(delta, event['item_id'] as String?);
        }
        break;

      // user speech transcript (final); only use it if no deltas were streamed,
      // otherwise it duplicates the accumulated fragments
      case 'conversation.item.input_audio_transcription.completed':
        final transcript = event['transcript'] as String?;
        if (transcript != null && !_sawInputTranscriptDelta) {
          onInputTranscript?.call(transcript, event['item_id'] as String?);
        }
        _sawInputTranscriptDelta = false;
        break;

      // barge-in: the server's VAD detected the user speaking over a reply.
      // The on-device AEC keeps the assistant's own voice out of the mic, so a
      // speech_started while a reply is playing is the user talking. The server
      // stops generating on its own (interrupt_response, set in the session);
      // the client just flushes the queued playback and drops the cancelled
      // reply's tail (the server can't unsend audio it already streamed to us).
      // We deliberately do NOT send response.cancel: the server has usually
      // already cancelled the response by now, so it would race and error with
      // "Cancellation failed: no active response found".
      case 'input_audio_buffer.speech_started':
        final live = _recentAudio;
        final pending = live || _playbackPending;
        if (!_barged && pending) {
          // latch `barged` (to drop trailing deltas) only if a reply is still
          // streaming; if it already finished there is no tail to drop and
          // latching would wrongly mute the next reply. Tag the cancelled reply
          // by id so only its tail is dropped.
          _barged = live;
          _cancelledResponseId = live ? _currentResponseId : null;
          _event('---Interrupted---');
          onInterrupted();
        }
        break;

      case 'response.done':
        // (OpenAI sends this; jarvis doesn't - the barge logic no longer
        // depends on it, but honour it when present.) Clear the barge latch so
        // the NEXT reply plays; the queued playback was already flushed at
        // barge-in and the cancelled reply's tail deltas are dropped by id.
        _sawOutputTranscriptDelta = false;
        _barged = false;
        _cancelledResponseId = null;
        _currentResponseId = null;
        _lastAudioTime = null;
        onTurnComplete?.call();
        break;

      case 'error':
        _event('Realtime error: ${event['error']?['message'] ?? event['error']}');
        break;

      default:
        _log.fine(() => 'Unhandled event: $type');
    }
  }

  /// True if a reply is actively streaming - audio arrived within [_playbackIdle].
  /// Used instead of a sticky flag so a backend that never sends response.done
  /// can't leave a reply flagged live forever (which would make every later user
  /// turn spuriously barge).
  bool get _recentAudio =>
      _lastAudioTime != null &&
      DateTime.now().difference(_lastAudioTime!) < _playbackIdle;

  /// bubble key for a model transcript event: the response id, falling back to
  /// the item id (either may be absent on backends that don't tag events)
  String? _outputTurnId(Map<String, dynamic> event) =>
      event['response_id'] as String? ?? event['item_id'] as String?;

  void _event(String msg) {
    _log.info(msg);
    onEvent?.call(msg);
  }
}
