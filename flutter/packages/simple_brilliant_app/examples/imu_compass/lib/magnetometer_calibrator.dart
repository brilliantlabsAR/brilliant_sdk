import 'dart:async';
import 'dart:math';

class MagnetometerCalibrator {
  final int _requiredSamples; // Adjust based on sensor rate

  double _minX = double.infinity;
  double _maxX = double.negativeInfinity;
  double _minY = double.infinity;
  double _maxY = double.negativeInfinity;
  double _minZ = double.infinity;
  double _maxZ = double.negativeInfinity;

  int _sampleCount = 0;

  MagnetometerCalibrator({int requiredSamples = 200}) : _requiredSamples = requiredSamples;

  final _calibrationComplete = StreamController<Map<String, double>>.broadcast();
  Stream<Map<String, double>> get onCalibrationComplete => _calibrationComplete.stream;

  // Process new sensor readings
  void addSample(double x, double y, double z) {
    _minX = min(_minX, x);
    _maxX = max(_maxX, x);
    _minY = min(_minY, y);
    _maxY = max(_maxY, y);
    _minZ = min(_minZ, z);
    _maxZ = max(_maxZ, z);

    _sampleCount++;

    if (_sampleCount >= _requiredSamples) {
      _completeCalibration();
    }
  }

  // Calculate offsets once enough samples are collected
  void _completeCalibration() {
    final offsets = {
      'offsetX': -(_minX + _maxX) / 2,
      'offsetY': -(_minY + _maxY) / 2,
      'offsetZ': -(_minZ + _maxZ) / 2,
    };

    _calibrationComplete.add(offsets);
  }

  // Get current progress 0.0 .. 1.0
  double getProgress() {
    return (_sampleCount / _requiredSamples).clamp(0.0, 1.0);
  }

  // Reset calibration
  void reset() {
    _minX = double.infinity;
    _maxX = double.negativeInfinity;
    _minY = double.infinity;
    _maxY = double.negativeInfinity;
    _minZ = double.infinity;
    _maxZ = double.negativeInfinity;
    _sampleCount = 0;
  }

  // Clean up resources
  void dispose() {
    _calibrationComplete.close();
  }
}