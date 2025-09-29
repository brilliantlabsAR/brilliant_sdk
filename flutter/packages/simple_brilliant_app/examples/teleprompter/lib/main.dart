import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logging/logging.dart';

import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:simple_frame_app/tx/code.dart';
import 'package:simple_frame_app/tx/text_sprite_block.dart';


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
      debugPrint('${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

  // teleprompter data - text and current chunk
  final List<String> _textChunks = [];
  int _currentLine = -1;
  TextDirection _textDir = TextDirection.ltr;
  int _textSizeIndex = 1;
  final List<int> _textSizeValues = [16, 32, 48, 64];

  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    try {
      // Open the file picker
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );

      if (result != null) {
        File file = File(result.files.single.path!);

        // Read the file content and split into lines
        String content = await file.readAsString();
        _textChunks.clear();

        // Update the UI
        setState(() {
          // strip out any carriage-return characters if the file is CRLF
          content = content.replaceAll(RegExp('\r'), '');
          _textChunks.addAll(content.split('\n'));
          _currentLine = 0;
        });

        // and send initial text to Frame
        await sendTextToFrame(_textChunks[_currentLine]);
      }
      else {
        currentState = ApplicationState.ready;
        if (mounted) setState(() {});
      }
    } catch (e) {
      _log.fine('Error executing application logic: $e');
      currentState = ApplicationState.ready;
      if (mounted) setState(() {});
    }
  }

  /// create the TextSpriteBlock for the specified text, then send the TSB header and line sprites one by one
  Future<void> sendTextToFrame(String text) async {
    if (text.isEmpty) {
      // just send a Clear Display message
      await frame!.sendMessage(TxCode(msgCode: 0x10));
      return;
    }

    var tsb = TxTextSpriteBlock(
      msgCode: 0x20,
      width: 620,
      fontSize: _textSizeValues[_textSizeIndex],
      maxDisplayRows: 10,
      textDirection: _textDir,
      textAlign: TextAlign.start,
      text: text,
    );

    // rasterize the text to sprites
    await tsb.rasterize(startLine: 0, endLine: tsb.numLines - 1);

    // send the TxTextSpriteBlock lines to Frame for display
    // block header first
    await frame!.sendMessage(tsb);

    // send over the lines one by one
    // note that the sprites have the same message code, so they need to be handled by the text_sprite_block parser
    for (var sprite in tsb.rasterizedSprites) {
      await frame!.sendMessage(sprite);
    }
  }

  @override
  Future<void> cancel() async {
    // send a Clear Display message
    await frame!.sendMessage(TxCode(msgCode: 0x10));

    currentState = ApplicationState.ready;
    _textChunks.clear();
    _currentLine = -1;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frame Teleprompter Universal',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Frame Teleprompter Universal'),
          actions: [getBatteryWidget()]
        ),
        drawer: Drawer(
          child: ListView(
            padding: EdgeInsets.zero,
            children: <Widget>[
              const DrawerHeader(
                decoration: BoxDecoration(
                  color: Colors.blue,
                ),
                child: Text('Settings',
                  style: TextStyle(color: Colors.white, fontSize: 24),
                  ),
              ),
              ListTile(
                title: const Text('Text Size'),
                subtitle: Slider(
                  value: _textSizeIndex.toDouble(),
                  min: 0,
                  max: _textSizeValues.length - 1,
                  divisions: _textSizeValues.length - 1,
                  label: _textSizeValues[_textSizeIndex].toStringAsFixed(0),
                  onChanged: (value) {
                    setState(() {
                      _textSizeIndex = value.toInt();
                    });
                  },
                  onChangeEnd: (value) {
                    if (currentState == ApplicationState.running) {
                      sendTextToFrame(_textChunks[_currentLine]);
                    }
                  },
                ),
              ),
              RadioListTile<TextDirection>(
                title: const Text('Left Align'),
                value: TextDirection.ltr,
                groupValue: _textDir,
                onChanged: (value) {
                  setState(() {
                    _textDir = value ?? TextDirection.ltr;
                    if (currentState == ApplicationState.running) {
                      sendTextToFrame(_textChunks[_currentLine]);
                    }
                  });
                },
              ),
              RadioListTile<TextDirection>(
                title: const Text('Right Align'),
                value: TextDirection.rtl,
                groupValue: _textDir,
                onChanged: (value) {
                  setState(() {
                    _textDir = value ?? TextDirection.rtl;
                    if (currentState == ApplicationState.running) {
                      sendTextToFrame(_textChunks[_currentLine]);
                    }
                  });
                },
              ),
            ],
          ),
        ),
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragEnd: (x) async {
              if (x.velocity.pixelsPerSecond.dy > 0) {
                _currentLine > 0 ? --_currentLine : null;
              }
              else {
                _currentLine < _textChunks.length - 1 ? ++_currentLine : null;
              }
              if (_currentLine >= 0) {
                await sendTextToFrame(_textChunks[_currentLine]);
              }
              if (mounted) setState(() {});
            },
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Text(
                  _currentLine >= 0 ? _textChunks[_currentLine] : 'Load a file',
                  style: const TextStyle(fontSize: 24),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
        floatingActionButton: getFloatingActionButtonWidget(const Icon(Icons.file_open), const Icon(Icons.close)),
        persistentFooterButtons: getFooterButtonsWidget(),
      )
    );
  }
}
