import 'dart:convert';

import 'compass_heading.dart';

/// Magnetometer calibration for tilt-compensated heading — the Dart mirror of
/// `brilliant_msg/calibration.py`'s runtime `MagCalibration`.
///
/// Three independent corrections make a worn/tilted compass usable:
///   1. Hard-iron [offset] — per-axis offset that re-centres the mag sphere.
///      Solvable on-device from a tumble (see MagnetometerCalibrator).
///   2. Mag/accel alignment [matrix] — a 3×3 rotation expressing the
///      magnetometer vector in the accelerometer's body frame. The QMC6308 mag
///      and BMA580 accel are separate parts at different mounting orientations,
///      so their axes do not coincide; tilt compensation needs them in one
///      frame. Solving it needs numpy-class math, so it is produced offline by
///      the Python tool (`examples/imu_calibrate.py`) and loaded here as JSON.
///   3. Heading offset [headingOffsetDeg] — a scalar fixing the absolute zero.
///      The tumble constrains tilt but not "north"; set it in the use location
///      via "Set North" (local interference shifts the zero).
///
/// Inputs/outputs use the host frame produced by RxIMU (+X right, +Y forward,
/// +Z up), so this composes with the shipped imu.lua remap. The JSON keys match
/// the Python tool exactly, so a `mag_calibration.json` loads directly.
class MagCalibration {
  static const List<List<double>> identity = [
    [1.0, 0.0, 0.0],
    [0.0, 1.0, 0.0],
    [0.0, 0.0, 1.0],
  ];

  /// Default Halo mag→accel alignment, used when no per-unit matrix is supplied.
  /// The QMC6308 (mag) and BMA580 (accel) dies are mounted at a fixed nominal
  /// orientation offset (~90° about Z plus a small tilt) that is consistent
  /// across units, so a fresh calibration ships with it and tilt compensation
  /// works before any per-unit calibration; identity leaves a residual tilt
  /// error. A per-unit tumble or a loaded calibration JSON overrides it. Keep in
  /// sync with Python HALO_DEFAULT_ALIGNMENT.
  static const List<List<double>> haloDefaultAlignment = [
    [-0.005078, -0.998944, -0.045656],
    [0.999975, -0.005296, 0.004647],
    [-0.004884, -0.045631, 0.998946],
  ];

  /// Per-axis hard-iron offset, added to the raw magnetometer (host frame).
  final List<double> offset;

  /// 3×3 mag→accel alignment rotation (row-major). Identity = hard-iron only.
  final List<List<double>> matrix;

  /// Absolute heading zero correction, degrees.
  final double headingOffsetDeg;

  /// Mean field magnitude (raw units) for optional µT scaling; 0 if unknown.
  final double fieldUT;

  MagCalibration({
    List<double>? offset,
    List<List<double>>? matrix,
    this.headingOffsetDeg = 0.0,
    this.fieldUT = 0.0,
  })  : offset = offset ?? [0.0, 0.0, 0.0],
        matrix = matrix ?? haloDefaultAlignment;

  /// Whether an alignment matrix (beyond identity) is present.
  bool get hasAlignment {
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        if ((matrix[r][c] - identity[r][c]).abs() > 1e-9) return true;
      }
    }
    return false;
  }

  /// m_corrected = matrix @ (m_raw + offset), in the host frame.
  (double, double, double) apply(double mx, double my, double mz) {
    final cx = mx + offset[0];
    final cy = my + offset[1];
    final cz = mz + offset[2];
    final r = matrix;
    return (
      r[0][0] * cx + r[0][1] * cy + r[0][2] * cz,
      r[1][0] * cx + r[1][1] * cy + r[1][2] * cz,
      r[2][0] * cx + r[2][1] * cy + r[2][2] * cz,
    );
  }

  /// Tilt-compensated magnetic heading (deg, 0-360) from a raw host-frame
  /// magnetometer + accelerometer sample. Applies hard-iron, alignment and the
  /// heading offset; pass [declination] to also get a true heading.
  double heading(
    double mx, double my, double mz,
    double ax, double ay, double az, {
    double declination = 0.0,
  }) {
    final (cx, cy, cz) = apply(mx, my, mz);
    final h = CompassHeading.calculateTiltCompensatedHeading(
      magX: cx, magY: cy, magZ: cz,
      gravityX: ax, gravityY: ay, gravityZ: az,
    );
    return (h + headingOffsetDeg + declination) % 360.0;
  }

  /// Copy with the given fields replaced (used by tumble / set-North / edits).
  MagCalibration copyWith({
    List<double>? offset,
    List<List<double>>? matrix,
    double? headingOffsetDeg,
    double? fieldUT,
  }) =>
      MagCalibration(
        offset: offset ?? List<double>.from(this.offset),
        matrix: matrix ?? this.matrix,
        headingOffsetDeg: headingOffsetDeg ?? this.headingOffsetDeg,
        fieldUT: fieldUT ?? this.fieldUT,
      );

  Map<String, dynamic> toJson() => {
        'offset': offset,
        'matrix': matrix,
        'heading_offset_deg': headingOffsetDeg,
        'field_uT': fieldUT,
      };

  factory MagCalibration.fromJson(Map<String, dynamic> j) {
    List<double> vec(dynamic v) =>
        (v as List).map((e) => (e as num).toDouble()).toList();
    return MagCalibration(
      offset: vec(j['offset']),
      matrix: (j['matrix'] as List).map((row) => vec(row)).toList(),
      headingOffsetDeg: (j['heading_offset_deg'] as num?)?.toDouble() ?? 0.0,
      fieldUT: (j['field_uT'] as num?)?.toDouble() ?? 0.0,
    );
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory MagCalibration.fromJsonString(String s) =>
      MagCalibration.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
