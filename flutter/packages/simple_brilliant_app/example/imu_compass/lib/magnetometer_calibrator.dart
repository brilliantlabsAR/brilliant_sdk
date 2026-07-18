import 'dart:async';
import 'dart:math';

/// Collects magnetometer samples during a full 3-axis tumble and computes
/// hard-iron offsets (per-axis min/max centre).
///
/// Completion is gated on genuine 3-D coverage: the accelerometer must have
/// pointed each device axis toward gravity (both + and -). A level-only spin
/// never moves the vertical axis, so its min/max on that axis is wrong; gating
/// on coverage prevents completing until every axis has been sampled.
class MagnetometerCalibrator {
  final int _requiredSamples;
  final double _coverThreshold; // |normalised gravity component| to count a face

  double _minX = double.infinity, _maxX = double.negativeInfinity;
  double _minY = double.infinity, _maxY = double.negativeInfinity;
  double _minZ = double.infinity, _maxZ = double.negativeInfinity;

  // which of the 6 axis directions gravity has pointed along: -x,+x,-y,+y,-z,+z
  final List<bool> _faces = List<bool>.filled(6, false);

  int _sampleCount = 0;

  MagnetometerCalibrator({int requiredSamples = 200, double coverThreshold = 0.7})
      : _requiredSamples = requiredSamples,
        _coverThreshold = coverThreshold;

  final _calibrationComplete = StreamController<Map<String, double>>.broadcast();
  Stream<Map<String, double>> get onCalibrationComplete => _calibrationComplete.stream;

  /// Feed a magnetometer sample together with the accelerometer sample taken at
  /// the same instant (used only for coverage detection).
  void addSample(double magX, double magY, double magZ,
      double accX, double accY, double accZ) {
    _minX = min(_minX, magX);
    _maxX = max(_maxX, magX);
    _minY = min(_minY, magY);
    _maxY = max(_maxY, magY);
    _minZ = min(_minZ, magZ);
    _maxZ = max(_maxZ, magZ);

    final n = sqrt(accX * accX + accY * accY + accZ * accZ);
    if (n > 0) {
      final gx = accX / n, gy = accY / n, gz = accZ / n;
      if (gx < -_coverThreshold) _faces[0] = true;
      if (gx > _coverThreshold) _faces[1] = true;
      if (gy < -_coverThreshold) _faces[2] = true;
      if (gy > _coverThreshold) _faces[3] = true;
      if (gz < -_coverThreshold) _faces[4] = true;
      if (gz > _coverThreshold) _faces[5] = true;
    }

    _sampleCount++;

    if (_sampleCount >= _requiredSamples && coverageComplete) {
      _completeCalibration();
    }
  }

  int get facesCovered => _faces.where((c) => c).length;
  bool get coverageComplete => facesCovered == 6;

  void _completeCalibration() {
    _calibrationComplete.add({
      'offsetX': -(_minX + _maxX) / 2,
      'offsetY': -(_minY + _maxY) / 2,
      'offsetZ': -(_minZ + _maxZ) / 2,
    });
  }

  /// Progress 0.0..1.0 combining sample count and 3-D coverage.
  double getProgress() {
    final s = (_sampleCount / _requiredSamples).clamp(0.0, 1.0);
    final c = facesCovered / 6.0;
    return min(s, c);
  }

  void reset() {
    _minX = double.infinity;
    _maxX = double.negativeInfinity;
    _minY = double.infinity;
    _maxY = double.negativeInfinity;
    _minZ = double.infinity;
    _maxZ = double.negativeInfinity;
    for (var i = 0; i < 6; i++) {
      _faces[i] = false;
    }
    _sampleCount = 0;
  }

  void dispose() {
    _calibrationComplete.close();
  }
}
