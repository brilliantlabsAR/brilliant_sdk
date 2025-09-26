import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:simple_frame_app/frame_vision_app.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:frame_msg/tx/plain_text.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  MainAppState createState() => MainAppState();
}

class MainAppState extends State<MainApp> with SimpleFrameAppState, FrameVisionAppState {

  // the image and metadata to show
  Image? _image;
  ImageMetadata? _imageMeta;
  bool _processing = false;

  MainAppState() {
    Logger.root.level = Level.FINE;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: ${record.time}: ${record.message}');
    });
  }

  @override
  void initState() {
    super.initState();
    // kick off the connection to Frame and start the app if possible
    tryScanAndConnectAndStart(andRun: true);
  }

  @override
  Future<void> onRun() async {
    final plainText = TxPlainText(text: '3-Tap: take photo');
    await frame!.sendMessage(0x0a, plainText.pack());
  }

  @override
  Future<void> onCancel() async {
    // app-specific cleanup
  }

  @override
  Future<void> onTap(int taps) async {
    switch (taps) {
      case 1:
        // next
        break;
      case 2:
        // prev
        break;
      case 3:
        // check if there's processing in progress already and drop the request if so
        if (!_processing) {
          _processing = true;
          // start new vision capture
          // asynchronously kick off the capture/processing pipeline
          capture().then(process);
        }
        break;
      default:
    }
  }

  /// The vision pipeline to run when a photo is captured
  FutureOr<void> process((Uint8List, ImageMetadata) photo) async {
    var imageData = photo.$1;
    var meta = photo.$2;

    try {
      // NOTE: Frame camera is rotated 90 degrees clockwise, so by default RxPhoto makes it upright (`img.copyRotate()`) for image processing.
      // Some processing packages e.g. ML Kit allow us to pass in a rotation parameter
      // To save processing we can set `upright=false` when we construct/initialize our main FrameVisionApp class and handle it manually.

      // update Widget UI
      // For the widget we rotate it upon display with a transform, not changing the source image
      Image im = Image.memory(imageData, gaplessPlayback: true,);

      setState(() {
        _image = im;
        _imageMeta = meta;
      });

      // TODO Perform vision processing pipeline on the current image

      // indicate that we're done processing
      _processing = false;

    } catch (e) {
      _log.severe('Error processing photo: $e');
      // TODO rethrow;?
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frame Vision',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Frame Vision'),
          actions: [getBatteryWidget()]
        ),
        drawer: getCameraDrawer(),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _image ?? Container(),
                  const Divider(),
                  if (_imageMeta != null) ImageMetadataWidget(meta: _imageMeta!),
                ],
              )
            ),
            const Divider(),
          ],
        ),
        floatingActionButton: getFloatingActionButtonWidget(const Icon(Icons.camera_alt), const Icon(Icons.cancel)),
        persistentFooterButtons: getFooterButtonsWidget(),
      ),
    );
  }
}
