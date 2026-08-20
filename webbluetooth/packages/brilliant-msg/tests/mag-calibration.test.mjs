// Unit tests for MagCalibration + CompassHeading. No device or test framework
// required: run with `npm test` (node --test) — the pretest script builds the
// dist bundle these tests import (and the linked brilliant-ble, if needed).
// Mirrors the Flutter example's test/mag_calibration_test.dart and the Python
// tests/test_calibration.py guards so all three SDKs stay in lockstep.
import { test } from 'node:test';
import assert from 'node:assert/strict';

// The published bundle targets the browser and references `self` at module-eval
// time (image-js). MagCalibration/CompassHeading have no browser deps, so shim
// `self` and dynamic-import after it is set (static imports are hoisted).
globalThis.self ??= globalThis;
const { MagCalibration, CompassHeading } = await import('../dist/brilliant-msg.es.js');

const close = (actual, expected, eps = 1e-6) =>
    assert.ok(Math.abs(actual - expected) <= eps,
        `expected ${actual} to be within ${eps} of ${expected}`);

test('default alignment: a fresh calibration ships the Halo default matrix (not identity)', () => {
    const cal = new MagCalibration();
    assert.deepEqual(cal.matrix, MagCalibration.haloDefaultAlignment);
    assert.equal(cal.hasAlignment, true);
});

test('default alignment is a valid rotation (orthonormal, det +1)', () => {
    const m = MagCalibration.haloDefaultAlignment;
    for (let i = 0; i < 3; i++) {
        for (let j = 0; j < 3; j++) {
            const dot = m[i][0] * m[j][0] + m[i][1] * m[j][1] + m[i][2] * m[j][2];
            close(dot, i === j ? 1.0 : 0.0, 1e-4);
        }
    }
    const det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
        m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
        m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);
    close(det, 1.0, 1e-4);
});

test('apply: identity + zero offset is a no-op', () => {
    const cal = new MagCalibration({ matrix: MagCalibration.identity });
    assert.equal(cal.hasAlignment, false);
    const [x, y, z] = cal.apply(10, -20, 30);
    close(x, 10);
    close(y, -20);
    close(z, 30);
});

test('apply: hard-iron offset is added before the matrix', () => {
    const cal = new MagCalibration({ offset: [1, 2, 3], matrix: MagCalibration.identity });
    const [x, y, z] = cal.apply(10, 20, 30);
    close(x, 11);
    close(y, 22);
    close(z, 33);
});

test('apply: matrix @ (m + offset): a 90deg z-rotation maps +X->+Y', () => {
    // rotation of +90deg about z: (x,y,z) -> (-y, x, z)
    const cal = new MagCalibration({ matrix: [[0, -1, 0], [1, 0, 0], [0, 0, 1]] });
    assert.equal(cal.hasAlignment, true);
    const [x, y, z] = cal.apply(1, 0, 0);
    close(x, 0);
    close(y, 1);
    close(z, 0);
});

test('JSON: round-trips with the Python tool key names', () => {
    const cal = new MagCalibration({
        offset: [1.5, -2.5, 0.25],
        matrix: [[0, -1, 0], [1, 0, 0], [0, 0, 1]],
        headingOffsetDeg: 42.0,
        fieldUT: 960.0,
    });
    const restored = MagCalibration.fromJsonString(cal.toJsonString());
    assert.deepEqual(restored.offset, cal.offset);
    assert.deepEqual(restored.matrix, cal.matrix);
    assert.equal(restored.headingOffsetDeg, cal.headingOffsetDeg);
    assert.equal(restored.fieldUT, cal.fieldUT);
});

test('JSON: parses the exact key names emitted by calibration.py', () => {
    const json = '{"offset":[1,2,3],'
        + '"matrix":[[1,0,0],[0,1,0],[0,0,1]],'
        + '"heading_offset_deg":12.7,"field_uT":57.0}';
    const cal = MagCalibration.fromJsonString(json);
    assert.deepEqual(cal.offset, [1.0, 2.0, 3.0]);
    assert.equal(cal.headingOffsetDeg, 12.7);
    assert.equal(cal.fieldUT, 57.0);
});

test('JSON: tolerates missing heading_offset_deg / field_uT', () => {
    const json = '{"offset":[0,0,0],"matrix":[[1,0,0],[0,1,0],[0,0,1]]}';
    const cal = MagCalibration.fromJsonString(json);
    assert.equal(cal.headingOffsetDeg, 0.0);
    assert.equal(cal.fieldUT, 0.0);
});

test('heading: heading offset shifts the reported heading', () => {
    // level device (+Z up), field pointing along +Y (forward) => 0deg.
    const mag = [0.0, 30.0, 0.0];
    const accel = [0.0, 0.0, 1.0];
    const base = new MagCalibration({ matrix: MagCalibration.identity });
    close(base.heading(mag[0], mag[1], mag[2], accel[0], accel[1], accel[2]), 0.0);

    const shifted = base.copyWith({ headingOffsetDeg: 90.0 });
    close(shifted.heading(mag[0], mag[1], mag[2], accel[0], accel[1], accel[2]), 90.0);
});

test('heading: declination is applied on top of the heading offset', () => {
    const mag = [0.0, 30.0, 0.0];
    const accel = [0.0, 0.0, 1.0];
    const cal = new MagCalibration({ headingOffsetDeg: 10.0, matrix: MagCalibration.identity });
    close(cal.heading(mag[0], mag[1], mag[2], accel[0], accel[1], accel[2], 12.7), 22.7);
});

test('set-North: re-zeros an arbitrary pose to read ~0deg afterwards', () => {
    // The app measures the live heading (which already includes the current
    // offset) and picks newOffset = currentOffset - measured so the pose reads 0.
    const reZero = (cal, mx, my, mz, ax, ay, az) => {
        const measured = cal.heading(mx, my, mz, ax, ay, az);
        return ((cal.headingOffsetDeg - measured) % 360.0 + 360.0) % 360.0;
    };
    // device facing East-ish: field along +X => uncalibrated heading 90deg.
    const mag = [30.0, 0.0, 0.0];
    const accel = [0.0, 0.0, 1.0];
    let cal = new MagCalibration({ headingOffsetDeg: 137.0, matrix: MagCalibration.identity });
    const newOffset = reZero(cal, mag[0], mag[1], mag[2], accel[0], accel[1], accel[2]);
    cal = cal.copyWith({ headingOffsetDeg: newOffset });
    const after = cal.heading(mag[0], mag[1], mag[2], accel[0], accel[1], accel[2]);
    close(Math.min(after, 360 - after), 0.0);
});

test('gravity normalization: raw accel (~960) gives the same heading as a unit vector', () => {
    const mag = [12.0, 34.0, -5.0];
    const unit = CompassHeading.calculateTiltCompensatedHeading(
        mag[0], mag[1], mag[2], 0.0, 0.0, 1.0);
    const raw = CompassHeading.calculateTiltCompensatedHeading(
        mag[0], mag[1], mag[2], 0.0, 0.0, 960.0);
    close(raw, unit);
});
