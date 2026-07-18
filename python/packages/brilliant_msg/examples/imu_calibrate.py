"""
Magnetometer calibration tool for Halo.

Captures a full 3-axis tumble plus one "face North, level" reference, solves the
complete calibration (hard-iron + mag/accel alignment + heading offset), reports
the validation gate, and writes a JSON file that MagCalibration can load.

Usage:
    uv run python packages/brilliant_msg/examples/imu_calibrate.py --name "Halo AB"

Then at runtime:
    from brilliant_msg import MagCalibration
    cal = MagCalibration.load("mag_calibration.json")
    heading = cal.heading(imu.compass, imu.accel)   # host-frame RxIMU sample

The tumble determines hard-iron and the tilt alignment; the North reference sets
the absolute heading zero. Worn accuracy is bounded by the reported dip residual.
"""
import argparse
import asyncio
import time

from brilliant_msg import BrilliantMsg
from brilliant_msg.calibration import compute_calibration, MagCalibration

# Convert native frame.imu.raw() axes to the host frame imu.lua emits
# (host: +X right, +Y forward, +Z up), so the calibration matches RxIMU output.
#   host_accel   = (-dev.z, dev.y, dev.x)
#   host_compass = ( dev.x, dev.z, -dev.y)
_READ_LUA = (
    "local r=frame.imu.raw() "
    "print(tostring(r.accelerometer.x)..' '..tostring(r.accelerometer.y)..' '..tostring(r.accelerometer.z)"
    "..' '..tostring(r.compass.x)..' '..tostring(r.compass.y)..' '..tostring(r.compass.z))"
)


def _to_host(ax, ay, az, cx, cy, cz):
    return (-az, ay, ax), (cx, cz, -cy)   # host_accel, host_compass


async def _read(frame):
    """Read one host-frame (accel, compass) sample, or (None, None) if the device
    returned an error string instead of numbers this cycle."""
    line = await frame.send_lua(_READ_LUA, await_print=True)
    try:
        ax, ay, az, cx, cy, cz = (float(v) for v in line.split())
    except ValueError:
        return None, None
    return _to_host(ax, ay, az, cx, cy, cz)


def _norm(v):
    m = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) ** 0.5
    return (v[0] / m, v[1] / m, v[2] / m) if m else (0.0, 0.0, 0.0)


async def main():
    parser = argparse.ArgumentParser(description="Halo magnetometer calibration (tumble + North).")
    parser.add_argument("--name", default=None, help='exact BLE device name, e.g. "Halo AB"')
    parser.add_argument("--out", default="mag_calibration.json", help="output JSON path")
    parser.add_argument("--samples-out", default=None,
                        help="also dump the raw tumble samples + North reference to this JSON "
                             "(lets you re-solve offline / compare units without re-tumbling)")
    parser.add_argument("--max-seconds", type=float, default=120.0)
    args = parser.parse_args()

    frame = BrilliantMsg()
    accel_s: list = []
    compass_s: list = []
    try:
        name = await frame.connect(name=args.name)
        print(f"Connected to {name}")
        print("\nStep 1/2 — TUMBLE: rotate the glasses slowly through every orientation")
        print("(point the top, then each temple, then nose straight down and up).")

        t0 = time.time()
        last = t0
        faces = [False] * 6
        while time.time() - t0 < args.max_seconds:
            # throttle: rapid unthrottled imu.raw() polling can outrun the device's
            # Lua GC and OOM-reboot it. ~10 Hz still gives plenty of tumble samples.
            await asyncio.sleep(0.1)
            acc, comp = await _read(frame)
            if acc is None:
                continue
            accel_s.append(acc)
            compass_s.append(comp)
            g = _norm(acc)
            for i in range(3):
                if g[i] < -0.8:
                    faces[2 * i] = True
                if g[i] > 0.8:
                    faces[2 * i + 1] = True
            if time.time() - last >= 3.0:
                covered = sum(faces)
                need = [("-+"[k] + "xyz"[i]) for i in range(3) for k in (0, 1)
                        if not faces[2 * i + k]]
                print(f"  {len(accel_s)} samples, axes covered {covered}/6"
                      + ("  -> DONE" if covered == 6 else f"  still need: {' '.join(need)}"))
                last = time.time()
                if covered == 6 and len(accel_s) > 150:
                    break

        if sum(faces) < 6:
            print("Did not achieve full coverage — re-run and tumble through all orientations.")
            return

        input("\nStep 2/2 — Hold the glasses LEVEL, face NORTH (use your phone compass), then press Enter… ")
        ref_a = [0.0, 0.0, 0.0]
        ref_c = [0.0, 0.0, 0.0]
        got = 0
        while got < 15:
            acc, comp = await _read(frame)
            if acc is None:
                continue
            for i in range(3):
                ref_a[i] += acc[i]
                ref_c[i] += comp[i]
            got += 1
        ref_a = [v / got for v in ref_a]
        ref_c = [v / got for v in ref_c]
        print("  reference captured")

        print("\nSolving calibration…")
        cal, info = compute_calibration(compass_s, accel_s,
                                        ref_mag=tuple(ref_c), ref_accel=tuple(ref_a),
                                        ref_heading_deg=0.0)
        print(f"  hard-iron offset      = {tuple(round(o, 1) for o in cal.offset)}")
        print(f"  heading offset        = {cal.heading_offset_deg:.1f} deg")
        print(f"  tilt scatter (dip)    = {info['dip_std_before_deg']:.1f} -> {info['dip_std_after_deg']:.1f} deg")
        print(f"  => estimated worn heading accuracy ~{info['dip_std_after_deg']:.1f} deg")
        gate = info["level_heading_residual_deg"]
        print(f"  GATE level-heading residual = {gate:.2f} deg "
              f"({'PASS' if gate < 5 else 'FAIL — re-run with a fuller tumble'})")

        cal.save(args.out)
        print(f"\nSaved calibration to {args.out}")

        if args.samples_out:
            import json
            with open(args.samples_out, "w") as f:
                json.dump({
                    "device": name,
                    "compass": [list(c) for c in compass_s],
                    "accel": [list(a) for a in accel_s],
                    "ref_compass": list(ref_c),
                    "ref_accel": list(ref_a),
                    "ref_heading_deg": 0.0,
                }, f)
            print(f"Saved raw samples to {args.samples_out} "
                  f"({len(compass_s)} tumble samples)")

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        await frame.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
