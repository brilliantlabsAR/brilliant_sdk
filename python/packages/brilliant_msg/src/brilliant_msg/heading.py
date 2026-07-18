"""
Compass heading helpers for calibrated magnetometer + accelerometer data.

These consume *host-frame* axes as produced by RxIMU (after imu.lua's device
remap), using the convention:  +X = right, +Y = forward, +Z = up.
A device facing magnetic North reads a heading of 0°, and turning right
increases the heading (0=N, 90=E, 180=S, 270=W).

Producing a usable true-North heading requires three steps that are the caller's
responsibility, in order:
  1. magnetometer hard-iron calibration (subtract per-axis offsets),
  2. tilt compensation (done here from the accelerometer/gravity vector),
  3. magnetic declination correction for your location + epoch.

This mirrors the Flutter example's compass_heading.dart so the SDKs agree.
"""
import math

# Magnetic declination is location-specific and left to the caller: look up your
# own at https://www.ngdc.noaa.gov/geomag/calculators/magcalc.shtml and pass it
# to apply_declination() (or MagCalibration.heading) for a true-North heading.


def basic_heading(mag_x: float, mag_y: float) -> float:
    """Heading (deg, 0-360) from horizontal magnetometer X/Y, no tilt compensation.

    Assumes the device is held level. +Y (forward) toward North gives 0°.
    """
    # Rotate by -90° so +Y (forward), not +X, is the 0° reference.
    degrees = math.degrees(math.atan2(mag_y, mag_x)) - 90.0
    return degrees % 360.0


def tilt_compensated_heading(
    mag_x: float, mag_y: float, mag_z: float,
    gravity_x: float, gravity_y: float, gravity_z: float,
) -> float:
    """Heading (deg, 0-360) using gravity to remove tilt.

    Projects the magnetic vector onto the plane perpendicular to gravity, then
    takes the horizontal bearing. ``gravity_*`` is the raw accelerometer vector;
    it is normalised here (the projection requires a unit vector), and its sign
    does not matter.

    NOTE: this is the simplified projection used by the Flutter example. It is
    exact when level and degrades gracefully with modest tilt; a full rotation
    into the world horizontal frame would be more accurate at large tilt.
    """
    gmag = math.sqrt(gravity_x * gravity_x + gravity_y * gravity_y + gravity_z * gravity_z)
    if gmag > 0.0:
        gravity_x, gravity_y, gravity_z = gravity_x / gmag, gravity_y / gmag, gravity_z / gmag
    mag_dot_grav = mag_x * gravity_x + mag_y * gravity_y + mag_z * gravity_z
    # remove the component of the field parallel to gravity
    h_mag_x = mag_x - mag_dot_grav * gravity_x
    h_mag_y = mag_y - mag_dot_grav * gravity_y
    degrees = math.degrees(math.atan2(h_mag_y, h_mag_x)) - 90.0
    return degrees % 360.0


def apply_declination(heading: float, declination: float) -> float:
    """Add magnetic declination (deg, +east) to a magnetic heading -> true heading."""
    return (heading + declination) % 360.0


_CARDINALS = (
    'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
    'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
)


def degrees_to_cardinal(degrees: float) -> str:
    """Convert a heading (deg) to a 16-point compass label."""
    index = int((degrees % 360.0 + 11.25) // 22.5) % 16
    return _CARDINALS[index]
