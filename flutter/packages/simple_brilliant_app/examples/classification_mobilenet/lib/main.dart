import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as image_lib;
import 'package:logging/logging.dart';
import 'package:simple_frame_app/frame_vision_app.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:simple_frame_app/tx/plain_text.dart';

import 'helper/image_classification_helper.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  MainAppState createState() => MainAppState();
}

class MainAppState extends State<MainApp> with SimpleFrameAppState, FrameVisionAppState {
  // main state of image processing in progress
  bool _processing = false;

  // Classification
  late ImageClassificationHelper _imageClassificationHelper;
  String _top3 = '';

  // the image and metadata to show
  Image? _image;
  ImageMetadata? _imageMeta;

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: ${record.time}: ${record.loggerName}: ${record.message}');
    });
  }

  @override
  void initState() {
    super.initState();

    _imageClassificationHelper = ImageClassificationHelper();
    _imageClassificationHelper.initHelper();

    // kick off the connection to Frame and start the app if possible
    tryScanAndConnectAndStart(andRun: true);
  }

  @override
  Future<void> onRun() async {
    // initial message to display when running
    await frame!.sendMessage(
      TxPlainText(
        msgCode: 0x0a,
        text: '2-Tap: take photo'
      )
    );
  }

  @override
  Future<void> onCancel() async {
    // no app-specific cleanup required here
  }

  @override
  Future<void> onTap(int taps) async {
    switch (taps) {
      case 2:
        // check if there's processing in progress already and drop the request if so
        if (!_processing) {
          _processing = true;
          // synchronously call the capture and processing (just display) of the photo
          await capture().then(process);
        }
        break;
      default:
    }
  }

  /// The vision pipeline to run when a photo is captured
  /// Which in this case is just displaying
  FutureOr<void> process((Uint8List, ImageMetadata) photo) async {
    var imageData = photo.$1;
    var meta = photo.$2;

    // Perform vision processing pipeline
    // send image to classifier, produce some candidate classes (https://pub.dev/packages/tflite_flutter)
    Map<String, double> classification = await _imageClassificationHelper.inferenceImage(image_lib.decodeJpg(imageData)!);

    // classification map is unordered and can be long, sort it and pick the best 3 here
    _top3 = (classification.entries.toList()
              ..sort((a, b) => a.value.compareTo(b.value),))
              .reversed.take(3).toList().fold<String>('', (previousValue, element) => '$previousValue\n${element.key}: ${element.value.toStringAsFixed(2)}').trim();

    _log.fine('Classification result: $_top3');

    // Frame display
    await frame!.sendMessage(TxPlainText(msgCode: 0x0a, text: _top3));

    // UI display
    setState(() {
      _image = Image.memory(imageData, gaplessPlayback: true,);
      _imageMeta = meta;
    });

    // finished processing, ready to start again
    _processing = false;
  }

  /// cancel the current photo
  @override
  Future<void> cancel() async {
    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vision - Classification',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Vision - Classification'),
          actions: [getBatteryWidget()]
        ),
        drawer: getCameraDrawer(),
        onDrawerChanged: (isOpened) {
          if (isOpened) {
            // if the user opens the camera settings, stop streaming
            _processing = false;
          }
          else {
            // if the user closes the camera settings, send the updated settings to Frame
            sendExposureSettings();
          }
        },
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _image ?? Container(),
                  const Divider(),
                  if (_imageMeta != null) ImageMetadataWidget(meta: _imageMeta!),
                  const Divider(),
                  Text(_top3),
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
