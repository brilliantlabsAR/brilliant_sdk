import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frame_msg/frame_msg.dart';
import 'package:frame_msg/tx/text_sprite_block.dart';
import 'package:logging/logging.dart';

import 'package:simple_frame_app/simple_frame_app.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {
  // Message codes for frame communication (arbitrarily-chosen identifiers)
  static const int _msgCodeLayout = 0x60;
  static const int _msgCodeRecordingMode = 0x40;
  static const int _msgCodeSpeechWave = 0x41;
  static const int _msgCodeTextSprite = 0x50;
  static const int _msgCodeClearText = 0x51;
  static const int _msgCodeImageSprite = 0x52;
  static const int _msgCodeClearImage = 0x53;

  Uint8List? _pngBytes;

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint(
          '${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

  @override
  void initState() {
    super.initState();

    // if possible, connect right away and load files
    tryScanAndConnectAndStart(andRun: true);
  }

  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      await _runEncounterLayout();
      await _runSpeechLayout();
      await _runTextLayout();
    } catch (e) {
      _log.fine(() => 'Error executing application logic: $e');
    }
    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  Future<void> _runTextLayout() async {
    _log.info("Starting TextLayout");

    final textStrings = [
      "We exist to build tools that empower knowledge, deepen understanding, unleash creativity, and foster empathy—all in service of our shared prosperity.\nAlways open source, we believe the future of computing belongs to all of us.",
      "我们致力于打造能够赋能知识、加深理解、激发创造力并培养同理心的工具——所有这一切都旨在服务于我们共同的繁荣。\n我们始终坚持开源，并坚信计算的未来属于我们所有人。",
      "私たちは、知識を強化し、理解を深め、創造性を解き放ち、共感を育むツールを構築するために存在しています。これらはすべて、私たちの共通の繁栄のために役立っています。\n常にオープンソースであり続ける私たちは、コンピューティングの未来は私たち全員のものだと確信しています。",
      "우리는 지식을 갖추게 하고, 이해를 심화시키며, 창의력을 발휘하고, 공감을 촉진하는 도구를 만들기 위해 존재합니다. 모두 우리의 공동 번영을 위해 봉사합니다.\n항상 오픈 소스로 제공되는 우리는 컴퓨팅의 미래가 우리 모두에 의해 구축되어야 한다고 믿습니다.",
      "ہم ایسے اوزار بنانے کے لیے موجود ہیں جو ہمیں علم سے آراستہ کرتے ہیں، سمجھ کو گہرا کرتے ہیں، تخلیقی صلاحیتوں کو جنم دیتے ہیں، اور ہمدردی کو فروغ دیتے ہیں - یہ سب کچھ ہماری مشترکہ خوشحالی کی خدمت میں ہے۔\nہمیشہ اوپن سورس، ہمیں یقین ہے کہ کمپیوٹنگ کا مستقبل ہم سب کے ذریعہ بنایا جانا چاہیے۔"
    ];

    final numLines = [4, 6, 8, 10];
    final fontSizes = [20, 16, 11, 8];
    final lineHeights = [28, 20, 15, 12];

    var txcLayout = TxCode(value: 1);
    await frame!.sendMessage(_msgCodeLayout, txcLayout.pack());

    for (int i = 0; i < numLines.length; i++) {
      final num = numLines[i];
      final fontSize = fontSizes[i];
      final lineHeight = lineHeights[i];

      for (int i = 0; i < textStrings.length; i++) {
        final txt = textStrings[i];

        // Check the assets/frame_app.lua to find the corresponding frameside handling for these (arbitrarily-chosen) msgCodes
        var txcRecord = TxCode(value: 1);
        await frame!.sendMessage(_msgCodeRecordingMode, txcRecord.pack());

        await Future.delayed(const Duration(seconds: 3));

        final tsb = TxTextSpriteBlock(
            width: 186, // Note: match body width in noa_layout.lua (256 - 2*35)
            lineHeight: lineHeight, // 17 (5 lines), 21 (4 lines), 28 (3 lines)
            fontSize: fontSize, // 12 (5 lines), 16 (4 lines), 20 (3 lines)
            maxDisplayLines: num, // 5, 4 or 3
            fontFamily: "DogicaPixel");

        final spriteLines = await tsb.createTextSprites(txt);

        _pngBytes = await tsb.toPngBytes(rasterizedSprites: spriteLines);
        if (mounted) setState(() {});

        // send the Text Sprite Block header
        await frame!.sendMessage(_msgCodeTextSprite, tsb.pack());

        // then send all the slices
        for (var spr in spriteLines) {
          await frame!.sendMessage(_msgCodeTextSprite, spr.pack());
          await Future.delayed(const Duration(milliseconds: 500));
        }

        // in recording mode for 4 seconds
        await Future.delayed(const Duration(seconds: 4));

        // clear the text
        final txcClearTxt = TxCode(value: 0);
        await frame!.sendMessage(_msgCodeClearText, txcClearTxt.pack());

        await Future.delayed(const Duration(seconds: 2));

        // send a code to switch off recording mode
        txcRecord = TxCode(value: 0);
        await frame!.sendMessage(_msgCodeRecordingMode, txcRecord.pack());

        await Future.delayed(const Duration(seconds: 3));
      }
    }
    _log.info("Ending TextLayout");
  }

  Future<void> _runSpeechLayout() async {
    _log.info("Starting SpeechLayout");

    var txcLayout = TxCode(value: 2);
    await frame!.sendMessage(_msgCodeLayout, txcLayout.pack());

    var txcRecord = TxCode(value: 1);
    await frame!.sendMessage(_msgCodeRecordingMode, txcRecord.pack());

    await Future.delayed(const Duration(seconds: 3));

    // send a code to switch on speech wave animation
    var txcSpeech = TxCode(value: 1);
    await frame!.sendMessage(_msgCodeSpeechWave, txcSpeech.pack());

    await Future.delayed(const Duration(seconds: 5));

    // send a code to switch off speech wave animation
    txcSpeech = TxCode(value: 0);
    await frame!.sendMessage(_msgCodeSpeechWave, txcSpeech.pack());

    await Future.delayed(const Duration(seconds: 5));

    // send a code to switch off speech wave animation
    txcSpeech = TxCode(value: 0);
    await frame!.sendMessage(_msgCodeSpeechWave, txcSpeech.pack());

    _log.info("Ending SpeechLayout");
  }

  Future<void> _runEncounterLayout() async {
    _log.info("Starting EncounterLayout");
    var txcLayout = TxCode(value: 3);
    await frame!.sendMessage(_msgCodeLayout, txcLayout.pack());

    // load the noa_demon asset and turn it into a sprite
    _log.info("Loading PNG asset");
    final byteData = await rootBundle.load('assets/images/noa_demon.png');
    final Uint8List demonBytes = byteData.buffer.asUint8List();

    // preview the image we're about to send
    _pngBytes = demonBytes;
    if (mounted) setState(() {});

    _log.info("Creating TxSprite from asset bytes");
    TxSprite sprite = TxSprite.fromPngBytes(pngBytes: demonBytes);

    // create a new TxSprite with a circular crop at the bottom
    Uint8List maskedPixels = applyCircleMask(sprite.pixelData);
    TxSprite maskedSprite = TxSprite(
      width: sprite.width,
      height: sprite.height,
      numColors: sprite.numColors,
      paletteData: sprite.paletteData,
      pixelData: maskedPixels,
    );

    // slice it into an image sprite block and send the header
    TxImageSpriteBlock isb = TxImageSpriteBlock(image: maskedSprite, spriteLineHeight: 16);
    _log.info("Sending header");
    await frame!.sendMessage(_msgCodeImageSprite, isb.pack());
    await Future.delayed(const Duration(milliseconds: 500));

    _log.info("Sending sprite lines");
    // then send all the slices
    for (var spr in isb.spriteLines) {
      await frame!.sendMessage(_msgCodeImageSprite, spr.pack());
    }

    final tsb = TxTextSpriteBlock(
        width: 146, // Note: match body width in encounter_layout.lua
        lineHeight: 20,
        fontSize: 16,
        maxDisplayLines: 3,
        fontFamily: "DogicaPixel");

    final spriteLines = await tsb.createTextSprites("Let's play some Pong, jerk face!");

    _pngBytes = await tsb.toPngBytes(rasterizedSprites: spriteLines);
    if (mounted) setState(() {});

    // send the Text Sprite Block header
    await frame!.sendMessage(_msgCodeTextSprite, tsb.pack());

    // then send all the slices
    for (var spr in spriteLines) {
      await frame!.sendMessage(_msgCodeTextSprite, spr.pack());
    }

    await Future.delayed(const Duration(seconds: 5));

    // clear the image and the text
    final txcClearImg = TxCode(value: 0);
    await frame!.sendMessage(_msgCodeClearImage, txcClearImg.pack());

    final txcClearTxt = TxCode(value: 0);
    await frame!.sendMessage(_msgCodeClearText, txcClearTxt.pack());

    _log.info("Ending EncounterLayout");
  }

  /// Apply a circular mask to the bottom of the image to avoid drawing over the 
  /// circular boundary in the encounter layout. 
  /// This is a simple pixel manipulation that sets pixels 
  /// outside the circle to transparent (0).
  /// The input byte array is one byte per pixel with a palette index 0..15
  /// which is the format used for the TxSprite pixelData
  /// Calibrated for 128x128 images with a circle centered at (63, 18) and radius 110.
  Uint8List applyCircleMask(Uint8List pixels) {
    const int cx = 63, cy = 18, r2 = 110 * 110;
    const int width = 128;

    for (int y = 107; y < 128; y++) {
      final int dy = y - cy;
      final int dx = sqrt((r2 - dy * dy).toDouble()).floor();
      final int xMin = (cx - dx).clamp(0, width);
      final int xMax = (cx + dx + 1).clamp(0, width);

      final int rowOffset = y * width;
      pixels.fillRange(rowOffset, rowOffset + xMin, 0);
      pixels.fillRange(rowOffset + xMax, rowOffset + width, 0);
    }
    return pixels;
  }

  @override
  Future<void> cancel() async {
    // TODO any logic while canceling?

    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Layout',
        theme: ThemeData.dark(),
        home: Scaffold(
          appBar: AppBar(
              title: const Text('Layout'),
              actions: [getBatteryWidget()]),
          body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                if (_pngBytes != null)
                  Center(
                    child: Image.memory(_pngBytes!),
                  ),
                const Spacer(),
              ],
            ),
          ),
          floatingActionButton: getFloatingActionButtonWidget(
              const Icon(Icons.file_open), const Icon(Icons.close)),
          persistentFooterButtons: getFooterButtonsWidget(),
        ));
  }
}
