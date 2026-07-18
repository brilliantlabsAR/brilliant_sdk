/**
 * Compass heading helpers for calibrated magnetometer + accelerometer data.
 *
 * These consume *host-frame* axes as produced by {@link RxIMU} (after imu.lua's
 * device remap), using the convention: +X = right, +Y = forward, +Z = up.
 * A device facing magnetic North reads a heading of 0deg, and turning right
 * increases the heading (0=N, 90=E, 180=S, 270=W).
 *
 * Producing a usable true-North heading requires three steps that are the
 * caller's responsibility, in order:
 *   1. magnetometer hard-iron calibration (subtract per-axis offsets),
 *   2. tilt compensation (done here from the accelerometer/gravity vector),
 *   3. magnetic declination correction for your location + epoch.
 *
 * This mirrors the Python `brilliant_msg/heading.py` and the Flutter example's
 * `compass_heading.dart` so the SDKs agree.
 */

/**
 * Compass heading math. Static methods only; mirrors the Python and Dart
 * implementations so all three SDKs produce identical headings.
 *
 * Magnetic declination is location-specific and left to the caller: look up your
 * own at https://www.ngdc.noaa.gov/geomag/calculators/magcalc.shtml and pass it
 * to `applyDeclination` (or `MagCalibration.heading`) for a true-North heading.
 */
export class CompassHeading {
    /**
     * Heading (deg, 0-360) from horizontal magnetometer X/Y, no tilt compensation.
     * Assumes the device is held level. +Y (forward) toward North gives 0deg.
     */
    public static calculateBasicHeading(x: number, y: number): number {
        // Rotate by -90deg so +Y (forward), not +X, is the 0deg reference.
        let degrees = Math.atan2(y, x) * 180.0 / Math.PI - 90.0;
        if (degrees < 0) {
            degrees += 360.0;
        }
        return degrees;
    }

    /**
     * Tilt-compensated heading (deg, 0-360) using gravity to remove tilt.
     *
     * Projects the magnetic vector onto the plane perpendicular to gravity, then
     * takes the horizontal bearing. `gravity` is the raw accelerometer vector; it
     * is normalised here (the projection requires a UNIT vector -- feeding the raw
     * accel, magnitude ~960, blows up the projection), and its sign does not matter.
     *
     * NOTE: this is the simplified projection used by the examples. It is exact
     * when level and degrades gracefully with modest tilt; a full rotation into
     * the world horizontal frame would be more accurate at large tilt.
     */
    public static calculateTiltCompensatedHeading(
        magX: number, magY: number, magZ: number,
        gravityX: number, gravityY: number, gravityZ: number,
    ): number {
        // Normalise gravity to a unit vector; its sign does not matter.
        const gMag = Math.sqrt(gravityX * gravityX + gravityY * gravityY + gravityZ * gravityZ);
        if (gMag > 0) {
            gravityX /= gMag;
            gravityY /= gMag;
            gravityZ /= gMag;
        }

        const magDotGrav = magX * gravityX + magY * gravityY + magZ * gravityZ;
        // remove the component of the field parallel to gravity
        const hMagX = magX - magDotGrav * gravityX;
        const hMagY = magY - magDotGrav * gravityY;

        // Rotate by -90deg so +Y (forward), not +X, is the 0deg reference.
        let degrees = Math.atan2(hMagY, hMagX) * 180.0 / Math.PI - 90.0;
        if (degrees < 0) {
            degrees += 360.0;
        }
        return degrees;
    }

    /** Add magnetic declination (deg, +east) to a magnetic heading -> true heading. */
    public static applyDeclination(heading: number, declination: number): number {
        return ((heading + declination) % 360.0 + 360.0) % 360.0;
    }

    /** Convert a heading (deg) to a 16-point compass label (N, NNE, NE, ...). */
    public static degreesToCardinal(degrees: number): string {
        const directions = [
            'N', 'NNE', 'NE', 'ENE',
            'E', 'ESE', 'SE', 'SSE',
            'S', 'SSW', 'SW', 'WSW',
            'W', 'WNW', 'NW', 'NNW',
        ];
        const index = Math.floor((((degrees % 360.0) + 360.0) % 360.0 + 11.25) / 22.5) % 16;
        return directions[index];
    }
}
