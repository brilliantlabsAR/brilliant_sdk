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
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    final textStrings = [
      "your local\nweather is\n30° celsius\nand sunny",
      "私たちは\n知識を強化し\n理解を深め\n創造性を解き放ち",
      "우리는 지식을\n갖추게 하고\n이해를 심화시키며\n창의력을 발휘하고",
      "ہم ایسے اوزار\nبنانے\nکے لیے موجود ہیں\nجو ہمیں علم سے "
    ];

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
            width: 216,
            lineHeight: 24,
            fontSize: 16,
            maxDisplayLines: 4,
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

        currentState = ApplicationState.ready;
        if (mounted) setState(() {});
      } catch (e) {
        _log.fine(() => 'Error executing application logic: $e');
        currentState = ApplicationState.ready;
        if (mounted) setState(() {});
      }
    }
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
