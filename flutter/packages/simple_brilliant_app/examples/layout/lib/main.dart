import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:frame_msg/tx/text_sprite_block.dart';
import 'package:logging/logging.dart';

import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:frame_msg/tx/code.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {
  Uint8List? pngBytes;

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

    final textStrings = [
      "We exist to build tools that empower knowledge, deepen understanding, unleash creativity, and foster empathy—all in service of our shared prosperity.\nAlways open source, we believe the future of computing belongs to all of us.",
      "我们致力于打造能够赋能知识、加深理解、激发创造力并培养同理心的工具——所有这一切都旨在服务于我们共同的繁荣。\n我们始终坚持开源，并坚信计算的未来属于我们所有人。",
      "私たちは、知識を強化し、理解を深め、創造性を解き放ち、共感を育むツールを構築するために存在しています。これらはすべて、私たちの共通の繁栄のために役立っています。\n常にオープンソースであり続ける私たちは、コンピューティングの未来は私たち全員のものだと確信しています。",
      "우리는 지식을 갖추게 하고, 이해를 심화시키며, 창의력을 발휘하고, 공감을 촉진하는 도구를 만들기 위해 존재합니다. 모두 우리의 공동 번영을 위해 봉사합니다.\n항상 오픈 소스로 제공되는 우리는 컴퓨팅의 미래가 우리 모두에 의해 구축되어야 한다고 믿습니다.",
      "ہم ایسے اوزار بنانے کے لیے موجود ہیں جو ہمیں علم سے آراستہ کرتے ہیں، سمجھ کو گہرا کرتے ہیں، تخلیقی صلاحیتوں کو جنم دیتے ہیں، اور ہمدردی کو فروغ دیتے ہیں - یہ سب کچھ ہماری مشترکہ خوشحالی کی خدمت میں ہے۔\nہمیشہ اوپن سورس، ہمیں یقین ہے کہ کمپیوٹنگ کا مستقبل ہم سب کے ذریعہ بنایا جانا چاہیے۔"
    ];

    final numLines = [3, 4, 5];
    final fontSizes = [20, 16, 12];
    final lineHeights = [28, 21, 17];


    for (int i = 0; i < numLines.length; i++) {
      final num = numLines[i];
      final fontSize = fontSizes[i];
      final lineHeight = lineHeights[i];

      for (int i = 0; i < textStrings.length; i++) {
        final txt = textStrings[i];

        try {
          _log.info("Starting layout");

          // Check the assets/frame_app.lua to find the corresponding frameside handling for these (arbitrarily-chosen) msgCodes
          var txcRecord = TxCode(value: 1);
          await frame!.sendMessage(0x40, txcRecord.pack());

          await Future.delayed(const Duration(seconds: 3));

          var txcSpeech = TxCode(value: 1);
          await frame!.sendMessage(0x41, txcSpeech.pack());


          final tsb = TxTextSpriteBlock(
              width: 186, // Note: match body width in noa_layout.lua (256 - 2*35)
              lineHeight: lineHeight, // 17 (5 lines), 21 (4 lines), 28 (3 lines)
              fontSize: fontSize, // 12 (5 lines), 16 (4 lines), 20 (3 lines)
              maxDisplayLines: num, // 5, 4 or 3
              fontFamily: "DogicaPixel");

          final spriteLines = await tsb.createTextSprites(txt);

          pngBytes = await tsb.toPngBytes(rasterizedSprites: spriteLines);
          if (mounted) setState(() {});


          // send the Text Sprite Block header
          await frame!.sendMessage(0x50, tsb.pack());

          // then send all the slices
          for (var spr in spriteLines) {
            await frame!.sendMessage(0x50, spr.pack());
            await Future.delayed(const Duration(milliseconds: 500));
          }

          // send a code to switch off speech wave animation
          txcSpeech = TxCode(value: 0);
          await frame!.sendMessage(0x41, txcSpeech.pack());

          // in recording mode for 4 seconds
          await Future.delayed(const Duration(seconds: 4));

          // clear the text
          final txcClearTxt = TxCode(value: 0);
          await frame!.sendMessage(0x51, txcClearTxt.pack());

          await Future.delayed(const Duration(seconds: 2));

          // send a code to switch off recording mode
          txcRecord = TxCode(value: 0);
          await frame!.sendMessage(0x40, txcRecord.pack());

          await Future.delayed(const Duration(seconds: 3));

          _log.info("Stopping layout");

        } catch (e) {
          _log.fine(() => 'Error executing application logic: $e');
          currentState = ApplicationState.ready;
          if (mounted) setState(() {});
          break;
        }
      }
    }

    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
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
                if (pngBytes != null)
                  Center(
                    child: Image.memory(pngBytes!),
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
