import { CompassHeading } from './compass-heading';

/** A 3-element vector, `[x, y, z]`. */
export type Vec3 = [number, number, number];
/** A 3x3 matrix in row-major order. */
export type Mat3 = [Vec3, Vec3, Vec3];

/** Serialised form of a {@link MagCalibration}, matching the Python tool's JSON
 *  keys exactly, so a `mag_calibration.json` produced by `imu_calibrate.py`
 *  loads directly. */
export interface MagCalibrationJson {
    offset: number[];
    matrix: number[][];
    heading_offset_deg?: number;
    field_uT?: number;
}

/**
 * Magnetometer calibration for tilt-compensated heading -- the TypeScript mirror
 * of `brilliant_msg/calibration.py`'s runtime `MagCalibration` and the Flutter
 * example's `mag_calibration.dart`.
 *
 * Three independent corrections make a worn/tilted compass usable:
 *   1. Hard-iron {@link offset} -- per-axis offset that re-centres the mag sphere.
 *      Solvable on-device from a tumble.
 *   2. Mag/accel alignment {@link matrix} -- a 3x3 rotation expressing the
 *      magnetometer vector in the accelerometer's body frame. The QMC6308 mag
 *      and BMA580 accel are separate parts at different mounting orientations,
 *      so their axes do not coincide; tilt compensation needs them in one frame.
 *      Solving it needs numpy-class math, so it is produced offline by the Python
 *      tool (`examples/imu_calibrate.py`) and loaded here as JSON.
 *   3. Heading offset {@link headingOffsetDeg} -- a scalar fixing the absolute
 *      zero. The tumble constrains tilt but not "north"; set it in the use
 *      location (local interference shifts the zero).
 *
 * Inputs/outputs use the host frame produced by {@link RxIMU} (+X right,
 * +Y forward, +Z up), so this composes with the shipped imu.lua remap. The JSON
 * keys match the Python tool exactly, so a `mag_calibration.json` loads directly.
 */
export class MagCalibration {
    static readonly identity: Mat3 = [
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0],
    ];

    /**
     * Default Halo mag->accel alignment, used when no per-unit matrix is supplied.
     * The QMC6308 (mag) and BMA580 (accel) dies are mounted at a fixed nominal
     * orientation offset (~90deg about Z plus a small tilt) that is consistent
     * across units, so a fresh calibration ships with it and tilt compensation
     * works before any per-unit calibration; identity leaves a residual tilt
     * error. A per-unit tumble or a loaded calibration JSON overrides it. Keep in
     * sync with Python HALO_DEFAULT_ALIGNMENT / Dart haloDefaultAlignment.
     */
    static readonly haloDefaultAlignment: Mat3 = [
        [-0.005078, -0.998944, -0.045656],
        [0.999975, -0.005296, 0.004647],
        [-0.004884, -0.045631, 0.998946],
    ];

    /** Per-axis hard-iron offset, added to the raw magnetometer (host frame). */
    public readonly offset: Vec3;
    /** 3x3 mag->accel alignment rotation (row-major). Identity = hard-iron only. */
    public readonly matrix: Mat3;
    /** Absolute heading zero correction, degrees. */
    public readonly headingOffsetDeg: number;
    /** Mean field magnitude (raw units) for optional uT scaling; 0 if unknown. */
    public readonly fieldUT: number;

    constructor(options: {
        offset?: Vec3;
        matrix?: Mat3;
        headingOffsetDeg?: number;
        fieldUT?: number;
    } = {}) {
        this.offset = options.offset ?? [0.0, 0.0, 0.0];
        this.matrix = options.matrix ?? MagCalibration.haloDefaultAlignment;
        this.headingOffsetDeg = options.headingOffsetDeg ?? 0.0;
        this.fieldUT = options.fieldUT ?? 0.0;
    }

    /** Whether an alignment matrix (beyond identity) is present. */
    public get hasAlignment(): boolean {
        for (let r = 0; r < 3; r++) {
            for (let c = 0; c < 3; c++) {
                if (Math.abs(this.matrix[r][c] - MagCalibration.identity[r][c]) > 1e-9) {
                    return true;
                }
            }
        }
        return false;
    }

    /** m_corrected = matrix @ (m_raw + offset), in the host frame. */
    public apply(mx: number, my: number, mz: number): Vec3 {
        const cx = mx + this.offset[0];
        const cy = my + this.offset[1];
        const cz = mz + this.offset[2];
        const r = this.matrix;
        return [
            r[0][0] * cx + r[0][1] * cy + r[0][2] * cz,
            r[1][0] * cx + r[1][1] * cy + r[1][2] * cz,
            r[2][0] * cx + r[2][1] * cy + r[2][2] * cz,
        ];
    }

    /**
     * Tilt-compensated magnetic heading (deg, 0-360) from a raw host-frame
     * magnetometer + accelerometer sample. Applies hard-iron, alignment and the
     * heading offset; pass `declination` to also get a true heading.
     */
    public heading(
        mx: number, my: number, mz: number,
        ax: number, ay: number, az: number,
        declination = 0.0,
    ): number {
        const [cx, cy, cz] = this.apply(mx, my, mz);
        const h = CompassHeading.calculateTiltCompensatedHeading(cx, cy, cz, ax, ay, az);
        return ((h + this.headingOffsetDeg + declination) % 360.0 + 360.0) % 360.0;
    }

    /** Copy with the given fields replaced (used by tumble / set-North / edits). */
    public copyWith(options: {
        offset?: Vec3;
        matrix?: Mat3;
        headingOffsetDeg?: number;
        fieldUT?: number;
    } = {}): MagCalibration {
        return new MagCalibration({
            offset: options.offset ?? ([...this.offset] as Vec3),
            matrix: options.matrix ?? this.matrix,
            headingOffsetDeg: options.headingOffsetDeg ?? this.headingOffsetDeg,
            fieldUT: options.fieldUT ?? this.fieldUT,
        });
    }

    /** Serialise to the Python tool's JSON shape (offset/matrix/heading_offset_deg/field_uT). */
    public toJson(): MagCalibrationJson {
        return {
            offset: [...this.offset],
            matrix: this.matrix.map((row) => [...row]),
            heading_offset_deg: this.headingOffsetDeg,
            field_uT: this.fieldUT,
        };
    }

    /** Parse from the Python tool's JSON shape; tolerates missing heading/field. */
    public static fromJson(j: MagCalibrationJson): MagCalibration {
        const vec = (v: number[]): Vec3 => [v[0], v[1], v[2]];
        return new MagCalibration({
            offset: vec(j.offset),
            matrix: j.matrix.map((row) => vec(row)) as Mat3,
            headingOffsetDeg: j.heading_offset_deg ?? 0.0,
            fieldUT: j.field_uT ?? 0.0,
        });
    }

    public toJsonString(): string {
        return JSON.stringify(this.toJson(), null, 2);
    }

    public static fromJsonString(s: string): MagCalibration {
        return MagCalibration.fromJson(JSON.parse(s) as MagCalibrationJson);
    }
}
