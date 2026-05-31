import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:brilliant_ble/brilliant_device.dart';
import 'package:brilliant_msg/rx/click.dart';
import 'package:logging/logging.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_brilliant_app/brilliant_vision_app.dart';
import 'package:simple_brilliant_app/simple_brilliant_app.dart';
import 'package:brilliant_msg/tx/plain_text.dart';

import 'api_call.dart';
import 'foreground_service.dart';
import 'text_pagination.dart';

void main() {
  // Set up Android foreground service
  initializeForegroundService();

  runApp(const MainApp());
}

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  MainAppState createState() => MainAppState();
}

/// BrilliantVisionAppState mixin provides scaffolding for photo capture on (multi-) tap and a mechanism for processing each photo
/// in addition to the connection and application state management provided by SimpleFrameAppState
class MainAppState extends State<MainApp> with SimpleFrameAppState, BrilliantVisionAppState {

  // Custom API state
  String _apiEndpoint = '';
  final TextEditingController _apiEndpointTextFieldController = TextEditingController();
  final TextEditingController _promptTextFieldController = TextEditingController();

  // the image and metadata to show
  Image? _image;
  Uint8List? _imageData;
  ImageMetadata? _imageMeta;
  bool _processing = false;

  // the response to show, and the timer to clear it after 10s
  Timer? _clearTimer;
  final List<String> _responseTextList = [];
  final TextPagination _pagination = TextPagination();

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: ${record.time}: ${record.message}');
    });
  }

  @override
  void dispose() {
    _apiEndpointTextFieldController.dispose();
    _promptTextFieldController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    // Frame connection and saved text field loading need to be performed asynchronously
    asyncInit();
  }

  Future<void> asyncInit() async {
    await _loadApiEndpoint();

    // kick off the connection to Frame and start the app if possible (unawaited)
    tryScanAndConnectAndStart(andRun: true);
  }

  Future<void> _loadApiEndpoint() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      _apiEndpoint = prefs.getString('api_endpoint') ?? '';
      _apiEndpointTextFieldController.text = _apiEndpoint;
    });
  }

  Future<void> _saveApiEndpoint() async {
    _apiEndpoint = _apiEndpointTextFieldController.text;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_endpoint', _apiEndpoint);
  }

  @override
  Future<void> onRun() async {
    TxPlainText msg;

    if (frame!.type == BrilliantDeviceType.halo) {
      msg = TxPlainText(text: 'Long-Click: take photo\n______________\n1-Click: next page\n2-Click: previous page');
    } else {
      msg = TxPlainText(text: '3-Tap: take photo\n______________\n1-Tap: next page\n2-Tap: previous page');
    }

    await frame!.sendMessage(0x0a,msg.pack());
  }

  @override
  Future<void> onCancel() async {
    _responseTextList.clear();
    _pagination.clear();
  }

  @override
  Future<void> onTap(int taps) async {
    switch (taps) {
      case 1:
        await _nextPage();
        break;
      case 2:
        await _previousPage();
        break;
      case 3:
        await _requestNewPhoto();
        break;
      default:
    }
  }

  @override
  Future<void> onClick(ClickType type) async {
    switch (type) {
      case ClickType.single:
        await _nextPage();
      case ClickType.double:
        await _previousPage();
      case ClickType.long:
        await _requestNewPhoto();
    }
  }

  Future<void> _requestNewPhoto() async {
    // check if there's processing in progress already and drop the request if so
    if (!_processing) {
      _processing = true;
      // start new vision capture
    
      // Cancel any pending clear operations
      _clearTimer?.cancel();
      _clearTimer = null;
    
      // show we're capturing on the Frame display
      await frame!.sendMessage(0x0a,
        TxPlainText(
          text: '\u{F0007}', // starry eyes emoji
          paletteOffset: 8, // yellow
        ).pack()
      );
    
      // asynchronously kick off the capture/processing pipeline
      capture().then(process);
    }
  }

  Future<void> _previousPage() async {
    // Cancel any pending clear operations
    _clearTimer?.cancel();
    _clearTimer = null;
    
    // prev
    _pagination.previousPage();
    await frame!.sendMessage(0x0a,
      TxPlainText(
        text: _pagination.getCurrentPage().join('\n')
      ).pack()
    );
  }

  Future<void> _nextPage() async {
    // Cancel any pending clear operations
    _clearTimer?.cancel();
    _clearTimer = null;
    
    // next
    _pagination.nextPage();
    await frame!.sendMessage(0x0a,
      TxPlainText(
        text: _pagination.getCurrentPage().join('\n')
      ).pack()
    );
  }

  /// The vision pipeline to run when a photo is captured
  FutureOr<void> process((Uint8List, ImageMetadata) photo) async {
    var imageData = photo.$1;
    var meta = photo.$2;

    try {
      // update UI with image and empty the text list
      setState(() {
        _imageData = imageData;
        _image = Image.memory(imageData, gaplessPlayback: true,);
        _imageMeta = meta;
        _responseTextList.clear();
      });

      // Perform vision processing pipeline on the current image
      // Initialize the service with the current _apiEndpoint
      final apiService = ApiService(endpointUrl: _apiEndpoint);

      // show we're calling the API
      await frame!.sendMessage(0x0a,
        TxPlainText(
          text: '\u{F0003}', // 3d shades emoji
          x: 285,
          y: 1,
          paletteOffset: 8,
        ).pack()
      );

      try {
        // Make the API call
        final response = await apiService.processImage(
          imageBytes: imageData,
        );

        // Handle the response
        _log.fine(() => 'Received text: $response');

        // show in ListView and paginate for Frame
        _handleResponseText(response);

      } catch (e) {
        // Error calling API (includes 404s as well as 500s)
        // separate "error in API" and "error calling API" if we can do so here
        _log.severe(e);
        await _handleResponseText(e.toString());
      }

      // indicate that we're done processing
      _processing = false;

    } catch (e) {
      // error processing image (or other)
      String err = 'Error processing image: $e';
      _log.severe(err);
      await _handleResponseText(err);
      _processing = false;
    }
  }

  /// replace ListView text with the response,
  /// and also send the response to Frame for display
  Future<void> _handleResponseText(String text) async {
    _responseTextList.clear();
    _pagination.clear();
    List<String> splitText = text.split('\n');

    // add to the ListView
    _responseTextList.addAll(splitText);

    // prepare for display on Frame (accommodating its line width)
    for (var line in splitText) {
      _pagination.appendLine(line);
    }

    // put the response on Frame's display
    await frame!.sendMessage(0x0a,
      TxPlainText(
        text: _pagination.getCurrentPage().join('\n')
      ).pack()
    );

    // redraw the UI
    setState(() {});

    // clear the display in 10s unless canceled
    _scheduleClearDisplay();
  }

  /// clear Frame's display after showing text for 10s (_clearTimer can be canceled)
  void _scheduleClearDisplay() {
    if (!_processing) {
      _clearTimer = Timer(const Duration(seconds: 10), () async {
        // clear Frame's display
        await frame!.sendMessage(0x0a,
          TxPlainText(
            text: ' '
          ).pack()
        );
      });
    }
  }

  /// Use the platform Share mechanism to share the image and the generated text
  static void _shareImage(Uint8List? jpegBytes, String text) async {
    if (jpegBytes != null) {
      try {
        // Share the image bytes as a JPEG file
        await Share.shareXFiles(
          [XFile.fromData(jpegBytes, mimeType: 'image/jpeg', name: 'image.jpg')],
          text: text,
        );
      }
      catch (e) {
        _log.severe('Error preparing image for sharing: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    startForegroundService();
    return WithForegroundTask(
      child: MaterialApp(
        title: 'API - Vision',
        theme: ThemeData.dark(),
        home: Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            title: const Text('API - Vision'),
            actions: [getBatteryWidget()]
          ),
          drawer: getCameraDrawer(),
          body: Column(
            children: [
              Row(
                children: [
                  Expanded(child: TextField(
                    controller: _apiEndpointTextFieldController,
                    decoration: const InputDecoration(
                      hintText: 'E.g. http://192.168.0.5:8000/process'
                    ),
                  )),
                  ElevatedButton(onPressed: _saveApiEndpoint, child: const Text('Save'))
                ],
              ),
              Expanded(
              child: GestureDetector(
                onTap: () {
                  if (_imageData != null) {
                    _shareImage(_imageData, _responseTextList.join('\n'));
                  }
                },
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _image,
                      ),
                    ),
                    if (_imageMeta != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(children: [
                            ImageMetadataWidget(meta: _imageMeta!),
                            const Divider()
                          ]),
                        ),
                      ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                            ),
                            child: Text(_responseTextList[index]),
                          );
                        },
                        childCount: _responseTextList.length,
                      ),
                    ),
                    // This ensures the list can grow dynamically
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Container(), // Empty container to allow scrolling
                    ),
                  ],
                ),
              ),
            ),
            ],
          ),
          floatingActionButton: getFloatingActionButtonWidget(const Icon(Icons.camera_alt), const Icon(Icons.cancel)),
          persistentFooterButtons: getFooterButtonsWidget(),
        ),
      ),
    );
  }
}
