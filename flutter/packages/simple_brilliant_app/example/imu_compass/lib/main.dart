import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:imu_compass/compass_heading.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:brilliant_msg/rx/imu.dart';
import 'package:brilliant_msg/tx/code.dart';
import 'package:brilliant_msg/tx/plain_text.dart';
import 'package:simple_brilliant_app/simple_brilliant_app.dart';

import 'mag_calibration.dart';
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
  int _calibrationFaces = 0;

  // Full magnetometer calibration: hard-iron offset + mag/accel alignment
  // matrix + heading offset. The tumble solves the offset on-device; the
  // alignment matrix comes from the Python tool as JSON; "Set North" sets the
  // heading offset in the use location.
  MagCalibration _cal = MagCalibration();

  double _rawMagX = 0;
  double _rawMagY = 0;
  double _rawMagZ = 0;

  // magnetometer after hard-iron + alignment (host frame)
  double _calibMagX = 0.0;
  double _calibMagY = 0.0;
  double _calibMagZ = 0.0;

  // set-North collects a short vector-averaged window when the user taps it
  bool _settingNorth = false;
  int _setNorthCount = 0;
  double _setNorthCos = 0.0;
  double _setNorthSin = 0.0;
  static const int _setNorthSamples = 20;

  // approx raw-magnetometer -> µT scale for the QMC6308 (display nicety only)
  static const double _rawToUT = 0.20;

  // different locations on Earth need heading adjusted due to varying magnetic declination
  double _declination = 0.0;
  double _magHeading = 0.0;
  double _trueHeading = 0.0;
  String _headingText = '';

  final TextEditingController _offsetXController = TextEditingController();
  final TextEditingController _offsetYController = TextEditingController();
  final TextEditingController _offsetZController = TextEditingController();
  final TextEditingController _declinationController = TextEditingController();
  final TextEditingController _calJsonController = TextEditingController();

  double _rawAccelX = 0;
  double _rawAccelY = 0;
  double _rawAccelZ = 0;

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
    // capture a non-null local so a later disconnect can't null-crash the stream
    final f = frame;
    if (f == null) {
      _log.severe('Cannot start: not connected to a device');
      setState(() {
        currentState = ApplicationState.disconnected;
      });
      return;
    }

    setState(() {
      currentState = ApplicationState.running;
    });

    try {
      // set up the RxIMU handler
      await imuStreamSubs?.cancel();
      imuStreamSubs = RxIMU().attach(f.dataResponse).listen((imuData) async {
        _log.fine(() => 'Raw: compass: ${imuData.compass}, accel: ${imuData.accel}, pitch: ${imuData.pitch.toStringAsFixed(2)}, roll: ${imuData.roll.toStringAsFixed(2)}');

        _rawMagX = imuData.compass.$1;
        _rawMagY = imuData.compass.$2;
        _rawMagZ = imuData.compass.$3;

        // apply the full calibration: hard-iron offset + mag/accel alignment
        final (cmx, cmy, cmz) = _cal.apply(_rawMagX, _rawMagY, _rawMagZ);
        _calibMagX = cmx;
        _calibMagY = cmy;
        _calibMagZ = cmz;

        _rawAccelX = imuData.accel.$1;
        _rawAccelY = imuData.accel.$2;
        _rawAccelZ = imuData.accel.$3;

        _normAccelX = _rawAccelX;
        _normAccelY = _rawAccelY;
        _normAccelZ = _rawAccelZ;

        // normalize to a magnitude of 1g
        double normAccel = sqrt(_normAccelX * _normAccelX + _normAccelY * _normAccelY + _normAccelZ * _normAccelZ);
        _normAccelX /= normAccel;
        _normAccelY /= normAccel;
        _normAccelZ /= normAccel;

        _pitch = imuData.pitch;
        _roll = imuData.roll;

        _log.fine(() => 'Calibrated: compass: (${_calibMagX.toStringAsFixed(1)}, ${_calibMagY.toStringAsFixed(1)}, ${_calibMagZ.toStringAsFixed(1)}), accel: (${_normAccelX.toStringAsFixed(1)}, ${_normAccelY.toStringAsFixed(1)}, ${_normAccelZ.toStringAsFixed(1)}), pitch: ${imuData.pitch.toStringAsFixed(2)}, roll: ${imuData.roll.toStringAsFixed(2)}');

        // Tilt-compensated magnetic heading including the heading offset. Uses
        // raw accel — the heading fn normalizes gravity internally.
        _magHeading = _cal.heading(
          _rawMagX, _rawMagY, _rawMagZ,
          _rawAccelX, _rawAccelY, _rawAccelZ);

        // accumulate a set-North window if the user tapped "Set North"
        if (_settingNorth) _accumulateSetNorth(_magHeading);

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
    final f = frame;
    if (f == null) {
      _log.severe('Cannot calibrate: not connected to a device');
      return;
    }

    setState(() {
      currentState = ApplicationState.running;
      _calibrating = true;
    });

    try {
      final calibrator = MagnetometerCalibrator();

      // Listen for calibration completion and cancel IMU stream, return to Ready
      calibrator.onCalibrationComplete.listen((offsets) async {
        // Tumble solves only the hard-iron offset; keep any loaded alignment
        // matrix and heading offset.
        _cal = _cal.copyWith(
          offset: [offsets['offsetX']!, offsets['offsetY']!, offsets['offsetZ']!],
        );
        _log.info('Calibration complete! Offset: ${_cal.offset}');
        _syncOffsetFields();

        // cancel the frameside IMU streaming
        await f.sendMessage(0x41, TxCode().pack()); // STOP_IMU_MSG

        setState(() {
          currentState = ApplicationState.ready;
          _calibrating = false;
        });
      });

      // set up the RxIMU handler
      await imuStreamSubs?.cancel();
      imuStreamSubs = RxIMU().attach(f.dataResponse).listen((imuData) {
        _log.fine('Calibration IMU data: compass: ${imuData.compass}, accel: ${imuData.accel}, pitch: ${imuData.pitch.toStringAsFixed(2)}, roll: ${imuData.roll.toStringAsFixed(2)}');
        // feed magnetometer + accelerometer into the calibrator; the accel is
        // used to require a full 3-axis tumble before calibration completes
        calibrator.addSample(
          imuData.compass.$1.toDouble(), imuData.compass.$2.toDouble(), imuData.compass.$3.toDouble(),
          imuData.accel.$1.toDouble(), imuData.accel.$2.toDouble(), imuData.accel.$3.toDouble());
        setState(() {
          _calibrationProgress = calibrator.getProgress();
          _calibrationFaces = calibrator.facesCovered;
        });
      });

      // kick off the frameside IMU streaming
      await f.sendMessage(0x40, TxCode(value: 10).pack()); // START_IMU_MSG, 10 per second

    } catch (e) {
      _log.severe(() => 'Error executing application logic: $e');
      setState(() {
        currentState = ApplicationState.ready;
      });
    }
  }

  /// Begin a "Set North" capture: face North (level) while streaming, then the
  /// live heading window is vector-averaged and folded into the heading offset
  /// so the current pose reads 0°. Must be done in the USE location — local
  /// magnetic interference shifts the zero. Mirrors imu_heading.py --set-north.
  void _startSetNorth() {
    if (currentState != ApplicationState.running) {
      _log.warning('Set North: start the compass (running) first');
      return;
    }
    setState(() {
      _settingNorth = true;
      _setNorthCount = 0;
      _setNorthCos = 0.0;
      _setNorthSin = 0.0;
    });
  }

  /// Fold one live heading sample into the set-North vector average; when the
  /// window is full, re-zero the heading offset and persist.
  void _accumulateSetNorth(double magHeadingDeg) {
    final r = magHeadingDeg * pi / 180.0;
    _setNorthCos += cos(r);
    _setNorthSin += sin(r);
    _setNorthCount++;
    if (_setNorthCount < _setNorthSamples) return;

    final measured = (atan2(_setNorthSin, _setNorthCos) * 180.0 / pi) % 360.0;
    // new_offset makes the current pose read 0: subtract what we currently
    // measure (with the existing offset already applied) from the old offset.
    final newOffset = (_cal.headingOffsetDeg - measured) % 360.0;
    _cal = _cal.copyWith(headingOffsetDeg: newOffset);
    _log.info('Set North: measured ${measured.toStringAsFixed(1)}° → heading offset ${newOffset.toStringAsFixed(1)}°');
    _settingNorth = false;
    _savePrefs();
  }

  /// Load a full calibration (hard-iron + alignment matrix + heading offset)
  /// from JSON produced by the Python tool (examples/imu_calibrate.py). This is
  /// the MVP path for the numpy-solved alignment matrix.
  Future<void> _loadCalJson() async {
    final text = _calJsonController.text.trim();
    if (text.isEmpty) {
      _log.warning('Load calibration: paste the mag_calibration.json first');
      return;
    }
    try {
      _cal = MagCalibration.fromJsonString(text);
      _syncOffsetFields();
      await _savePrefs();
      _log.info('Loaded calibration: offset ${_cal.offset}, '
          'alignment ${_cal.hasAlignment ? "present" : "identity"}, '
          'heading offset ${_cal.headingOffsetDeg.toStringAsFixed(1)}°');
      if (mounted) {
        FocusScope.of(context).unfocus();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Calibration loaded'), duration: Duration(seconds: 2)));
      }
    } catch (e) {
      _log.severe('Load calibration failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Invalid calibration JSON: $e')));
      }
    }
  }

  /// Reflect the current [_cal.offset] into the editable offset fields.
  void _syncOffsetFields() {
    _offsetXController.text = _cal.offset[0].toStringAsFixed(2);
    _offsetYController.text = _cal.offset[1].toStringAsFixed(2);
    _offsetZController.text = _cal.offset[2].toStringAsFixed(2);
  }

  @override
  void dispose() async {
    await imuStreamSubs?.cancel();
    super.dispose();
  }

  /// Parse a controller's text tolerantly (empty/invalid -> 0.0) and rewrite the
  /// field with the normalized value so it never holds an unparseable string.
  double _readField(TextEditingController c) {
    final v = double.tryParse(c.text.trim()) ?? 0.0;
    c.text = v.toString();
    return v;
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();

    // The full calibration (offset + alignment matrix + heading offset) is
    // stored as one JSON string.
    final calJson = prefs.getString('calibration');
    if (calJson != null) {
      try {
        _cal = MagCalibration.fromJsonString(calJson);
      } catch (e) {
        _log.warning('Stored calibration unreadable, ignoring: $e');
      }
    }

    setState(() {
      _syncOffsetFields();
      _declinationController.text = prefs.getString('declination') ?? '0.0';
      _declination = _readField(_declinationController);
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    // Editable offset fields override the hard-iron offset; alignment matrix and
    // heading offset are preserved from the current calibration.
    _cal = _cal.copyWith(offset: [
      _readField(_offsetXController),
      _readField(_offsetYController),
      _readField(_offsetZController),
    ]);
    _declination = _readField(_declinationController);

    await prefs.setString('calibration', _cal.toJsonString());
    await prefs.setString('declination', _declinationController.text);

    // dismiss the keyboard after saving
    if (mounted) FocusScope.of(context).unfocus();
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
        // Tap anywhere outside a field to dismiss the (numeric) iOS keyboard,
        // which otherwise has no return/done key to dismiss it.
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            // ListView (scrollable) so the fields + readout don't overflow and
            // the footer buttons stay reachable when the keyboard is up.
            child: ListView(
              children: [
              TextField(
                controller: _offsetXController,
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                decoration: const InputDecoration(labelText: 'mag offset:X-axis', hintText: 'Magnetometer offset - X axis'),),
              TextField(
                controller: _offsetYController,
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                decoration: const InputDecoration(labelText: 'mag offset:Y-axis', hintText: 'Magnetometer offset - Y axis'),),
              TextField(
                controller: _offsetZController,
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                decoration: const InputDecoration(labelText: 'mag offset:Z-axis', hintText: 'Magnetometer offset - Z axis'),),
              TextField(
                controller: _declinationController,
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                decoration: const InputDecoration(labelText: 'magnetic declination for your latitude/longitude', hintText: 'Magnetic Declination Estimate'),),

              ElevatedButton(onPressed: _runCalibration, child: const Text('Calibrate Magnetometer (tumble)')),
              if (_calibrating) ...[
                LinearProgressIndicator(value: _calibrationProgress),
                Text('Tumble through all orientations — axes covered: $_calibrationFaces/6',
                    textAlign: TextAlign.center),
              ],
              Text(
                'Alignment matrix: ${_cal.hasAlignment ? "active" : "identity (hard-iron only)"} · '
                'heading offset: ${_cal.headingOffsetDeg.toStringAsFixed(1)}°',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const Divider(),

              // Full calibration (incl. mag/accel alignment matrix) is solved by
              // the Python tool (examples/imu_calibrate.py). Paste its
              // mag_calibration.json here and load it.
              TextField(
                controller: _calJsonController,
                keyboardType: TextInputType.multiline,
                maxLines: 3,
                minLines: 1,
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                decoration: const InputDecoration(
                    labelText: 'calibration JSON (from imu_calibrate.py)',
                    hintText: 'paste mag_calibration.json'),
              ),
              ElevatedButton(onPressed: _loadCalJson, child: const Text('Load calibration JSON')),
              const Divider(),
              ElevatedButton(onPressed: _savePrefs, child: const Text('Save')),

              const SizedBox(height: 12),

              if (currentState == ApplicationState.running)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(_headingText, style: const TextStyle(fontSize: 24)),
                    const SizedBox(height: 8),
                    // Re-zero the compass in the use location (local interference
                    // shifts the zero). Hold level, face North, then tap.
                    ElevatedButton(
                      onPressed: _settingNorth ? null : _startSetNorth,
                      child: Text(_settingNorth
                          ? 'Hold level, facing North… ($_setNorthCount/$_setNorthSamples)'
                          : 'Set North (hold level, face North)'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Raw Accel X: ${_rawAccelX.toStringAsFixed(2)}'),
                            Text('Raw Accel Y: ${_rawAccelY.toStringAsFixed(2)}'),
                            Text('Raw Accel Z: ${_rawAccelZ.toStringAsFixed(2)}'),
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
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Raw Mag X: ${_rawMagX.toStringAsFixed(2)}'),
                            Text('Raw Mag Y: ${_rawMagY.toStringAsFixed(2)}'),
                            Text('Raw Mag Z: ${_rawMagZ.toStringAsFixed(2)}'),
                            const SizedBox(height: 12),
                            Text('Calib Mag X: ${_calibMagX.toStringAsFixed(2)}'),
                            Text('Calib Mag Y: ${_calibMagY.toStringAsFixed(2)}'),
                            Text('Calib Mag Z: ${_calibMagZ.toStringAsFixed(2)}'),
                            const SizedBox(height: 12),
                            Text('Mag magnitude: ${(sqrt(_calibMagX*_calibMagX + _calibMagY*_calibMagY + _calibMagZ*_calibMagZ)*_rawToUT).toStringAsFixed(2)}µT'),
                            Text('Mag heading: ${_magHeading.toStringAsFixed(2)}°'),
                            Text('True heading: ${_trueHeading.toStringAsFixed(2)}°'),
                          ]
                        ),)
                      ],
                    ),
                  ]
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: getFloatingActionButtonWidget(const Icon(Icons.north_east), const Icon(Icons.cancel)),
        persistentFooterButtons: getFooterButtonsWidget(),
      )
    );
  }
}
