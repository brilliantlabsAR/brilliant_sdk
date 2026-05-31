import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'dart:convert';

import 'package:simple_brilliant_app/simple_brilliant_app.dart';
import 'package:brilliant_msg/tx/code.dart';

import 'sfxr.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {

  // show the loaded image in the Flutter UI also
  late TextEditingController _jsonController;
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

  @override
  void initState() {
    super.initState();
    _jsonController = TextEditingController();

    // start up if the Frame can be found
    tryScanAndConnectAndStart(andRun: false);
  }

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      // try to parse the JSON description from the text box
      final jsonString = _jsonController.text;
      final jsonLength = jsonString.length;
      try {
        final jsonData = json.decode(jsonString);
        _log.info('JSON length: $jsonLength, Valid JSON: true');

        // make a TxSfxr from the JSON data
        final sfxr = TxSfxr.fromJson(jsonData);
        
        // send the SFXR to Halo to play
        await frame!.sendMessage(0x20, sfxr.pack());

        await Future.delayed(const Duration(milliseconds: 3000));

        currentState = ApplicationState.ready;
        if (mounted) setState(() {});
        return;

      } catch (e) {
        _log.warning('JSON length: $jsonLength, Valid JSON: false');
        // pop up a toast indicating invalid JSON
        _messengerKey.currentState?.showSnackBar(const SnackBar(content: Text('Invalid JSON')));

        currentState = ApplicationState.ready;
        if (mounted) setState(() {});
        return;
      }

    } catch (e) {
      _log.fine('Error executing application logic: $e');
      currentState = ApplicationState.ready;
      if (mounted) setState(() {});
    }
  }

  Future<void> runRandom() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
        // send the code telling Halo to generate and play a random SFXR sound effect
        await frame!.sendMessage(0x21, TxCode().pack());

        await Future.delayed(const Duration(milliseconds: 3000));

        currentState = ApplicationState.ready;
        if (mounted) setState(() {});
        return;
    } catch (e) {
      _log.fine('Error executing application logic: $e');
      currentState = ApplicationState.ready;
      if (mounted) setState(() {});
    }
  }

  @override
  Future<void> cancel() async {
    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  FloatingActionButton? getRandomFloatingActionButtonWidget(
    Icon ready, Icon running) {
    return currentState == ApplicationState.ready
        ? FloatingActionButton(onPressed: runRandom, child: ready)
        : currentState == ApplicationState.running
            ? FloatingActionButton(onPressed: cancel, child: running)
            : null;
  }


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sound Effect Player',
      theme: ThemeData.dark(),
      home: ScaffoldMessenger(
        key: _messengerKey,
        child: Scaffold(
        appBar: AppBar(
          title: const Text('Sound Effect Player'),
          actions: [getBatteryWidget()]
        ),
        body: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: TextField(
                  controller: _jsonController,
                  onSubmitted: (value) {
                    // Handle JSON submission
                  },
                  decoration: const InputDecoration(
                    labelText: 'Enter SFXR JSON',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: null,
                  expands: true,
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            getRandomFloatingActionButtonWidget(const Icon(Icons.tag_faces_rounded), const Icon(Icons.stop)) ?? const SizedBox.shrink(),
            const SizedBox(height: 16),
            getFloatingActionButtonWidget(const Icon(Icons.play_arrow), const Icon(Icons.stop)) ?? const SizedBox.shrink(),
          ],
        ),
        persistentFooterButtons: getFooterButtonsWidget(),
      ),
    ),
    );
  }
}
