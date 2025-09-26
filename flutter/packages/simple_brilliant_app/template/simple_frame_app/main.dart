import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:frame_msg/tx/code.dart';
import 'package:frame_msg/tx/plain_text.dart';

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
      // TODO do something, e.g. send some text, wait a while, send a clear message
      // Check the assets/frame_app.lua to find the corresponding frameside handling for these (arbitrarily-chosen) msgCodes
      final plainText = TxPlainText(text: 'Hello, Frame!');
      await frame!.sendMessage(0x12, plainText.pack());

      await Future.delayed(const Duration(seconds: 10));

      final code = TxCode();
      await frame!.sendMessage(0x10, code.pack());

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
        title: 'Simple Frame App Template',
        theme: ThemeData.dark(),
        home: Scaffold(
          appBar: AppBar(
              title: const Text('Simple Frame App Template'),
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
