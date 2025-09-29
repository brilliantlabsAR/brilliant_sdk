import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:simple_frame_app/text_utils.dart';
import 'package:frame_msg/tx/image_sprite_block.dart';
import 'package:frame_msg/tx/sprite.dart';
import 'package:frame_msg/tx/plain_text.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'pollinations.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  MainAppState createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint('${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

  // Speech to text members
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  String _partialResult = "N/A";
  String _finalResult = "N/A";
  String? _prevText;

  // Image gen/display/sharing members
  Image? _image;
  Uint8List? _imageBytes;

  static const _textStyle = TextStyle(fontSize: 30);

  @override
  void initState() {
    super.initState();

    // asynchronously kick off Speech-to-text initialization and Frame connection/startup
    currentState = ApplicationState.initializing;
    _initSpeech()
      .then((dynamic) {tryScanAndConnectAndStart(andRun: false);});
  }

  @override
  void dispose() async {
    _speechToText.cancel();
    super.dispose();
  }

  /// This has to happen only once per app, but microphone permission must be provided
  Future<void> _initSpeech() async {
    _speechEnabled = await _speechToText.initialize(onError: _onSpeechError);

    if (!_speechEnabled) {
      _finalResult = 'The user has denied the use of speech recognition. Microphone permission must be added manually in device settings.';
      _log.severe(_finalResult);
      currentState = ApplicationState.disconnected;
    }
    else {
      _log.fine('Speech-to-text initialized');
      // this will initialise before Frame is connected, so proceed to disconnected state
      currentState = ApplicationState.disconnected;
    }

    if (mounted) setState(() {});
  }

  /// Manually stop the active speech recognition session, but timeouts will also stop the listening
  Future<void> _stopListening() async {
    await _speechToText.stop();
  }

  /// Timeouts invoke this function, but also other permanent errors
  void _onSpeechError(SpeechRecognitionError error) {
    if (error.errorMsg != 'error_speech_timeout') {
      _log.severe(error.errorMsg);
      currentState = ApplicationState.ready;
    }
    else {
      currentState = ApplicationState.running;
    }
    if (mounted) setState(() {});
  }

  /// This application uses platform speech-to-text to listen to audio from the host mic, convert to text,
  /// and send the text to the Frame.
  /// An image generation request is also sent, and the resulting content is shown in Frame.
  /// So the lifetime of this run() is 10s of seconds or so, due to image generation time and image transfer time
  /// It has a running main loop on the Frame (frame_app.lua)
  @override
  Future<void> run() async {
    currentState = ApplicationState.running;
    if (mounted) setState(() {});

    // listen for STT
    await _speechToText.listen(
      listenOptions: SpeechListenOptions(
        cancelOnError: true, onDevice: true, listenMode: ListenMode.search
      ),
      onResult: (SpeechRecognitionResult result) async {
        if (currentState == ApplicationState.ready) {
          // user has cancelled already, don't process result
          return;
        }

        if (result.finalResult) {
          // on a final result we generate the image
          _finalResult = result.recognizedWords;
          _partialResult = '';
          _log.fine('Final result: $_finalResult');
          _stopListening();
          // send final query text to Frame line 1 (before we confirm the title)
          if (_finalResult != _prevText) {
            var text = TxPlainText(text: TextUtils.wrapText(_finalResult, 300, 4).join('\n'));
            await frame!.sendMessage(0x0a, text.pack());
            _prevText = _finalResult;
          }


          // first, download the image based on the prompt
          String? error;
          Uint8List? bytes;
          (bytes, error) = await fetchImage(_finalResult);

          if (bytes != null) {
            try {
              _imageBytes = bytes;

              // Update the UI based on the original image
              setState(() {
                _image = Image.memory(_imageBytes!, gaplessPlayback: true, fit: BoxFit.cover);
              });

              // yield here a moment in order to show the first image first
              await Future.delayed(const Duration(milliseconds: 10));

              // creating the sprite this way will quantize colors and possibly scale the image
              var sprite = TxSprite.fromImageBytes(imageBytes: _imageBytes!);

              // Update the UI with the modified image
              setState(() {
                _image = Image.memory(img.encodePng(sprite.toImage()), gaplessPlayback: true, fit: BoxFit.cover);
              });

              // create the image sprite block header and its sprite lines
              // based on the sprite
              TxImageSpriteBlock isb = TxImageSpriteBlock(
                image: sprite,
                spriteLineHeight: 20,
                progressiveRender: true);

              // and send the block header then the sprite lines to Frame
              await frame!.sendMessage(0x0d, isb.pack());

              for (var sprite in isb.spriteLines) {
                await frame!.sendMessage(0x0d, sprite.pack());
              }

              // final result is done
              currentState = ApplicationState.ready;
              if (mounted) setState(() {});
            }
            catch (e) {
              _log.severe('Error processing image: $e');
            }
          }
          else {
            _log.fine('Error fetching image for "$_finalResult": "$error"');
          }
        }
        else {
          // partial result - just display in-progress text
          _partialResult = result.recognizedWords;
          if (mounted) setState((){});

          _log.fine('Partial result: $_partialResult, ${result.alternates}');
          if (_partialResult != _prevText) {
            // send partial result to Frame line 1
            var text = TxPlainText(text: TextUtils.wrapText(_partialResult, 300, 4).join('\n'));
            await frame!.sendMessage(0x0a, text.pack());
            _prevText = _partialResult;
          }
        }
      },
    );
  }

  /// The run() function will run for 5-25 seconds or so, but if the user
  /// interrupts it, we can cancel the speech to text/image generation and return to ApplicationState.ready state.
  @override
  Future<void> cancel() async {
    await _stopListening();
    currentState = ApplicationState.ready;
    if (mounted) setState(() {});
  }

  void _shareImage(Uint8List jpegBytes, String prompt) async {
    try {
    // Share the image bytes as a JPEG file
    await Share.shareXFiles(
      [XFile.fromData(jpegBytes, mimeType: 'image/jpeg', name: 'image.jpg')],
      text: prompt,
    );
    }
    catch (e) {
      _log.severe('Error preparing image for sharing: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frame - Pollinations.ai',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Frame - Pollinations.ai'),
          actions: [getBatteryWidget()]
        ),
        body: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Align(alignment: Alignment.centerLeft,
                  child: Text('Query: ${_partialResult == '' ? _finalResult : _partialResult}', style: _textStyle)
                ),
                const Divider(),
                SizedBox(
                  width: 640,
                  height: 400,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Container(
                          alignment: Alignment.topCenter,
                          color: Colors.black,
                          child: (_image != null) ? GestureDetector(
                            onTap: () => _shareImage(_imageBytes!, _finalResult),
                            child: _image!) : null
                        )
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: getFloatingActionButtonWidget(const Icon(Icons.search), const Icon(Icons.cancel)),
        persistentFooterButtons: getFooterButtonsWidget(),
      ),
    );
  }
}
