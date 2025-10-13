import 'dart:async';

import 'package:flutter/material.dart';
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
  void initState() {
    super.initState();

    tryScanAndConnectAndStart(andRun: false);
  }

  @override
  void dispose() async {

    super.dispose();
  }

  /// Start recording audio on Frame
  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      // attach a handler to listen for the data
      frame!.dataResponse.listen( (data) {
        // TODO count the bytes received
        if (data.isEmpty) {
          // end of data
          // TODO stop stopwatch and calculate rate
          // TODO set state back to ready
        } else {
          // TODO add data length to byte counter
        }
      });

      // start a stopwatch to measure the time taken to receive the data
      // and count the bytes received
      // TODO reset byte counter
      // TODO start stopwatch     

      // tell Frame to start streaming data
      await frame!.sendMessage(0x30, TxCode().pack());

      // TODO when the data is all received, send some data and measure the rate

      // when done, set the state back to ready
      currentState = ApplicationState.ready;

    } catch (e) {
      _log.fine('Error executing application logic: $e');
      currentState = ApplicationState.ready;
      if (mounted) setState(() {});
    }
  }

  /// Stop the streaming data test
  @override
  Future<void> cancel() async {

    // in canceling state, the user can't click other buttons to start/stop
    // and the state will return to ready when the data is all received
    setState(() {
      currentState = ApplicationState.canceling;
    });

    // tell Frame to stop streaming data
    await frame!.sendMessage(0x31, TxCode().pack());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'BLE Throughput Tester',
        theme: ThemeData.dark(),
        home: Scaffold(
          appBar: AppBar(
              title: const Text('BLE Throughput Tester'),
              actions: [getBatteryWidget()]),
          body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: const Text("Placeholder for BLE throughput test app")
          ),
          floatingActionButton: getFloatingActionButtonWidget(
              const Icon(Icons.mic), const Icon(Icons.stop)),
          persistentFooterButtons: getFooterButtonsWidget(),
        ));
  }
}
