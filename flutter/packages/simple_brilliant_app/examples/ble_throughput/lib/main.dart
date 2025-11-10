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

  int _bytesReceived = 0;
  int _numPackets = 0;
  int _mtu = 0;
  final _stopwatch = Stopwatch();
  int _millis = 0;
  static const totalPacketCount = 4000;
  StreamSubscription<List<int>>? dataResponseSubs;

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

  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      _mtu = frame!.maxStringLength ?? 0;
      // attach a handler to listen for the data
      dataResponseSubs?.cancel();
      dataResponseSubs = frame!.dataResponse.listen( (data) {
        // count the bytes received
        if (data.length > 1 && data[0] == 0x30) {
          _bytesReceived += data.length;
          _numPackets++;
          _millis = _stopwatch.elapsedMilliseconds;
          setState(() {});

          if (_numPackets == totalPacketCount) {
            _stopwatch.stop();
            _log.info("All packets received");
            // when done, set the state back to ready
            currentState = ApplicationState.ready;
            setState(() {});
          }
        }
      });

      // start a stopwatch to measure the time taken to receive the data
      // and count the bytes received
      setState(() {
        _bytesReceived = 0;
        _numPackets = 0;
        _millis = 0;
      });

      _stopwatch.reset();
      _stopwatch.start();

      // tell Frame/Halo to start streaming data
      await frame!.sendMessage(0x30, TxCode().pack());

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
            child: Text("Packets received: $_numPackets\nBytes received: $_bytesReceived\nMTU: $_mtu\nPacket size: ${_numPackets == 0 ? 0 : _bytesReceived/_numPackets}\nElapsed time (ms): $_millis\nThroughput (kbps): ${_millis == 0 ? 0 : (8 * _bytesReceived / 1024 / _millis * 1000).toStringAsFixed(0)}\nThroughput (kBps): ${_millis == 0 ? 0 : (_bytesReceived / 1024 / _millis * 1000).toStringAsFixed(2)}")
          ),
          floatingActionButton: getFloatingActionButtonWidget(
              const Icon(Icons.mic), const Icon(Icons.stop)),
          persistentFooterButtons: getFooterButtonsWidget(),
        ));
  }
}
