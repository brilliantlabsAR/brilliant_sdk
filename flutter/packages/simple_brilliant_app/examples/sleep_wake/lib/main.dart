import 'package:flutter/material.dart';
import 'package:frame_msg/tx/code.dart';
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
  // Message codes for Frame communication
  static const int _msgCodeStandby = 0x40;
  static const int _msgCodeWakeup = 0x41;

  String _status = '';

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
    tryScanAndConnectAndStart(andRun: false);
  }

  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      // Send standby command to Frame
      _log.info('Sending standby command');
      _status = 'Standby...';
      if (mounted) setState(() {});
      await frame!.sendMessage(_msgCodeStandby, TxCode().pack());

      // Wait for wakeup source print from Frame Lua app
      _log.info('Frame entering standby, waiting for wakeup...');
      final source = await frame!.stringResponse
          .firstWhere((s) => s.startsWith('Wakeup source:'));

      _log.info('Frame woke up: $source');
      _status = source;
      if (mounted) setState(() {});
    } catch (e) {
      _log.fine(() => 'Error executing application logic: $e');
    }

    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  Future<void> _sendWakeup() async {
    try {
      _log.info('Sending BLE wakeup');
      await frame!.sendMessage(_msgCodeWakeup, TxCode().pack());
    } catch (e) {
      _log.fine(() => 'Error sending wakeup: $e');
    }
  }

  @override
  Future<void> cancel() async {
    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'Sleep Wake',
        theme: ThemeData.dark(),
        home: Scaffold(
          appBar: AppBar(
              title: const Text('Sleep Wake'),
              actions: [getBatteryWidget()]),
          body: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Center(
                  child: Text(
                    _status,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
          floatingActionButton: currentState == ApplicationState.running
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton(
                      heroTag: 'wakeup',
                      onPressed: _sendWakeup,
                      child: const Icon(Icons.bluetooth),
                    ),
                    const SizedBox(height: 12),
                    FloatingActionButton(
                      heroTag: 'cancel',
                      onPressed: cancel,
                      child: const Icon(Icons.close),
                    ),
                  ],
                )
              : getFloatingActionButtonWidget(
                  const Icon(Icons.bedtime), const Icon(Icons.close)),
          persistentFooterButtons: getFooterButtonsWidget(),
        ));
  }
}
