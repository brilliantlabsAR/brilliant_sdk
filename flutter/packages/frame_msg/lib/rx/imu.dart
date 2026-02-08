import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';

final _log = Logger("RxIMU");

/// Buffer class to allow us to provide a smoothed moving average of samples
class SensorBuffer {
  final int maxSize;
  final List<(double x, double y, double z)> _buffer = [];

  SensorBuffer(this.maxSize);

  void add((double x, double y, double z) value) {
    _buffer.add(value);
    if (_buffer.length > maxSize) {
      _buffer.removeAt(0);
    }
  }

  (double x, double y, double z) get average {
    if (_buffer.isEmpty) return (0.0, 0.0, 0.0);

    double sumX = 0, sumY = 0, sumZ = 0;
    for (var value in _buffer) {
      sumX += value.$1;
      sumY += value.$2;
      sumZ += value.$3;
    }
    return (
      (sumX / _buffer.length),
      (sumY / _buffer.length),
      (sumZ / _buffer.length)
    );
  }
}

/// IMU data stream, returns raw 3-axis magnetometer and 3-axis accelerometer data
/// and optionally computes derived values
/// Note, a proper calculation of Heading requires magnetometer calibration,
/// tilt compensation (which we can do here from the accelerometer), and magnetic
/// declination adjustment (which is lat-long and time-dependent).
/// Magnetometer calibration and declination adjustments need to be done outside this class.
class RxIMU {
  final int _smoothingSamples;

  // Frame to Phone flags
  final int imuFlag;
  StreamController<IMUData>? _controller;

  // Buffers for smoothing
  late final SensorBuffer _compassBuffer;
  late final SensorBuffer _accelBuffer;

  RxIMU({
    this.imuFlag = 0x0A,
    int smoothingSamples = 1,
  }) : _smoothingSamples = smoothingSamples {
    _compassBuffer = SensorBuffer(_smoothingSamples);
    _accelBuffer = SensorBuffer(_smoothingSamples);
  }

  /// Attach this RxIMU to the Frame's dataResponse characteristic stream.
  Stream<IMUData> attach(Stream<List<int>> dataResponse) {
    // TODO check for illegal state - attach() already called on this RxIMU etc?
    // might be possible though after a clean close(), do I want to prevent it?

    // the subscription to the underlying data stream
    StreamSubscription<List<int>>? dataResponseSubs;

    // Our stream controller that transforms the dataResponse elements into IMUData events
    _controller = StreamController();

    _controller!.onListen = () {
      dataResponseSubs = dataResponse
        .where((data) => data[0] == imuFlag)
        .listen((data) {
          // data structure: [flag, ?, float, float, float, float, float, float]
          // offsets: 0, 1, 2..5, 6..9, 10..13, 14..17, 18..21, 22..25
          // total length should be at least 2 + 6*4 = 26 bytes.
          
          if (data.length < 26) {
             // Not enough data for 6 floats + header
             return;
          }

          final byteData = ByteData.sublistView(Uint8List.fromList(data));
          
          // Read 6 32-bit little-endian floats starting at offset 2
          double cX = byteData.getFloat32(2, Endian.little);
          double cY = byteData.getFloat32(6, Endian.little);
          double cZ = byteData.getFloat32(10, Endian.little);
          double aX = byteData.getFloat32(14, Endian.little);
          double aY = byteData.getFloat32(18, Endian.little);
          double aZ = byteData.getFloat32(22, Endian.little);

          // Get raw values
          var rawCompass = (cX, cY, cZ);
          var rawAccel = (aX, aY, aZ);

          // Add to buffers
          _compassBuffer.add(rawCompass);
          _accelBuffer.add(rawAccel);

          _controller!.add(IMUData(
            compass: _compassBuffer.average,
            accel: _accelBuffer.average,
            raw: IMURawData(
              compass: rawCompass,
              accel: rawAccel,
            ),
          ));

      }, onDone: _controller!.close, onError: _controller!.addError);
      _log.fine('ImuDataResponse stream subscribed');
    };

    _controller!.onCancel = () {
      _log.fine('ImuDataResponse stream unsubscribed');
      dataResponseSubs?.cancel();
      _controller!.close();
    };

    return _controller!.stream;
  }
}

class IMURawData {
  final (double x, double y, double z) compass;
  final (double x, double y, double z) accel;

  IMURawData({
    required this.compass,
    required this.accel,
  });
}

class IMUData {
  final (double x, double y, double z) compass;
  final (double x, double y, double z) accel;
  final IMURawData? raw;

  IMUData({
    required this.compass,
    required this.accel,
    this.raw,
  });

  double get pitch => atan2(accel.$2, accel.$3) * 180.0 / pi;
  double get roll => atan2(accel.$1, accel.$3) * 180.0 / pi;
}