import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';

import 'package:brilliant_ble/brilliant_device.dart';
import 'package:brilliant_msg/rx/audio.dart';
import 'package:brilliant_msg/tx/code.dart';
import 'package:brilliant_msg/tx/image_sprite_block.dart';
import 'package:brilliant_msg/tx/sprite.dart';
import 'package:simple_brilliant_app/simple_brilliant_app.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

// Phone to Frame flags (match assets/frame_app.lua)
const imageSpriteBlockMsg = 0x20;
const audioStartMsg = 0x40;
const audioStopMsg = 0x41;

// LC3 with 10 ms frames: bitrate / 800 bytes per frame (40 bytes at 32 kbps)
const framesPerSecond = 100;

// the speaker clip: LC3 at 8 kHz, 32 kbps, 10 ms frames
const speakerRate = 8000;
const speakerKbps = 32;
const speakerFrameBytes = speakerKbps * 1000 ~/ 800;

// --dart-define=DURATION=120 to stream for longer
const streamDuration = Duration(seconds: int.fromEnvironment('DURATION', defaultValue: 30));
// --dart-define=AUTORUN=true starts streaming as soon as the app connects (for unattended testing)
const autoRun = bool.fromEnvironment('AUTORUN');
const speakerVolume = 80;
// seconds of speaker audio to keep queued on the device
const speakerLead = 0.3;
const micRate = 16000;
const micKbps = 32;
// ask Halo to request this connection interval (ms); the phone decides
const connectionIntervalMs = 15;
const stripHeight = 16;

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {

  bool _withImages = true;
  bool _withMic = true;
  bool _cancelled = false;
  final List<String> _lines = [];
  List<TxImageSpriteBlock>? _blocks;

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

  @override
  void initState() {
    super.initState();

    // start up if the Frame can be found
    tryScanAndConnectAndStart(andRun: autoRun);
  }

  void _addLine(String line) {
    _log.info(line);
    if (mounted) setState(() => _lines.add(line));
  }

  /// Square crops of the koala photo, each numbered so new images are visible on the display
  Future<List<TxImageSpriteBlock>> _makeImages(int count, {int size = 128}) async {
    var src = img.decodeJpg((await rootBundle.load('assets/koala.jpg')).buffer.asUint8List())!;
    final side = math.min(src.width, src.height);
    src = img.copyCrop(src, x: (src.width - side) ~/ 2, y: (src.height - side) ~/ 2, width: side, height: side);
    final zoom = (side * 0.8).toInt();
    return [
      for (var n = 0; n < count; n++)
        () {
          // pan the crop a little each time so every image is different
          final x = ((side - zoom) * n / math.max(1, count - 1)).toInt();
          var image = img.copyResize(img.copyCrop(src, x: x, y: 0, width: zoom, height: zoom),
              width: size, height: size, interpolation: img.Interpolation.average);
          img.drawString(image, n.toString().padLeft(2, '0'), font: img.arial14, x: 4, y: 4, color: img.ColorRgb8(255, 255, 0));
          final sprite = TxSprite.fromImageBytes(imageBytes: img.encodePng(image));
          return TxImageSpriteBlock(image: sprite, spriteLineHeight: stripHeight);
        }()
    ];
  }

  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    _cancelled = false;
    _lines.clear();
    if (mounted) setState(() {});

    StreamSubscription<String>? stdoutSubs;
    StreamSubscription<Uint8List>? micSubs;
    var micBytes = 0;
    final micDone = Completer<void>();

    try {
      if (frame!.type != BrilliantDeviceType.halo) {
        _addLine('This example requires a Halo (speaker and LC3 microphone)');
        return;
      }

      _blocks ??= await _makeImages(16);
      final lc3Data = (await rootBundle.load('assets/female_w1_8k_s16.lc3')).buffer.asUint8List();
      final lc3Frames = [
        for (var i = 0; i + speakerFrameBytes <= lc3Data.length; i += speakerFrameBytes)
          lc3Data.sublist(i, i + speakerFrameBytes)
      ];

      final mtu = frame!.device.mtuNow;
      final framesPerWrite = math.max(1, bleWriteSize(math.min(mtu - 3, 512)) ~/ speakerFrameBytes);
      _addLine('ATT MTU $mtu | $framesPerWrite LC3 frames (${framesPerWrite * speakerFrameBytes} bytes) per speaker write');

      // the device prints its speaker/microphone stats every 2 seconds
      stdoutSubs = frame!.stringResponse.listen((s) {
        if (s.startsWith('stats')) _addLine(s.substring(6));
      });

      if (_withMic) {
        micSubs = RxAudio(streaming: true).attach(frame!.dataResponse).listen(
          (chunk) => micBytes += chunk.length,
          onDone: () => micDone.complete());
      }

      await frame!.sendMessage(audioStartMsg, Uint8List.fromList([
        speakerRate ~/ 1000, speakerKbps, speakerVolume,
        micRate ~/ 1000, _withMic ? micKbps : 0, connectionIntervalMs]));

      final stopwatch = Stopwatch()..start();
      bool running() => !_cancelled && stopwatch.elapsed < streamDuration;

      // speaker: keep speakerLead seconds queued ahead of where playback should be
      var sent = 0;
      var writes = 0;
      var minLead = speakerLead;
      var maxWriteGap = Duration.zero;
      var lastWrite = Duration.zero;
      Future<void> speaker() async {
        final leadFrames = (speakerLead * framesPerSecond).toInt();
        while (running()) {
          final played = stopwatch.elapsedMicroseconds * framesPerSecond / 1000000;
          if (sent > 0) minLead = math.min(minLead, (sent - played) / framesPerSecond);
          while (sent < played + leadFrames) {
            final chunk = BytesBuilder(copy: false);
            for (var i = 0; i < framesPerWrite; i++) {
              chunk.add(lc3Frames[(sent + i) % lc3Frames.length]);
            }
            await frame!.sendAudio(chunk.toBytes());
            sent += framesPerWrite;
            writes++;
            final now = stopwatch.elapsed;
            if (now - lastWrite > maxWriteGap) maxWriteGap = now - lastWrite;
            lastWrite = now;
          }
          await Future.delayed(const Duration(milliseconds: 10));
        }
      }

      // images: the header once, then each image's strips update the block in place
      var images = 0;
      var imageBytes = 0;
      Future<void> imageStream() async {
        await frame!.sendMessage(imageSpriteBlockMsg, _blocks![0].pack());
        while (running()) {
          for (var strip in _blocks![images % _blocks!.length].spriteLines) {
            final packed = strip.pack();
            await frame!.sendMessage(imageSpriteBlockMsg, packed);
            imageBytes += packed.length;
          }
          images++;
        }
      }

      await Future.wait([speaker(), if (_withImages) imageStream()]);
      final elapsed = stopwatch.elapsedMilliseconds / 1000;

      // let the queued speaker audio play out and the last stats print
      await Future.delayed(Duration(milliseconds: (speakerLead * 1000).toInt() + 2500));
      await frame!.sendMessage(audioStopMsg, TxCode(value: 0).pack());
      if (_withMic) {
        await micDone.future.timeout(const Duration(seconds: 3), onTimeout: () => _addLine('microphone end-of-stream not received'));
      }

      _addLine('--- ${elapsed.toStringAsFixed(1)} s ---');
      _addLine('speaker: $sent frames in $writes writes '
          '(${(sent * speakerFrameBytes * 8 / elapsed / 1000).toStringAsFixed(1)} kbps), '
          'min lead ${(minLead * 1000).round()} ms, longest gap between writes ${maxWriteGap.inMilliseconds} ms');
      if (_withImages) {
        _addLine('images: $images (${(images / elapsed).toStringAsFixed(2)}/s, '
            '${(imageBytes * 8 / elapsed / 1000).round()} kbps)');
      }
      if (_withMic) {
        final micFrames = micBytes ~/ (micKbps * 1000 ~/ 800);
        _addLine('mic: $micFrames frames (${(micFrames / framesPerSecond).toStringAsFixed(1)} s of audio)');
      }
    } catch (e) {
      _addLine('Error: $e');
      try {
        await frame!.sendMessage(audioStopMsg, TxCode(value: 0).pack());
      } catch (_) {}
    } finally {
      await stdoutSubs?.cancel();
      await micSubs?.cancel();
      currentState = ApplicationState.ready;
      if (mounted) setState(() {});
    }
  }

  @override
  Future<void> cancel() async {
    // run() sees this, stops streaming and reports
    _cancelled = true;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Duplex Sprites',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Audio Duplex Sprites'),
          actions: [getBatteryWidget()]
        ),
        body: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                title: const Text('Stream images'),
                value: _withImages,
                onChanged: currentState == ApplicationState.running ? null : (v) => setState(() => _withImages = v)),
              SwitchListTile(
                title: const Text('Stream microphone'),
                value: _withMic,
                onChanged: currentState == ApplicationState.running ? null : (v) => setState(() => _withMic = v)),
              Expanded(
                child: ListView(
                  children: [for (var line in _lines) Text(line, style: const TextStyle(fontFamily: 'monospace', fontSize: 11))],
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: getFloatingActionButtonWidget(const Icon(Icons.play_arrow), const Icon(Icons.stop)),
        persistentFooterButtons: getFooterButtonsWidget(),
      )
    );
  }
}
