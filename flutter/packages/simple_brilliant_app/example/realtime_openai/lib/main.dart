import 'dart:async';
import 'dart:typed_data';

import 'package:brilliant_ble/brilliant_device.dart';
import 'package:flutter/material.dart';
import 'package:brilliant_msg/brilliant_msg.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_brilliant_app/simple_brilliant_app.dart';

import 'lc3_decoder_service.dart';
import 'lc3_encoder_service.dart';
import 'lc3_packet_pacer.dart';
import 'openai_realtime.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

// Phone to Frame flags
const clearMsg = 0x10;
const clickSubsMsg = 0x11;
const textMsg = 0x12;
const startListeningMsg = 0x30;
const stopListeningMsg = 0x31;
const startPlaybackMsg = 0x40;
const stopPlaybackMsg = 0x41;

/// LC3 configuration, matching frame_app.lua: both the Halo microphone
/// stream and the Halo speaker run LC3 at 16kHz mono, 32kbps, 10ms frames
const lc3SampleRate = 16000;
const lc3Bitrate = 32000;
const lc3FrameDurationUs = 10000;

/// bytes per encoded LC3 frame (32kbps, 10ms -> 40 bytes); used to count how
/// many 10ms frames are in each packet sent to the device, for the playback clock
const lc3FrameBytes = lc3Bitrate ~/ 8 * lc3FrameDurationUs ~/ 1000000;

/// send mic audio in ~40-60ms batches (rather than per 10ms frame)
const micBatchBytes = 1920;

/// The Halo speaker is quiet, so run it at full volume; gain 0 maps to the
/// device's 0..20 mic-gain value 10.
const haloSpeakerVolume = 100;
const haloMicGainValue = 10;

/// Default OpenAI Realtime websocket endpoint (the model rides in the query
/// string). Point this at e.g. ws://<host>:8765/v1/realtime for a self-hosted
/// OpenAI-Realtime-compatible backend such as huggingface/speech-to-speech.
const defaultEndpoint = 'wss://api.openai.com/v1/realtime?model=gpt-realtime';


/// one entry (chat bubble) in the conversation transcript
class TranscriptEntry {
  final bool fromUser;
  String text;

  /// turn id this bubble belongs to (response id for the model, input item id
  /// for the user; null on backends that don't tag events). Used to keep two
  /// same-speaker turns in separate bubbles even when their transcripts arrive
  /// back-to-back or out of order.
  final String? turnId;

