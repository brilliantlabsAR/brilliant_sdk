import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:logging/logging.dart';

import 'package:brilliant_ble/brilliant_device.dart';
import 'package:simple_brilliant_app/simple_brilliant_app.dart';
import 'package:brilliant_msg/tx/code.dart';
import 'package:brilliant_msg/tx/text_page.dart';


void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {

  // teleprompter data - pages of text to display
  final List<PageData> _pages = [];
  int _currentPage = -1;
  TextDirection _textDir = TextDirection.ltr;
  int _textSizeIndex = 1;
  final List<int> _textSizeValues = [16, 20, 24, 28, 32, 48, 64];
  Uint8List _pngBytes = Uint8List(0);
  String _content = '';
  
  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
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

    try {
      // Open the file picker
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );

      if (result != null) {
        File file = File(result.files.single.path!);

        // Read the file content
        // (strip out any carriage-return characters if the file is CRLF)
        _content = (await file.readAsString()).replaceAll(RegExp('\r'), '');

        // lay out the text into pages and send the first page to Frame
        _currentPage = 0;
        await _layoutAndShowPages();
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

  /// (re)lay out the loaded text with the current text size and alignment,
  /// then show the current page (e.g. after the settings change)
  Future<void> _layoutAndShowPages() async {
    final textAlign = _textDir == TextDirection.ltr ? TextAlign.left : TextAlign.right;

    // Halo's display is round: fit each line to the circle's chord at its height
    final TextLayout layout = frame!.type == BrilliantDeviceType.halo
        ? CircularTextLayout(width: 256, height: 256,
            fontSize: _textSizeValues[_textSizeIndex],
            textAlign: textAlign)
        : RectangularTextLayout(width: 256, height: 256,
            fontSize: _textSizeValues[_textSizeIndex],
            textAlign: textAlign);

    var tp = TxTextPage(
      layout: layout,
      text: _content,
    );

    final List<PageData> pages = [];
    while (tp.hasMoreText) {
      final page = await tp.measureNextPage();
      if (page != null) {
        pages.add(page);
      }
    }

    if (pages.isEmpty) return;

    _pages
      ..clear()
      ..addAll(pages);
    // the page count changes with the text size, so stay within range
    _currentPage = _currentPage.clamp(0, _pages.length - 1);

    // rasterize the current page and create a PNG image of it
    await _pages[_currentPage].rasterize();
    _pngBytes = await _pages[_currentPage].toPngBytes();
    if (mounted) setState(() {});

    await sendTextToFrame(_pages[_currentPage]);
  }

  /// send the page header and then its line sprites one by one
  Future<void> sendTextToFrame(PageData page) async {
    // start by sending a Clear Display message
    await frame!.sendMessage(0x10, TxCode().pack());

    if (page.isEmpty) {
      return;
    }
    else if (!page.isRasterized) {
      await page.rasterize();
    }

    // send the page to Frame for display
    // page header (with each line's x/y offset) first
    await frame!.sendMessage(0x20, page.pack());

    // send over the lines one by one
    // note that the sprites have the same message code, so they need to be handled by the text_page parser
    for (var sprite in page.rasterizedSprites) {
      await frame!.sendMessage(0x20, sprite.pack());
    }
  }

  @override
  Future<void> cancel() async {
    // send a Clear Display message
    await frame!.sendMessage(0x10, TxCode().pack());

    currentState = ApplicationState.ready;
    _pages.clear();
    _currentPage = -1;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Teleprompter',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Teleprompter'),
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
                      _layoutAndShowPages();
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
                      _layoutAndShowPages();
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
                      _layoutAndShowPages();
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
                _currentPage > 0 ? --_currentPage : null;
              }
              else {
                _currentPage < _pages.length - 1 ? ++_currentPage : null;
              }
              if (_currentPage >= 0) {
                _pngBytes = await _pages[_currentPage].toPngBytes();
                await sendTextToFrame(_pages[_currentPage]);
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
                if (_currentPage >= 0)
                  ..._pages[_currentPage].lineTexts.map((line) =>
                   Center(
                     child: 
                      Text(
                        line,
                        style: const TextStyle(fontSize: 16),
                      ),
                   ),
                  )
                else
                  const Center(child: Text('Load a file', style: TextStyle(fontSize: 12))),
                const Spacer(),
                // insert an image of the current TextSpriteBlock here
                if (_currentPage >= 0 && _pngBytes.isNotEmpty)
                  Center(
                    child: Image.memory(_pngBytes, width: 256, height: 256, fit: BoxFit.contain),
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
