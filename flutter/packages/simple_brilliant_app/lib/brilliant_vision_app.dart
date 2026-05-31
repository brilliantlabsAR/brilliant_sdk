import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:brilliant_ble/brilliant_device.dart';
import 'package:brilliant_msg/rx/photo.dart';
import 'package:brilliant_msg/rx/tap.dart';
import 'package:brilliant_msg/rx/click.dart';
import 'package:brilliant_msg/tx/capture_settings.dart';
import 'package:brilliant_msg/tx/manual_exp_settings.dart';
import 'package:brilliant_msg/tx/auto_exp_settings.dart';
import 'package:simple_brilliant_app/simple_brilliant_app.dart';
import 'package:brilliant_msg/tx/code.dart';
import 'package:brilliant_msg/tx/plain_text.dart';

final _log = Logger("FVA");

mixin BrilliantVisionAppState<T extends StatefulWidget> on SimpleFrameAppState<T> {

  final Stopwatch _stopwatch = Stopwatch();

  // camera settings
  int qualityIndex = 4;
  final List<String> qualityValues = ['VERY_LOW', 'LOW', 'MEDIUM', 'HIGH', 'VERY_HIGH'];
  int resolution = 640;
  int pan = 0;
  bool upright = false;
  bool _isAutoExposure = true;

  // autoexposure/gain parameters
  int meteringIndex = 1;
  final List<String> meteringValues = ['SPOT', 'CENTER_WEIGHTED', 'AVERAGE'];
  double exposure = 0.1;       // 0.0 <= val <= 1.0
  double exposureSpeed = 0.45; // 0.0 <= val <= 1.0
  int shutterLimit = 16383;    // 4 <= val <= 16383
  int analogGainLimit = 16;    // 1 <= val <= 248
  double whiteBalanceSpeed = 0.5;  // 0.0 <= val <= 1.0
  int rgbGainLimit = 287;      // 0 <= val <= 1023

  // manual exposure/gain parameters
  int manualShutter = 4096; // 4 <= val <= 16383
  int manualAnalogGain = 1; // 1 <= val <= 248
  int manualRedGain = 121;  // 0 <= val <= 1023
  int manualGreenGain = 64; // 0 <= val <= 1023
  int manualBlueGain = 140; // 0 <= val <= 1023

  // tap/click subscriptions
  StreamSubscription<int>? _tapSubs;
  StreamSubscription<ClickType>? _clickSubs;

  /// abstract method that is called at the end of run() to give the implementing class
  /// a chance to print some instructions (or perform some other final setup)
  /// after the tap handler is hooked up
  Future<void> onRun();

  /// abstract method that is called at the start of cancel() to give the implementing class
  /// a chance to perform some cleanup
  Future<void> onCancel();

  /// abstract method that must be implemented by the class mixing in brilliant_vision_app
  /// to capture a photo and perform some action on a 1-, 2-, 3-, n-tap etc.
  Future<void> onTap(int taps);

  /// abstract method that must be implemented by the class mixing in brilliant_vision_app
  /// to capture a photo and perform some action on a single, double or long click.
  Future<void> onClick(ClickType type);

  /// Implements simple_brilliant_app run() by listening for taps
  /// and handing off to a tapHandler() function
  /// in the class that mixes in brilliant_vision_app.
  /// That function would be expected to call capture() and
  /// then perform processing on the image
  @override
  Future<void> run() async {
    setState(() {
      currentState = ApplicationState.running;
    });

    // same TxCode(1) for both click and tap subscriptions
    final code = TxCode(value: 1);

    // let Frame know to subscribe for taps and send them to us
    if (frame!.type == BrilliantDeviceType.frame) {
      // listen for taps for e.g. next(1)/prev(2) content and "new capture" (3)
      _tapSubs?.cancel();
      _tapSubs = RxTap().attach(frame!.dataResponse)
        .listen((taps) async {
          _log.fine(() => 'taps: $taps');
          // call the tap handler in the implementing class
          onTap(taps);
        }
      );

      // let Frame know to subscribe for taps and send them to us
      await frame!.sendMessage(0x10, code.pack());
    }
    else {
      // Halo
      // listen for clicks for e.g. single/double/long click
      _clickSubs?.cancel();
      _clickSubs = RxClick().attach(frame!.dataResponse)
        .listen((type) async {
          _log.fine(() => 'click type: $type');
          // call the click handler in the implementing class
          onClick(type);
        }
      );

      await frame!.sendMessage(0x11, code.pack());
    }

    // prompt the user to begin tapping/clicking or other app-specific setup
    await onRun();

    // run() completes but we stay in ApplicationState.running because the tap listener is active
  }

  Future<void> updateAutoExpSettings() async {
    final autoExpSettings = TxAutoExpSettings(
      meteringIndex: meteringIndex,
      exposure: exposure,
      exposureSpeed: exposureSpeed,
      shutterLimit: shutterLimit,
      analogGainLimit: analogGainLimit,
      whiteBalanceSpeed: whiteBalanceSpeed,
      rgbGainLimit: rgbGainLimit,
    );

    await frame!.sendMessage(0x0e, autoExpSettings.pack());
  }

  Future<void> updateManualExpSettings() async {
    final manualExpSettings = TxManualExpSettings(
      manualShutter: manualShutter,
      manualAnalogGain: manualAnalogGain,
      manualRedGain: manualRedGain,
      manualGreenGain: manualGreenGain,
      manualBlueGain: manualBlueGain,
    );

    await frame!.sendMessage(0x0f, manualExpSettings.pack());
  }

  Future<void> sendExposureSettings() async {
    if (_isAutoExposure) {
      await updateAutoExpSettings();
    }
    else {
      await updateManualExpSettings();
    }
  }

  /// request a photo from Frame
  Future<(Uint8List, ImageMetadata)> capture() async {
    try {
      // save a snapshot of the image metadata (camera settings) to show under the image
      ImageMetadata meta;

      // freeze the quality, resolution and pan for this capture
      var currQualIndex = qualityIndex;
      var currRes = resolution;
      var currPan = pan;

      if (_isAutoExposure) {
        meta = AutoExpImageMetadata(
            quality: qualityValues[currQualIndex],
            resolution: currRes,
            pan: currPan,
            metering: meteringValues[meteringIndex],
            exposure: exposure,
            exposureSpeed: exposureSpeed,
            shutterLimit: shutterLimit,
            analogGainLimit: analogGainLimit,
            whiteBalanceSpeed: whiteBalanceSpeed,
            rgbGainLimit: rgbGainLimit);
      }
      else {
        meta = ManualExpImageMetadata(
            quality: qualityValues[currQualIndex],
            resolution: currRes,
            pan: currPan,
            shutter: manualShutter,
            analogGain: manualAnalogGain,
            redGain: manualRedGain,
            greenGain: manualGreenGain,
            blueGain: manualBlueGain);
      }

      // if we've saved the header from a previous photo, we can request the raw data without the header
      bool requestRaw = RxPhoto.hasJpegHeader(qualityValues[currQualIndex], currRes);

      _stopwatch.reset();
      _stopwatch.start();

      // send the lua command to request a photo from the Frame based on the current settings
      final captureSettings = TxCaptureSettings(
        resolution: currRes,
        qualityIndex: currQualIndex,
        pan: currPan,
        raw: requestRaw,
      );

      await frame!.sendMessage(0x0d, captureSettings.pack());

      // synchronously await the image response (and add jpeg header if necessary)
      Uint8List imageData = await RxPhoto(quality: qualityValues[currQualIndex], resolution: currRes, isRaw: false, upright: upright).attach(frame!.dataResponse).first;

      // received a whole-image Uint8List with jpeg header included
      _stopwatch.stop();

      // add the size and elapsed time to the image metadata widget
      if (meta is AutoExpImageMetadata) {
        meta.size = imageData.length;
        meta.elapsedTimeMs = _stopwatch.elapsedMilliseconds;
      }
      else if (meta is ManualExpImageMetadata) {
        meta.size = imageData.length;
        meta.elapsedTimeMs = _stopwatch.elapsedMilliseconds;
      }

      _log.fine(() => 'Image file size in bytes: ${imageData.length}, elapsedMs: ${_stopwatch.elapsedMilliseconds}, ${((imageData.length / 1024.0) / (_stopwatch.elapsedMilliseconds / 1000.0)).toStringAsFixed(2)} kB/s');

      return (imageData, meta);

    } catch (e) {
      _log.severe('Error executing application: $e');
      rethrow;
    }
  }

  /// cancel tap-listening state and clear the display
  @override
  Future<void> cancel() async {
    setState(() {
      currentState = ApplicationState.canceling;
    });

    // perform app-specific cleanup
    await onCancel();

    // let Frame/Halo know to stop sending taps/clicks
    final code = TxCode(value: 0);

    if (frame!.type == BrilliantDeviceType.frame) {
      await frame!.sendMessage(0x10, code.pack());
    }
    else {
      await frame!.sendMessage(0x11, code.pack());
    }

    // clear the display
    final plainText = TxPlainText(text: ' ');
    await frame!.sendMessage(0x0a, plainText.pack());

    setState(() {
      currentState = ApplicationState.ready;
    });
  }

  Drawer getCameraDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          const DrawerHeader(
            decoration: BoxDecoration(
              color: Colors.blue,
            ),
            child: Text('Camera Settings',
              style: TextStyle(color: Colors.white, fontSize: 24),
              ),
          ),
          ListTile(
            title: const Text('Quality'),
            subtitle: Slider(
              value: qualityIndex.toDouble(),
              min: 0,
              max: qualityValues.length - 1,
              divisions: qualityValues.length - 1,
              label: qualityValues[qualityIndex],
              onChanged: (value) {
                setState(() {
                  qualityIndex = value.toInt();
                });
              },
            ),
          ),
          ListTile(
            title: const Text('Resolution'),
            subtitle: Slider(
              value: resolution.toDouble(),
              min: 256,
              max: 720,
              divisions: (720 - 256) ~/ 16, // even numbers only
              label: resolution.toString(),
              onChanged: (value) {
                setState(() {
                  resolution = value.toInt();
                });
              },
            ),
          ),
          ListTile(
            title: const Text('Pan'),
            subtitle: Slider(
              value: pan.toDouble(),
              min: -140,
              max: 140,
              divisions: 280,
              label: pan.toString(),
              onChanged: (value) {
                setState(() {
                  pan = value.toInt();
                });
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Auto Exposure/Gain'),
            value: _isAutoExposure,
            onChanged: (bool value) async {
              setState(() {
                _isAutoExposure = value;
              });
            },
            subtitle: Text(_isAutoExposure ? 'Auto' : 'Manual'),
          ),
          if (_isAutoExposure) ...[
            // Widgets visible in Auto mode
            ListTile(
              title: const Text('Metering'),
              subtitle: DropdownButton<int>(
                value: meteringIndex,
                onChanged: (int? newValue) async {
                  setState(() {
                    meteringIndex = newValue!;
                  });
                },
                items: meteringValues
                    .map<DropdownMenuItem<int>>((String value) {
                  return DropdownMenuItem<int>(
                    value: meteringValues.indexOf(value),
                    child: Text(value),
                  );
                }).toList(),
              ),
            ),
            ListTile(
              title: const Text('Exposure'),
              subtitle: Slider(
                value: exposure,
                min: 0,
                max: 1,
                divisions: 20,
                label: exposure.toString(),
                onChanged: (value) {
                  setState(() {
                    exposure = value;
                  });
                },
              ),
            ),
            ListTile(
              title: const Text('Exposure Speed'),
              subtitle: Slider(
                value: exposureSpeed,
                min: 0,
                max: 1,
                divisions: 20,
                label: exposureSpeed.toString(),
                onChanged: (value) {
                  setState(() {
                    exposureSpeed = value;
                  });
                },
              ),
            ),
            ListTile(
              title: const Text('Shutter Limit'),
              subtitle: Slider(
                value: shutterLimit.toDouble(),
                min: 4,
                max: 16383,
                divisions: 16,
                label: shutterLimit.toStringAsFixed(0),
                onChanged: (value) {
                  setState(() {
                    shutterLimit = value.toInt();
                  });
                },
              ),
            ),
            ListTile(
              title: const Text('Analog Gain Limit'),
              subtitle: Slider(
                value: analogGainLimit.toDouble(),
                min: 1,
                max: 248,
                divisions: 16,
                label: analogGainLimit.toStringAsFixed(0),
                onChanged: (value) {
                  setState(() {
                    analogGainLimit = value.toInt();
                  });
                },
              ),
            ),
            ListTile(
              title: const Text('White Balance Speed'),
              subtitle: Slider(
                value: whiteBalanceSpeed,
                min: 0,
                max: 1,
                divisions: 20,
                label: whiteBalanceSpeed.toString(),
                onChanged: (value) {
                  setState(() {
                    whiteBalanceSpeed = value;
                  });
                },
              ),
            ),
            ListTile(
              title: const Text('RGB Gain Limit'),
              subtitle: Slider(
                value: rgbGainLimit.toDouble(),
                min: 0,
                max: 1023,
                divisions: 32,
                label: rgbGainLimit.toStringAsFixed(0),
                onChanged: (value) {
                  setState(() {
                    rgbGainLimit = value.toInt();
                  });
                },
              ),
            ),
          ] else ...[
            // Widgets visible in Manual mode
            ListTile(
              title: const Text('Manual Shutter'),
              subtitle: Slider(
                value: manualShutter.toDouble(),
                min: 4,
                max: 16383,
                divisions: 32,
                label: manualShutter.toStringAsFixed(0),
                onChanged: (value) {
                  setState(() {
                    manualShutter = value.toInt();
                  });
                },
              ),
            ),
            ListTile(
              title: const Text('Manual Analog Gain'),
              subtitle: Slider(
                value: manualAnalogGain.toDouble(),
                min: 1,
                max: 248,
                divisions: 50,
                label: manualAnalogGain.toStringAsFixed(0),
                onChanged: (value) {
                  setState(() {
                    manualAnalogGain = value.toInt();
                  });
                },
              ),
            ),
            ListTile(
              title: const Text('Red Gain'),
              subtitle: Slider(
                value: manualRedGain.toDouble(),
                min: 0,
                max: 1023,
                divisions: 50,
                label: manualRedGain.toStringAsFixed(0),
                onChanged: (value) {
                  setState(() {
                    manualRedGain = value.toInt();
                  });
                },
              ),
            ),
            ListTile(
              title: const Text('Green Gain'),
              subtitle: Slider(
                value: manualGreenGain.toDouble(),
                min: 0,
                max: 1023,
                divisions: 50,
                label: manualGreenGain.toStringAsFixed(0),
                onChanged: (value) {
                  setState(() {
                    manualGreenGain = value.toInt();
                  });
                },
              ),
            ),
            ListTile(
              title: const Text('Blue Gain'),
              subtitle: Slider(
                value: manualBlueGain.toDouble(),
                min: 0,
                max: 1023,
                divisions: 50,
                label: manualBlueGain.toStringAsFixed(0),
                onChanged: (value) {
                  setState(() {
                    manualBlueGain = value.toInt();
                  });
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ImageMetadataWidget extends StatelessWidget {
  final ImageMetadata meta;

  const ImageMetadataWidget({super.key, required this.meta});

  @override
  Widget build(BuildContext context) {
    List<String> metaList = meta.toMetaDataList();
    List<Widget> columns = [];

    for (int i = 0; i < metaList.length; i++) {
      columns.add(Text(metaList[i], style: const TextStyle(fontSize: 10, fontFamily: 'helvetica')));

      if (i<metaList.length-1) {
        columns.add(const Spacer());
      }
    }
    return Row(
      children: columns,
    );
  }
}

abstract class ImageMetadata {
  final String quality;
  final int resolution;
  final int pan;
  int size = 0;
  int elapsedTimeMs = 0;

  ImageMetadata({required this.quality, required this.resolution, required this.pan});

  List<String> toMetaDataList();
}

class AutoExpImageMetadata extends ImageMetadata {
  final String metering;
  final double exposure;
  final double exposureSpeed;
  final int shutterLimit;
  final int analogGainLimit;
  final double whiteBalanceSpeed;
  final int rgbGainLimit;

  AutoExpImageMetadata(
      {required super.quality,
      required super.resolution,
      required super.pan,
      required this.metering,
      required this.exposure,
      required this.exposureSpeed,
      required this.shutterLimit,
      required this.analogGainLimit,
      required this.whiteBalanceSpeed,
      required this.rgbGainLimit});

  @override
  List<String> toMetaDataList() {
    return [
        'Quality: $quality\nResolution: $resolution\nPan: $pan\nMetering: ${metering.substring(0,4)}',
        'Exposure: $exposure\nExposureSpeed: $exposureSpeed\nShutterLim: $shutterLimit\nAnalogGainLim: $analogGainLimit',
        'WBSpeed: $whiteBalanceSpeed\nRgbGainLim: $rgbGainLimit\nSize: ${((size)/1024).toStringAsFixed(1)} kb\nTime: $elapsedTimeMs ms',
      ];
  }

  @override
  String toString() {
    return toMetaDataList().join('\n');
  }
}

class ManualExpImageMetadata extends ImageMetadata {
  final int shutter;
  final int analogGain;
  final int redGain;
  final int greenGain;
  final int blueGain;

  ManualExpImageMetadata(
      {required super.quality,
      required super.resolution,
      required super.pan,
      required this.shutter,
      required this.analogGain,
      required this.redGain,
      required this.greenGain,
      required this.blueGain});

  @override
  List<String> toMetaDataList() {
    return [
        'Quality: $quality\nResolution: $resolution\nPan: $pan\nShutter: $shutter',
        'AnalogGain: $analogGain\nRedGain: $redGain\nGreenGain: $greenGain\nBlueGain: $blueGain',
        'Size: ${(size/1024).toStringAsFixed(1)} kb\nTime: $elapsedTimeMs ms',
      ];
  }

  @override
  String toString() {
    return toMetaDataList().join('\n');
  }
}