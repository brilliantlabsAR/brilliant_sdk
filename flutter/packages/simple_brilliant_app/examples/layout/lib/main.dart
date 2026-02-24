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

    try {
      _log.info("Starting layout");

      // Check the assets/frame_app.lua to find the corresponding frameside handling for these (arbitrarily-chosen) msgCodes
      var txcRecord = TxCode(value: 1);
      await frame!.sendMessage(0x40, txcRecord.pack());

      await Future.delayed(const Duration(seconds: 3));

      var txcSpeech = TxCode(value: 1);
      await frame!.sendMessage(0x41, txcSpeech.pack());


      // # Send the text for display
      // # Note that the frameside app is expecting a message of type TxTextSpriteBlock on msgCode 0x20
      // # the width needs to match the NoaLayout body width (216)
      // tsb = TxTextSpriteBlock(width=216,
      //                         line_height=25,
      //                         font_size=20,
      //                         max_display_lines=4,
      //                         font_family="fonts/dogicapixel.ttf"
      // )
      final tsb = TxTextSpriteBlock(
          width: 216,
          lineHeight: 25,
          fontSize: 20,
          maxDisplayLines: 4,
          fontFamily: "fonts/dogicapixel.ttf");

      final spriteLines = await tsb.createTextSprites("your local\nweather is\n30° celsius\nand sunny");

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

      await Future.delayed(const Duration(seconds: 3));

      currentState = ApplicationState.ready;
      if (mounted) setState(() {});
    } catch (e) {
      _log.fine(() => 'Error executing application logic: $e');
      currentState = ApplicationState.ready;
      if (mounted) setState(() {});
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
          body: const Padding(
            padding: EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Spacer(),
              ],
            ),
          ),
          floatingActionButton: getFloatingActionButtonWidget(
              const Icon(Icons.file_open), const Icon(Icons.close)),
          persistentFooterButtons: getFooterButtonsWidget(),
        ));
  }
}
