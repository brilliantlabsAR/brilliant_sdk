import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:imu_compass/compass_heading.dart';
import 'package:imu_compass/mag_calibration.dart';

void main() {
  group('default alignment', () {
    test('a fresh calibration ships the Halo default matrix (not identity)', () {
      final cal = MagCalibration();
      expect(cal.matrix, MagCalibration.haloDefaultAlignment);
      expect(cal.hasAlignment, isTrue);
    });

    test('the default alignment is a valid rotation (orthonormal, det +1)', () {
      const m = MagCalibration.haloDefaultAlignment;
      for (var i = 0; i < 3; i++) {
        for (var j = 0; j < 3; j++) {
          final dot = m[i][0] * m[j][0] + m[i][1] * m[j][1] + m[i][2] * m[j][2];
          expect(dot, closeTo(i == j ? 1.0 : 0.0, 1e-4));
        }
      }
      final det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
          m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
          m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
      expect(det, closeTo(1.0, 1e-4));
    });
  });

  group('MagCalibration.apply', () {
    test('identity + zero offset is a no-op', () {
      // the class default is now the Halo alignment, so pass identity explicitly
      final cal = MagCalibration(matrix: MagCalibration.identity);
      expect(cal.hasAlignment, isFalse);
      final (x, y, z) = cal.apply(10, -20, 30);
      expect(x, closeTo(10, 1e-9));
      expect(y, closeTo(-20, 1e-9));
      expect(z, closeTo(30, 1e-9));
    });

    test('hard-iron offset is added before the matrix', () {
      final cal = MagCalibration(offset: [1, 2, 3], matrix: MagCalibration.identity);
      final (x, y, z) = cal.apply(10, 20, 30);
      expect(x, closeTo(11, 1e-9));
      expect(y, closeTo(22, 1e-9));
      expect(z, closeTo(33, 1e-9));
    });

    test('matrix @ (m + offset): a 90° z-rotation maps +X→+Y', () {
      // rotation of +90° about z: (x,y,z) -> (-y, x, z)
      final cal = MagCalibration(matrix: const [
        [0, -1, 0],
        [1, 0, 0],
        [0, 0, 1],
      ]);
      expect(cal.hasAlignment, isTrue);
      final (x, y, z) = cal.apply(1, 0, 0);
      expect(x, closeTo(0, 1e-9));
      expect(y, closeTo(1, 1e-9));
      expect(z, closeTo(0, 1e-9));
    });
  });

  group('MagCalibration JSON', () {
    test('round-trips through JSON with the Python tool key names', () {
      final cal = MagCalibration(
        offset: [1.5, -2.5, 0.25],
        matrix: const [
          [0, -1, 0],
          [1, 0, 0],
          [0, 0, 1],
        ],
        headingOffsetDeg: 42.0,
        fieldUT: 960.0,
      );
      final restored = MagCalibration.fromJsonString(cal.toJsonString());
      expect(restored.offset, cal.offset);
      expect(restored.matrix, cal.matrix);
      expect(restored.headingOffsetDeg, cal.headingOffsetDeg);
      expect(restored.fieldUT, cal.fieldUT);
    });

    test('parses the exact key names emitted by calibration.py', () {
      const json = '{"offset":[1,2,3],'
          '"matrix":[[1,0,0],[0,1,0],[0,0,1]],'
          '"heading_offset_deg":12.7,"field_uT":57.0}';
      final cal = MagCalibration.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(cal.offset, [1.0, 2.0, 3.0]);
      expect(cal.headingOffsetDeg, 12.7);
      expect(cal.fieldUT, 57.0);
    });

    test('tolerates missing heading_offset_deg / field_uT', () {
      const json = '{"offset":[0,0,0],"matrix":[[1,0,0],[0,1,0],[0,0,1]]}';
      final cal = MagCalibration.fromJson(jsonDecode(json) as Map<String, dynamic>);
      expect(cal.headingOffsetDeg, 0.0);
      expect(cal.fieldUT, 0.0);
    });
  });

  group('MagCalibration.heading', () {
    test('heading offset shifts the reported heading', () {
      // level device (+Z up), field pointing along +Y (forward) => 0°.
      const mag = [0.0, 30.0, 0.0];
      const accel = [0.0, 0.0, 1.0];
      final base = MagCalibration(matrix: MagCalibration.identity);
      expect(base.heading(mag[0], mag[1], mag[2], accel[0], accel[1], accel[2]),
          closeTo(0.0, 1e-6));

      final shifted = base.copyWith(headingOffsetDeg: 90.0);
      expect(
          shifted.heading(mag[0], mag[1], mag[2], accel[0], accel[1], accel[2]),
          closeTo(90.0, 1e-6));
    });

    test('declination is applied on top of the heading offset', () {
      const mag = [0.0, 30.0, 0.0];
      const accel = [0.0, 0.0, 1.0];
      final cal = MagCalibration(headingOffsetDeg: 10.0, matrix: MagCalibration.identity);
      expect(
          cal.heading(mag[0], mag[1], mag[2], accel[0], accel[1], accel[2],
              declination: 12.7),
          closeTo(22.7, 1e-6));
    });
  });

  group('set-North offset math (mirrors imu_heading.py --set-north)', () {
    // The app measures the live heading (which already includes the current
    // offset) and picks newOffset = currentOffset - measured so the pose reads 0.
    double reZero(MagCalibration cal, double mx, double my, double mz,
        double ax, double ay, double az) {
      final measured = cal.heading(mx, my, mz, ax, ay, az);
      return (cal.headingOffsetDeg - measured) % 360.0;
    }

    test('re-zeros an arbitrary pose to read ~0° afterwards', () {
      // device facing East-ish: field along +X => uncalibrated heading 90°.
      const mag = [30.0, 0.0, 0.0];
      const accel = [0.0, 0.0, 1.0];
      var cal = MagCalibration();
      final newOffset = reZero(cal, mag[0], mag[1], mag[2], accel[0], accel[1], accel[2]);
      cal = cal.copyWith(headingOffsetDeg: newOffset);
      final after = cal.heading(mag[0], mag[1], mag[2], accel[0], accel[1], accel[2]);
      expect(min(after, 360 - after), closeTo(0.0, 1e-6));
    });

    test('re-zero is stable when an offset is already present', () {
      const mag = [30.0, 0.0, 0.0];
      const accel = [0.0, 0.0, 1.0];
      var cal = MagCalibration(headingOffsetDeg: 137.0);
      final newOffset = reZero(cal, mag[0], mag[1], mag[2], accel[0], accel[1], accel[2]);
      cal = cal.copyWith(headingOffsetDeg: newOffset);
      final after = cal.heading(mag[0], mag[1], mag[2], accel[0], accel[1], accel[2]);
      expect(min(after, 360 - after), closeTo(0.0, 1e-6));
    });
  });

  group('gravity normalization in tilt compensation', () {
    test('raw accel (magnitude ~960) gives the same heading as a unit vector', () {
      const mag = [12.0, 34.0, -5.0];
      final unit = CompassHeading.calculateTiltCompensatedHeading(
        magX: mag[0], magY: mag[1], magZ: mag[2],
        gravityX: 0.0, gravityY: 0.0, gravityZ: 1.0);
      final raw = CompassHeading.calculateTiltCompensatedHeading(
        magX: mag[0], magY: mag[1], magZ: mag[2],
        gravityX: 0.0, gravityY: 0.0, gravityZ: 960.0);
      expect(raw, closeTo(unit, 1e-6));
    });
  });
}