  TranscriptEntry(this.fromUser, this.text, [this.turnId]);
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {
  // user preferences
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _endpointController = TextEditingController();
  final TextEditingController _systemInstructionController =
      TextEditingController();
  OpenAiVoiceName _voiceName = OpenAiVoiceName.alloy;

  // OpenAI realtime session
  late final OpenAiRealtime _openai;

  // audio pipeline: the Halo mic/speaker LC3 streams are 16kHz, but the codec
  // decodes/encodes PCM at the endpoint's sample rate (liblc3 resamples), so
  // no separate resampler is needed.
  Lc3DecoderService? _micDecoder; // Halo mic LC3 (16kHz) -> PCM @ server rate
  Lc3EncoderService? _speakerEncoder; // PCM @ server rate -> LC3 (16kHz)
  Lc3PacketPacer? _pacer;
  final BytesBuilder _micPcmBatch = BytesBuilder(copy: false);

  // subscriptions
  StreamSubscription<Uint8List>? _micLc3Subs;
  StreamSubscription<Uint8List>? _micPcmSubs;
  StreamSubscription<Uint8List>? _speakerLc3Subs;
  StreamSubscription<ClickType>? _clickSubs;

  // conversation state
  bool _conversing = false;

  // on-device audio processing (applied at mic start). Full-duplex barge-in
  // relies on the AEC to strip the Halo speaker's bleed out of the mic, and on
  // voice mode to band-pass the AEC output so the server VAD only hears the
  // near-end - matching the Python sample's defaults (--aec-off / --no-voice-mode
  // turn them off there).
  bool _aec = true;
  bool _voiceMode = true;

  final List<TranscriptEntry> _transcript = [];
  final List<String> _eventLog = [];
  final ScrollController _transcriptScroll = ScrollController();

  // glasses display: throttled updates of the model's speech transcript
  String _displayText = '';
  Timer? _displayTimer;
  bool _displayDirty = false;

  static const _defaultSystemInstruction =
      'You are a helpful assistant speaking to the user through their '
      'smart glasses. The user hears your voice through a small speaker. '
      'Be natural, direct and concise - answer in a sentence or two where '
      'possible, without asking follow-up questions unless necessary.';

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint(
          '${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });

    _openai = OpenAiRealtime(
      onAudio: _handleOpenAiAudio,
      onInterrupted: _handleOpenAiInterrupted,
      isPlaybackPending: () => _conversing && (_pacer?.bufferedFrames ?? 0) > 0,
      onInputTranscript: (text, id) =>
          _appendTranscript(fromUser: true, text: text, turnId: id),
      onOutputTranscript: (text, id) =>
          _appendTranscript(fromUser: false, text: text, turnId: id),
      onTurnComplete: _handleTurnComplete,
      onEvent: _logEvent,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    // scan/connect to the Halo and upload the frameside app on startup;
    // the user then presses Start (or it's a no-op until they Connect)
    tryScanAndConnectAndStart(andRun: false);
  }

  @override
  void dispose() async {
    _displayTimer?.cancel();
    await _stopConversation();
    await _openai.disconnect();
    await _clickSubs?.cancel();
    _apiKeyController.dispose();
    _endpointController.dispose();
    _systemInstructionController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString('api_key') ?? '';
      _endpointController.text = prefs.getString('endpoint') ?? defaultEndpoint;
      _systemInstructionController.text =
          prefs.getString('system_instruction') ?? _defaultSystemInstruction;
      _voiceName = OpenAiVoiceName.values.asNameMap()[
              prefs.getString('voice_name') ?? OpenAiVoiceName.alloy.name] ??
          OpenAiVoiceName.alloy;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_key', _apiKeyController.text.trim());
    await prefs.setString('endpoint', _endpointController.text.trim());
    await prefs.setString(
        'system_instruction', _systemInstructionController.text);
    await prefs.setString('voice_name', _voiceName.name);
  }

  void _logEvent(String event) {
    _log.info(event);
    if (mounted) {
      setState(() {
        _eventLog.insert(0, event);
        if (_eventLog.length > 20) _eventLog.removeLast();
      });
    }
  }

  /// Connect to the Realtime endpoint and set up the audio pipeline;
  /// conversation is then started/stopped with the Halo button (or the phone UI)
  @override
  Future<void> run() async {
    if (frame!.type != BrilliantDeviceType.halo) {
      _logEvent('This example requires a Halo (LC3 audio in both directions)');
      setState(() => currentState = ApplicationState.ready);
      return;
    }

    final endpoint = _endpointController.text.trim();
    if (endpoint.isEmpty) {
      _logEvent('Enter a Realtime endpoint URL first');
      setState(() => currentState = ApplicationState.ready);
      return;
    }
    await _savePrefs();

    setState(() {
      currentState = ApplicationState.running;
      _transcript.clear();
    });

    try {
      final ok = await _openai.connect(
        endpoint: endpoint,
        apiKey: _apiKeyController.text.trim(),
        voice: _voiceName,
        systemInstruction: _systemInstructionController.text,
      );
      if (!ok) {
        setState(() => currentState = ApplicationState.ready);
        return;
      }

      // If the user pressed cancel (FAB) while we were connecting, cancel() has
      // already torn down and set the state - don't proceed and resurrect the
      // session with zombie click/display subscriptions.
      if (currentState != ApplicationState.running) {
        await _openai.disconnect();
        return;
      }

      // Halo button starts/stops the conversation
      await _clickSubs?.cancel();
      _clickSubs = RxClick().attach(frame!.dataResponse).listen(_handleClick);
      await frame!.sendMessage(clickSubsMsg, TxCode(value: 1).pack());

      // throttle glasses display updates while the model speaks
      _displayTimer?.cancel();
      _displayTimer = Timer.periodic(
          const Duration(milliseconds: 300), (_) => _updateDisplay());

      await _showOnGlasses('Click to talk');
    } catch (e) {
      _log.severe('Error starting realtime session: $e');
      await _openai.disconnect();
      // always return to ready so the FAB/footer aren't stuck disabled after a
      // failed connect (e.g. a bad endpoint URL)
      if (mounted) setState(() => currentState = ApplicationState.ready);
    }
  }

  @override
  Future<void> cancel() async {
    setState(() => currentState = ApplicationState.canceling);

    _displayTimer?.cancel();
    try {
      await _stopConversation();
      await _openai.disconnect();

      // Best-effort, timed-out device cleanup: a hung write here must not block
      // the `finally` below, or the app stays stuck in `canceling`.
      await _bleBestEffort('unsubscribe clicks',
          () => frame!.sendMessage(clickSubsMsg, TxCode(value: 0).pack()));
      await _clickSubs?.cancel();
      _clickSubs = null;
      await _bleBestEffort('clear display',
          () => frame!.sendMessage(clearMsg, TxCode().pack()));
    } catch (e) {
      _log.warning('Error during cancel: $e');
    } finally {
      // always return to ready, even if teardown partially failed, so the
      // FAB/footer don't stay stuck in the disabled `canceling` state
      if (mounted) setState(() => currentState = ApplicationState.ready);
    }
  }

  void _handleClick(ClickType type) {
    _log.fine(() => 'click: $type');
    switch (type) {
      case ClickType.single:
        _toggleConversation();
      case ClickType.double:
        // manually skip the rest of the current response audio
        _flushPlayback();
      case ClickType.long:
        break;
    }
  }

  Future<void> _toggleConversation() async {
    if (currentState != ApplicationState.running) return;

    if (_conversing) {
      await _stopConversation();
      await _showOnGlasses('Click to talk');
    } else {
      await _startConversation();
    }
    if (mounted) setState(() {});
  }

  /// Set up the bidirectional device audio streams and codecs:
  /// Halo mic LC3 -> decode -> [_handleMicPcm], and
  /// [_speakerEncoder] -> LC3 -> paced -> Halo speaker. liblc3 resamples between
  /// the Halo's 16kHz and the wire's 24kHz ([OpenAiRealtime.serverSampleRate]).
  Future<void> _startAudioPipeline() async {
    // mic: LC3 (16kHz) decoded and upsampled to 24kHz PCM for the server
    _micDecoder = Lc3DecoderService();
    await _micDecoder!.init(
      sampleRateHz: lc3SampleRate,
      pcmSampleRateHz: OpenAiRealtime.serverSampleRate,
      frameDurationUs: lc3FrameDurationUs,
      bitrate: lc3Bitrate,
    );
    _micPcmSubs = _micDecoder!.outputStream.listen(_handleMicPcm);

    // speaker: LC3 encoder (16kHz) fed with the server's 24kHz PCM (downsampled)
    _speakerEncoder = Lc3EncoderService();
    await _speakerEncoder!.init(
      sampleRateHz: lc3SampleRate,
      pcmSampleRateHz: OpenAiRealtime.serverSampleRate,
      frameDurationUs: lc3FrameDurationUs,
      targetBitrate: lc3Bitrate,
    );
    _pacer = Lc3PacketPacer(
      intervalMs: lc3FrameDurationUs ~/ 1000,
      maxBufferDelayFrames: 6000, // cap phone-side buffer at 60s of audio
      sendAudio: (data) async {
        await frame!.sendAudio(data);
        // Advance the playback clock by the real-time duration of what we just
        // sent to the device (each LC3 frame is 10ms). This is the true "audio
        // sent to the device" point, so the barge gate stays armed for the whole
        // physical playout instead of reopening the instant the client queue
        // drains (which would leak the reply's tail to the server).
        final nFrames = data.lengthInBytes ~/ lc3FrameBytes;
        if (nFrames > 0) {
          _openai.advancePlaybackClock(
              Duration(microseconds: lc3FrameDurationUs * nFrames));
        }
      },
    );
    _speakerLc3Subs = _speakerEncoder!.outputStream
        .listen((lc3Frame) => _pacer?.onNewPacketReceived(lc3Frame));

    // the mic LC3 stream closes itself on the final-chunk flag, re-attach per use
    await _micLc3Subs?.cancel();
    _micLc3Subs = RxAudio(streaming: true)
        .attach(frame!.dataResponse)
        .listen(_handleMicLc3);

    _micPcmBatch.clear();

    await frame!.sendMessage(
        startPlaybackMsg, TxCode(value: haloSpeakerVolume).pack());
    await frame!.sendMessage(startListeningMsg,
        _micStartPayload(gain: haloMicGainValue, aec: _aec, voice: _voiceMode));
  }

  /// START_LISTENING payload: three named bytes, one field each, decoded by the
  /// frame app's START_LISTENING handler:
  ///   [0] gain code 0..20 (10 = 0 dB)   [1] aec 0/1   [2] voice 0/1
  /// Maps 1:1 onto frame.microphone.start{gain=}, .aec(bool), .voice(bool).
  Uint8List _micStartPayload(
          {required int gain, required bool aec, required bool voice}) =>
      Uint8List.fromList(
          [gain.clamp(0, 20), aec ? 1 : 0, voice ? 1 : 0]);

  /// Run a best-effort BLE teardown step: bounded by a timeout and swallowing
  /// errors, so a hung or failed device write can never block teardown from
  /// reaching its terminal state. Without this, a stalled write leaves the app
  /// parked in a transient state (`canceling`/`stopping`) where the FAB is gone
  /// and every footer button is disabled - with no way out.
  Future<void> _bleBestEffort(String what, Future<void> Function() op) async {
    try {
      await op().timeout(const Duration(seconds: 2));
    } catch (e) {
      _log.warning('$what failed/timed out during teardown: $e');
    }
  }

  Future<void> _stopAudioPipeline() async {
    // Timed-out so a degraded BLE link can't hang teardown (which would strand
    // the app in a transient state where the FAB and all footer buttons are
    // disabled). See [_bleBestEffort].
    await _bleBestEffort('stop listening',
        () => frame!.sendMessage(stopListeningMsg, TxCode().pack()));
    await _bleBestEffort('stop playback',
        () => frame!.sendMessage(stopPlaybackMsg, TxCode().pack()));

    await _micLc3Subs?.cancel();
    _micLc3Subs = null;
    await _micPcmSubs?.cancel();
    _micPcmSubs = null;
    await _speakerLc3Subs?.cancel();
    _speakerLc3Subs = null;

    _micDecoder?.dispose();
    _micDecoder = null;
    _speakerEncoder?.dispose();
    _speakerEncoder = null;
    _pacer?.dispose();
    _pacer = null;
    _micPcmBatch.clear();
  }

  /// Start a conversation: connect the audio pipeline to the endpoint
  Future<void> _startConversation() async {
    if (!_openai.isConnected) {
      _logEvent('Not connected');
      return;
    }

    await _startAudioPipeline();
    _conversing = true;
    await _showOnGlasses('Listening...');
    _logEvent('Conversation started');
  }

  Future<void> _stopConversation() async {
    if (!_conversing) return;
    _conversing = false;

    await _stopAudioPipeline();
    _logEvent('Conversation stopped');
  }

  /// LC3-encoded microphone audio from the Halo
  void _handleMicLc3(Uint8List lc3Chunk) {
    _micDecoder?.sendLc3Chunk(lc3Chunk);
  }

  /// decoded PCM microphone audio (already at the endpoint's sample rate):
  /// batch and forward. Full-duplex: the mic streams continuously, even while
  /// a reply is playing, so the user can talk over it to interrupt (barge-in).
  /// The on-device AEC strips the Halo speaker's bleed out of the mic feed, so
  /// this is (mostly) near-end speech and the server VAD won't self-interrupt.
  void _handleMicPcm(Uint8List pcmFrame) {
    if (!_conversing) return;

    _micPcmBatch.add(pcmFrame);
    if (_micPcmBatch.length >= micBatchBytes) {
      _openai.sendAudio(_micPcmBatch.takeBytes());
    }
  }

  /// PCM response audio from the endpoint (at its sample rate): LC3-encode for
  /// the Halo speaker (the encoder resamples to 16kHz as needed)
  void _handleOpenAiAudio(Uint8List pcm) {
    if (!_conversing) return;
    _speakerEncoder?.sendPcmChunk(pcm);
  }

  /// the user spoke over the model: drop all queued response audio
  void _handleOpenAiInterrupted() {
    _flushPlayback();
  }

  /// discard queued response audio on the phone, and restart the Halo
  /// speaker to flush the small amount buffered on the device
  Future<void> _flushPlayback() async {
    _pacer?.clear();
    if (_conversing) {
      await frame!.sendMessage(stopPlaybackMsg, TxCode().pack());
      await frame!.sendMessage(
          startPlaybackMsg, TxCode(value: haloSpeakerVolume).pack());
    }
  }

  void _handleTurnComplete() {
    _displayDirty = true;
  }

  /// accumulate incremental transcription fragments into per-turn bubbles. A
  /// fragment extends the last bubble only when it is the same speaker AND the
  /// same turn id; otherwise it starts a new bubble. Keying on the turn id (as
  /// well as the speaker) keeps the next reply from being appended to the
  /// previous bubble when transcripts arrive back-to-back or out of order.
  void _appendTranscript(
      {required bool fromUser, required String text, String? turnId}) {
    if (!mounted) return;
    setState(() {
      final last = _transcript.isNotEmpty ? _transcript.last : null;
      if (last != null && last.fromUser == fromUser && last.turnId == turnId) {
        last.text += text;
      } else {
        _transcript.add(TranscriptEntry(fromUser, text, turnId));
      }
    });

    // mirror the model's speech on the glasses display
    if (!fromUser) {
      _displayText = _transcript.last.text;
      _displayDirty = true;
    }

    // keep the newest text visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_transcriptScroll.hasClients) {
        _transcriptScroll.jumpTo(_transcriptScroll.position.maxScrollExtent);
      }
    });
  }

  /// throttled: push the latest model speech to the glasses display
  Future<void> _updateDisplay() async {
    if (!_displayDirty || !_conversing) return;
    _displayDirty = false;

    // last few wrapped lines of the model's current utterance
    final lines = _wrapForHalo(_displayText);
    final tail = lines.length > 4 ? lines.sublist(lines.length - 4) : lines;
    await _showOnGlasses(tail.join('\n'));
  }

  /// Word-wrap for the Halo display: 256px wide, text starts at x=15, and
  /// the default Dogica 8px font is monospace at 8px per character,
  /// so (256 - 15) ~/ 8 = 30 characters fit on a line.
  static const int _haloCharsPerLine = 30;

  static List<String> _wrapForHalo(String text) {
    final lines = <String>[];
    var line = StringBuffer();
    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      var w = word;
      // hard-break words longer than a whole line
      while (w.length > _haloCharsPerLine) {
        if (line.isNotEmpty) {
          lines.add(line.toString());
          line = StringBuffer();
        }
        lines.add(w.substring(0, _haloCharsPerLine));
        w = w.substring(_haloCharsPerLine);
      }
      final needed = line.isEmpty ? w.length : line.length + 1 + w.length;
      if (needed > _haloCharsPerLine) {
        lines.add(line.toString());
        line = StringBuffer(w);
      } else {
        if (line.isNotEmpty) line.write(' ');
        line.write(w);
      }
    }
    if (line.isNotEmpty) lines.add(line.toString());
    return lines;
  }

  Future<void> _showOnGlasses(String text) async {
    try {
      await frame!.sendMessage(
          textMsg, TxPlainText(text: text, x: 15, y: 50).pack());
    } catch (e) {
      _log.warning('Error sending text to display: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenAI Realtime',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
            title: const Text('OpenAI Realtime'),
            actions: [getBatteryWidget()]),
        body: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _apiKeyController,
                      obscureText: true,
                      decoration: const InputDecoration(
                          hintText: 'OpenAI API key (blank for local backend)'),
                      enabled: currentState != ApplicationState.running,
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<OpenAiVoiceName>(
                    value: _voiceName,
                    onChanged: currentState == ApplicationState.running
                        ? null
                        : (v) => setState(
                            () => _voiceName = v ?? OpenAiVoiceName.alloy),
                    items: OpenAiVoiceName.values
                        .map((v) =>
                            DropdownMenuItem(value: v, child: Text(v.name)))
                        .toList(),
                  ),
                ],
              ),
              TextField(
                controller: _endpointController,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                    labelText: 'Realtime endpoint (wss:// or ws://)'),
                enabled: currentState != ApplicationState.running,
              ),
              TextField(
                controller: _systemInstructionController,
                maxLines: 2,
                style: const TextStyle(fontSize: 12),
                decoration:
                    const InputDecoration(labelText: 'System instruction'),
                enabled: currentState != ApplicationState.running,
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Echo cancellation (AEC)'),
                subtitle: const Text(
                    'On-device AEC removes the speaker bleed so the mic can '
                    'stay open for barge-in'),
                value: _aec,
                onChanged: _conversing
                    ? null
                    : (v) => setState(() => _aec = v),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Voice mode'),
                subtitle: const Text(
                    'Band-pass the AEC output so the server VAD only hears '
                    'near-end speech'),
                value: _voiceMode,
                onChanged: _conversing
                    ? null
                    : (v) => setState(() => _voiceMode = v),
              ),
              if (currentState == ApplicationState.running)
                Card(
                  child: ListTile(
                    leading: Icon(_conversing ? Icons.mic : Icons.mic_off,
                        color: _conversing ? Colors.green : Colors.orange),
                    title: Text(_conversing
                        ? 'Conversing - click the Halo (or tap here) to stop'
                        : 'Click the Halo (or tap here) to talk'),
                    subtitle: _conversing
                        ? const Text('Double-click the Halo to skip a reply')
                        : null,
                    onTap: _toggleConversation,
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(
                flex: 3,
                child: _transcript.isEmpty
                    ? const Center(
                        child: Text(
                            'Connect and Start, then click the Halo button '
                            'and speak.\nLive transcripts appear here.',
                            textAlign: TextAlign.center))
                    : ListView.builder(
                        controller: _transcriptScroll,
                        itemCount: _transcript.length,
                        itemBuilder: (context, index) {
                          final entry = _transcript[index];
                          return Card(
                            color: entry.fromUser
                                ? Colors.blueGrey.shade800
                                : Colors.grey.shade900,
                            child: ListTile(
                              dense: true,
                              leading: Icon(entry.fromUser
                                  ? Icons.person
                                  : Icons.smart_toy),
                              title: Text(entry.text),
                            ),
                          );
                        }),
              ),
              const Divider(),
              Expanded(
                flex: 1,
                child: ListView.builder(
                    reverse: true,
                    itemCount: _eventLog.length,
                    itemBuilder: (context, index) => Text(_eventLog[index],
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white54))),
              ),
            ],
          ),
        ),
        floatingActionButton: getFloatingActionButtonWidget(
            const Icon(Icons.chat), const Icon(Icons.cancel)),
        persistentFooterButtons: getFooterButtonsWidget(),
      ),
    );
  }
}
