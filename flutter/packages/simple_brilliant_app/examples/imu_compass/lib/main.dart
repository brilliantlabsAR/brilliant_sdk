import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:imu_compass/compass_heading.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:frame_msg/rx/imu.dart';
import 'package:frame_msg/tx/code.dart';
import 'package:frame_msg/tx/plain_text.dart';

import 'package:simple_frame_app/simple_frame_app.dart';

import 'magnetometer_calibrator.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {
  StreamSubscription<IMUData>? imuStreamSubs;
  bool _calibrating = false;
  double _calibrationProgress = 0.0;

  // magnetometer outputs need to be calibrated/zeroed with offsets
  int _rawMagX = 0;
  int _rawMagY = 0;
  int _rawMagZ = 0;

  double _offsetX = 0.0;
  double _offsetY = 0.0;
  double _offsetZ = 0.0;

  double _calibMagX = 0.0;
  double _calibMagY = 0.0;
  double _calibMagZ = 0.0;

  // different locations on Earth need heading adjusted due to varying magnetic declination
  double _declination = 0.0;
  double _magHeading = 0.0;
  double _trueHeading = 0.0;
  String _headingText = '';

  final TextEditingController _offsetXController = TextEditingController();
  final TextEditingController _offsetYController = TextEditingController();
  final TextEditingController _offsetZController = TextEditingController();
  final TextEditingController _declinationController = TextEditingController();

  // accelerometer outputs get normalised to 1.0 == 1g
  static const int accelFactor = 4096;
  int _rawAccelX = 0;
  int _rawAccelY = 0;
  int _rawAccelZ = 0;

  double _normAccelX = 0.0;
  double _normAccelY = 0.0;
  double _normAccelZ = 0.0;

  double _pitch = 0.0;
  double _roll = 0.0;


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

    _loadPrefs();
  }

  @override
  Future<void> run() async {
    setState(() {
      currentState = ApplicationState.running;
    });

    try {
      // set up the RxIMU handler
      await imuStreamSubs?.cancel();
      imuStreamSubs = RxIMU().attach(frame!.dataResponse).listen((imuData) async {
        _log.fine(() => 'Raw: compass: ${imuData.compass}, accel: ${imuData.accel}, pitch: ${imuData.pitch.toStringAsFixed(2)}, roll: ${imuData.roll.toStringAsFixed(2)}');

        _rawMagX = imuData.compass.$1;
        _rawMagY = imuData.compass.$2;
        _rawMagZ = imuData.compass.$3;

        // apply offsets learned through calibration
        _calibMagX = _rawMagX + _offsetX;
        _calibMagY = _rawMagY + _offsetY;
        _calibMagZ = _rawMagZ + _offsetZ;

        _rawAccelX = imuData.accel.$1;
        _rawAccelY = imuData.accel.$2;
        _rawAccelZ = imuData.accel.$3;

        // accelerometer is configured so that ±2g maps to ±8192,
        // so normalize to 1g == 1.0
        _normAccelX = _rawAccelX / accelFactor;
        _normAccelY = _rawAccelY / accelFactor;
        _normAccelZ = _rawAccelZ / accelFactor;

        // normalize to a magnitude of 1g
        double normAccel = sqrt(_normAccelX * _normAccelX + _normAccelY * _normAccelY + _normAccelZ * _normAccelZ);
        _normAccelX /= normAccel;
        _normAccelY /= normAccel;
        _normAccelZ /= normAccel;

        _pitch = imuData.pitch;
        _roll = imuData.roll;

        _log.fine(() => 'Calibrated: compass: (${_calibMagX.toStringAsFixed(1)}, ${_calibMagY.toStringAsFixed(1)}, ${_calibMagZ.toStringAsFixed(1)}), accel: (${_normAccelX.toStringAsFixed(1)}, ${_normAccelY.toStringAsFixed(1)}, ${_normAccelZ.toStringAsFixed(1)}), pitch: ${imuData.pitch.toStringAsFixed(2)}, roll: ${imuData.roll.toStringAsFixed(2)}');

        _magHeading = CompassHeading.calculateTiltCompensatedHeading(
          magX: _calibMagX,
          magY: _calibMagY,
          magZ: _calibMagZ,
          gravityX: _normAccelX,
          gravityY: _normAccelY,
          gravityZ: _normAccelZ);

        // _magHeading = CompassHeading.calculateBasicHeading(
        //   _calibMagX,
        //   _calibMagY);

        // Optionally apply magnetic declination for your location
        // (look up declination for your location: https://www.ngdc.noaa.gov/geomag/calculators/magcalc.shtml)
        _trueHeading = CompassHeading.applyDeclination(_magHeading, _declination);

        // Get cardinal direction
        final cardinal = CompassHeading.degreesToCardinal(_trueHeading);

        setState(() {
          _headingText = 'Heading: ${_trueHeading.toStringAsFixed(1)}° $cardinal';
        });

        _log.fine(_headingText);
        await frame!.sendMessage(0x12, TxPlainText(text: _headingText).pack());
      });

      // kick off the frameside IMU streaming
      await frame!.sendMessage(0x40, TxCode(value: 1).pack()); // START_IMU_MSG, 1 per second

    } catch (e) {
      _log.severe(() => 'Error executing application logic: $e');
      setState(() {
        currentState = ApplicationState.ready;
      });
    }
  }

  @override
  Future<void> cancel() async {
    // cancel the frameside IMU streaming
    await frame!.sendMessage(0x41, TxCode().pack()); // STOP_IMU_MSG

    setState(() {
      currentState = ApplicationState.ready;
    });
  }

  /// Additional calibration function to run before regular app mode
  Future<void> _runCalibration() async {
    setState(() {
      currentState = ApplicationState.running;
      _calibrating = true;
    });

    try {
      final calibrator = MagnetometerCalibrator();

      // Listen for calibration completion and cancel IMU stream, return to Ready
      calibrator.onCalibrationComplete.listen((offsets) async {
        _offsetX = offsets['offsetX']!;
        _offsetY = offsets['offsetY']!;
        _offsetZ = offsets['offsetZ']!;
        _log.info('Calibration complete! Offsets: ($_offsetX, $_offsetY. $_offsetZ)');
        _offsetXController.text = _offsetX.toStringAsFixed(2);
        _offsetYController.text = _offsetY.toStringAsFixed(2);
        _offsetZController.text = _offsetZ.toStringAsFixed(2);

        // cancel the frameside IMU streaming
        await frame!.sendMessage(0x41, TxCode().pack()); // STOP_IMU_MSG

        setState(() {
          currentState = ApplicationState.ready;
          _calibrating = false;
        });
      });

      // set up the RxIMU handler
      await imuStreamSubs?.cancel();
      imuStreamSubs = RxIMU().attach(frame!.dataResponse).listen((imuData) {
        _log.fine('Calibration IMU data: compass: ${imuData.compass}, accel: ${imuData.accel}, pitch: ${imuData.pitch.toStringAsFixed(2)}, roll: ${imuData.roll.toStringAsFixed(2)}');
        // feed the samples into the calibrator
        calibrator.addSample(imuData.compass.$1.toDouble(), imuData.compass.$2.toDouble(), imuData.compass.$3.toDouble());
        setState(() {
          _calibrationProgress = calibrator.getProgress();
        });
      });

      // kick off the frameside IMU streaming
      await frame!.sendMessage(0x40, TxCode(value: 10).pack()); // START_IMU_MSG, 10 per second

    } catch (e) {
      _log.severe(() => 'Error executing application logic: $e');
      setState(() {
        currentState = ApplicationState.ready;
      });
    }
  }

  @override
  void dispose() async {
    await imuStreamSubs?.cancel();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _offsetXController.text = prefs.getString('offsetX') ?? '0.0';
      _offsetYController.text = prefs.getString('offsetY') ?? '0.0';
      _offsetZController.text = prefs.getString('offsetZ') ?? '0.0';
      _offsetX = double.parse(_offsetXController.text);
      _offsetY = double.parse(_offsetYController.text);
      _offsetZ = double.parse(_offsetZController.text);

      _declinationController.text = prefs.getString('declination') ?? '0.0';
      _declination = double.parse(_declinationController.text);
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('offsetX', _offsetXController.text);
    await prefs.setString('offsetY', _offsetYController.text);
    await prefs.setString('offsetZ', _offsetZController.text);
    _offsetX = double.parse(_offsetXController.text);
    _offsetY = double.parse(_offsetYController.text);
    _offsetZ = double.parse(_offsetZController.text);

    await prefs.setString('declination', _declinationController.text);
    _declination = double.parse(_declinationController.text);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Frame IMU Demo',
      theme: ThemeData.dark(),
      home: Scaffold(
        appBar: AppBar(
            title: const Text('Frame IMU Demo'),
            actions: [getBatteryWidget()]
        ),
        body: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _offsetXController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'mag offset:X-axis', hintText: 'Magnetometer offset - X axis'),),
              TextField(
                controller: _offsetYController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'mag offset:Y-axis', hintText: 'Magnetometer offset - Y axis'),),
              TextField(
                controller: _offsetZController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'mag offset:Z-axis', hintText: 'Magnetometer offset - Z axis'),),
              TextField(
                controller: _declinationController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'magnetic declination for your latitude/longitude', hintText: 'Magnetic Declination Estimate'),),

              ElevatedButton(onPressed: _runCalibration, child: const Text('Calibrate Magnetometer')),
              if (_calibrating) LinearProgressIndicator(value: _calibrationProgress),
              const Divider(),
              ElevatedButton(onPressed: _savePrefs, child: const Text('Save')),

              const SizedBox(height: 12),

              if (currentState == ApplicationState.running)
                Expanded(child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_headingText, style: const TextStyle(fontSize: 24)),
                    const SizedBox(height: 12),
                    Expanded(child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Raw Accel X: $_rawAccelX'),
                            Text('Raw Accel Y: $_rawAccelY'),
                            Text('Raw Accel Z: $_rawAccelZ'),
                            const SizedBox(height: 12),
                            Text('Norm Accel X: ${_normAccelX.toStringAsFixed(2)}'),
                            Text('Norm Accel Y: ${_normAccelY.toStringAsFixed(2)}'),
                            Text('Norm Accel Z: ${_normAccelZ.toStringAsFixed(2)}'),
                            const SizedBox(height: 12),
                            Text('Pitch: ${_pitch.toStringAsFixed(2)}°'),
                            Text('Roll: ${_roll.toStringAsFixed(2)}°'),
                          ]
                        ),),
                        Expanded(child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Raw Mag X: $_rawMagX'),
                            Text('Raw Mag Y: $_rawMagY'),
                            Text('Raw Mag Z: $_rawMagZ'),
                            const SizedBox(height: 12),
                            Text('Calib Mag X: ${_calibMagX.toStringAsFixed(2)}'),
                            Text('Calib Mag Y: ${_calibMagY.toStringAsFixed(2)}'),
                            Text('Calib Mag Z: ${_calibMagZ.toStringAsFixed(2)}'),
                            const SizedBox(height: 12),
                            Text('Mag magnitude: ${(sqrt(_calibMagX*_calibMagX + _calibMagY*_calibMagY + _calibMagZ*_calibMagZ)*0.15).toStringAsFixed(2)}µT'),
                            Text('Mag heading: ${_magHeading.toStringAsFixed(2)}°'),
                            Text('True heading: ${_trueHeading.toStringAsFixed(2)}°'),
                          ]
                        ),)
                      ],
                    ),),
                  ]
                ),),
              //const Spacer(),
            ],
          ),
        ),
        floatingActionButton: getFloatingActionButtonWidget(const Icon(Icons.north_east), const Icon(Icons.cancel)),
        persistentFooterButtons: getFooterButtonsWidget(),
      )
    );
  }
}
