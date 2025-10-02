import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:frame_msg/tx/image_sprite_block.dart';
import 'package:logging/logging.dart';

import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:frame_msg/tx/code.dart';
import 'package:frame_msg/tx/sprite.dart';


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
  Image? _image;

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
    tryScanAndConnectAndStart(andRun: true);
  }

  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      _log.fine('Running application logic');

      while (currentState == ApplicationState.running) {
        var msg = TxCode();
        await frame!.sendMessage(0x11, msg.pack());
        await Future.delayed(const Duration(milliseconds: 900));
        await frame!.sendMessage(0x11, msg.pack());
        await Future.delayed(const Duration(milliseconds: 300));
        await frame!.sendMessage(0x11, msg.pack());
        await Future.delayed(const Duration(milliseconds: 300));
        await frame!.sendMessage(0x10, msg.pack());
        await Future.delayed(const Duration(milliseconds: 1000));
      }

      // // Open the file picker
      // FilePickerResult? result = await FilePicker.platform.pickFiles(
      //   type: FileType.image,
      // );

      // if (result != null) {
      //   File file = File(result.files.single.path!);

      //   // Read the file content
      //   Uint8List imageBytes = await file.readAsBytes();

      //   // Update the UI
      //   setState(() {
      //     _image = Image.memory(imageBytes);
      //   });

      //   // make the sprite
      //   var sprite = TxSprite.fromImageBytes(imageBytes: imageBytes);

      //   var isb = TxImageSpriteBlock(image: sprite, spriteLineHeight: 10);
      //   // send the header first
      //   await frame!.sendMessage(0x20, isb.pack());

      //   // then send all the slices
      //   for (var line in isb.spriteLines) {
      //     await frame!.sendMessage(0x20, line.pack());
      //   }
      // }
      // else {
      //   currentState = ApplicationState.ready;
      //   if (mounted) setState(() {});
      // }
    } catch (e) {
      _log.fine('Error executing application logic: $e');
      currentState = ApplicationState.ready;
      if (mounted) setState(() {});
    }
  }

  @override
  Future<void> cancel() async {
    // remove the displayed image
    var msg = TxCode(value: 1);
    await frame!.sendMessage(0x10, msg.pack());
    _image = null;

    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sprite Animation',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Sprite Animation'),
          actions: [getBatteryWidget()]
        ),
        body: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              if (_image != null) _image!,
              const Spacer(),
            ],
          ),
        ),
        floatingActionButton: getFloatingActionButtonWidget(const Icon(Icons.file_open), const Icon(Icons.close)),
        persistentFooterButtons: getFooterButtonsWidget(),
      )
    );
  }
}
