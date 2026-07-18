"""
Live tilt-compensated heading using a saved MagCalibration.

Run imu_calibrate.py first to produce mag_calibration.json, then wear/hold the
glasses and compare this heading to your phone compass at a few facings.

Usage:
    uv run python packages/brilliant_msg/examples/imu_heading.py --name "Halo 24"
"""
import argparse
import asyncio
import math

from brilliant_msg import BrilliantMsg, MagCalibration
from brilliant_msg.heading import degrees_to_cardinal

_READ_LUA = (
    "local r=frame.imu.raw() "
    "print(tostring(r.accelerometer.x)..' '..tostring(r.accelerometer.y)..' '..tostring(r.accelerometer.z)"
    "..' '..tostring(r.compass.x)..' '..tostring(r.compass.y)..' '..tostring(r.compass.z))"
)


def _to_host(ax, ay, az, cx, cy, cz):
    # native -> host frame (matches imu.lua): accel(-z,y,x), compass(x,z,-y)
    return (-az, ay, ax), (cx, cz, -cy)


async def main():
    parser = argparse.ArgumentParser(description="Live heading from a saved calibration.")
    parser.add_argument("--name", default=None, help='exact BLE device name, e.g. "Halo 24"')
    parser.add_argument("--cal", default=None,
                        help="calibration JSON path; if omitted, use the built-in default "
                             "Halo alignment (no hard-iron/North — run imu_calibrate.py for those)")
    parser.add_argument("--set-north", action="store_true",
                        help="face North (level), capture, and rewrite the heading offset in the JSON")
    args = parser.parse_args()

    if args.cal:
        # explicit file requested — load it (a missing file is a real error here)
        cal = MagCalibration.load(args.cal)
        cal_source = args.cal
    else:
        # No --cal: use a bare MagCalibration, which still carries the built-in
        # Halo alignment matrix (tilt-stable) but has NO hard-iron offset — so
        # absolute heading will be off until you run imu_calibrate.py. --set-north
        # at least zeros the current facing (saved to mag_calibration.json).
        cal = MagCalibration()
        cal_source = "built-in default alignment (no hard-iron; run imu_calibrate.py for a per-unit fix)"
    # same calibration but WITHOUT the mag/accel alignment matrix (hard-iron +
    # heading offset only) — the uniform-tracking behaviour for comparison
    cal_noalign = MagCalibration(offset=cal.offset,
                                 matrix=((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)),
                                 heading_offset_deg=cal.heading_offset_deg,
                                 field_uT=cal.field_uT)
    frame = BrilliantMsg()
    try:
        name = await frame.connect(name=args.name)
        print(f"Connected to {name} — heading uses {cal_source}.")

        if args.set_north:
            input("Hold the glasses LEVEL, face NORTH (phone compass), then press Enter… ")
            # heading offset that makes the current pose read 0 (with the matrix)
            raw = MagCalibration(offset=cal.offset, matrix=cal.matrix)
            got, hx, hy = 0, 0.0, 0.0
            while got < 20:
                line = await frame.send_lua(_READ_LUA, await_print=True)
                try:
                    ax, ay, az, cx, cy, cz = (float(v) for v in line.split())
                except ValueError:
                    continue
                acc, comp = _to_host(ax, ay, az, cx, cy, cz)
                h = math.radians(raw.heading(comp, acc))
                hx += math.cos(h); hy += math.sin(h); got += 1
            measured = math.degrees(math.atan2(hy, hx)) % 360.0
            cal.heading_offset_deg = (-measured) % 360.0
            # with no --cal there is no file to update; persist to the default path
            save_path = args.cal or "mag_calibration.json"
            cal.save(save_path)
            print(f"  set heading offset = {cal.heading_offset_deg:.1f}° and saved to {save_path}\n")

        print("Ctrl-C to stop.\n")
        while True:
            line = await frame.send_lua(_READ_LUA, await_print=True)
            try:
                ax, ay, az, cx, cy, cz = (float(v) for v in line.split())
            except ValueError:
                # occasional device-side error string instead of numbers — skip it
                await asyncio.sleep(0.1)
                continue
            acc, comp = _to_host(ax, ay, az, cx, cy, cz)
            h = cal.heading(comp, acc)
            h0 = cal_noalign.heading(comp, acc)
            print(f"\rwith-align: {h:6.1f}° {degrees_to_cardinal(h):3s}   |   "
                  f"hard-iron-only: {h0:6.1f}° {degrees_to_cardinal(h0):3s}   ",
                  end="", flush=True)
            await asyncio.sleep(0.1)
    except (asyncio.CancelledError, KeyboardInterrupt):
        pass
    finally:
        print()
        await frame.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
