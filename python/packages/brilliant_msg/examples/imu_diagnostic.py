"""
IMU / magnetometer axis + magnitude diagnostic for Halo (and Frame).

Streams the *native* (unremapped, unscaled) frame.imu.raw() axes from the device
via examples/lua/imu_diag_frame_app.lua, walks you through a short guided set of
physical poses, and prints an evidence-based verdict on:

  * which native accelerometer axis/sign is "up", "forward" and "right"
  * the accelerometer scale factor (does a resting sample read ~1 g?)
  * the magnetometer hard-iron offsets, field magnitude and a raw->uT scale
  * the vertical magnetic field sign (Sydney: field points UP out of the ground)
  * a proposed native -> (right, forward, up) remap to compare against imu.lua

All raw samples are also written to imu_diag_<timestamp>.csv for later review.

Usage:
    uv run python packages/brilliant_msg/examples/imu_diagnostic.py --name "Halo AB"

Nothing here changes the SDK; it only measures. Use the verdicts to decide whether
imu.lua's remap / scale and rx_imu.py need correcting.
"""

import argparse
import asyncio
import csv
import math
import struct
import time
from dataclasses import dataclass, field

from brilliant_msg import BrilliantMsg, TxCode

# Frame <-> Phone flags (match imu_diag_frame_app.lua)
IMU_SUBS_MSG = 0x40
IMU_DATA_MSG = 0x0A

# Sydney geomagnetic ground truth (approx, epoch ~2025)
SYDNEY_DECLINATION_DEG = 12.7      # +east
SYDNEY_INCLINATION_DEG = -64.0     # negative => field points UP out of the ground
SYDNEY_TOTAL_FIELD_UT = 57.0       # microtesla, total intensity

AXIS_NAMES = ("x", "y", "z")


@dataclass
class Sample:
    t: float
    compass: tuple[float, float, float]  # native cx, cy, cz
    accel: tuple[float, float, float]    # native ax, ay, az


@dataclass
class Collector:
    """Registered on IMU_DATA_MSG; parses native 6-float packets."""
    samples: list[Sample] = field(default_factory=list)
    _recording_into: list[Sample] | None = None

    def handle_data(self, data: bytes) -> None:
        if len(data) < 26:
            return
        cx, cy, cz, ax, ay, az = struct.unpack("<6f", data[2:26])
        s = Sample(time.time(), (cx, cy, cz), (ax, ay, az))
        self.samples.append(s)
        if self._recording_into is not None:
            self._recording_into.append(s)

    def record_window(self) -> list[Sample]:
        window: list[Sample] = []
        self._recording_into = window
        return window

    def stop_window(self) -> None:
        self._recording_into = None


def _avg(vectors: list[tuple[float, float, float]]) -> tuple[float, float, float]:
    if not vectors:
        return (0.0, 0.0, 0.0)
    n = len(vectors)
    return tuple(sum(v[i] for v in vectors) / n for i in range(3))  # type: ignore[return-value]


def _mag(v: tuple[float, float, float]) -> float:
    return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])


def _dominant_axis(v: tuple[float, float, float]) -> tuple[int, int]:
    """Return (axis_index, sign) of the largest-magnitude component."""
    i = max(range(3), key=lambda k: abs(v[k]))
    return i, (1 if v[i] >= 0 else -1)


def _axis_label(idx: int, sign: int) -> str:
    return f"{'+' if sign >= 0 else '-'}{AXIS_NAMES[idx]}"


def _std(values: list[float]) -> float:
    if not values:
        return 0.0
    m = sum(values) / len(values)
    return math.sqrt(sum((v - m) ** 2 for v in values) / len(values))


def _signed_permutations():
    """Yield (perm, signs, det) for every signed axis permutation.

    perm[host] = native axis index feeding host axis (0=right,1=forward,2=up);
    signs[host] = +1/-1. det is the determinant (+1 => proper rotation).
    """
    from itertools import permutations, product
    for perm in permutations((0, 1, 2)):
        for signs in product((1, -1), repeat=3):
            # determinant of the signed permutation matrix
            # sign of the permutation:
            p = perm
            parity = 1
            for a in range(3):
                for b in range(a + 1, 3):
                    if p[a] > p[b]:
                        parity = -parity
            det = parity * signs[0] * signs[1] * signs[2]
            yield perm, signs, det


def _find_sensor_frame(centered: list[tuple[float, float, float]]):
    """Given hard-iron-centered vectors from a LEVEL spin (rotation about the
    vertical), find the signed axis permutation native->(right,forward,up) whose
    'up' component stays most constant (the vertical field) while right/forward
    trace the horizontal circle. Returns (perm, signs) as host-indexed tuples.
    Sign of 'up' is chosen positive-mean (Sydney: field points up)."""
    best = None
    for perm, signs, det in _signed_permutations():
        if det != 1:               # proper rotations only
            continue
        up = [signs[2] * v[perm[2]] for v in centered]
        right = [signs[0] * v[perm[0]] for v in centered]
        fwd = [signs[1] * v[perm[1]] for v in centered]
        horiz = (_std(right) + _std(fwd)) / 2 + 1e-9
        score = _std(up) / horiz
        up_mean = sum(up) / len(up)
        cand = (score, up_mean, perm, signs)
        # prefer low score, and among near-ties prefer up_mean > 0
        if best is None or score < best[0] - 1e-9:
            best = cand
        elif abs(score - best[0]) <= 1e-9 and up_mean > 0 >= best[1]:
            best = cand
    _, _, perm, signs = best
    # force 'up' positive-mean if the winner came out negative
    up = [signs[2] * v[perm[2]] for v in centered]
    if sum(up) / len(up) < 0:
        # flip up sign and one horizontal to keep a proper rotation
        signs = (signs[0], -signs[1], -signs[2])
    return perm, signs


async def _prompt(text: str) -> None:
    """Non-blocking input() so IMU samples keep streaming in the background."""
    await asyncio.get_event_loop().run_in_executor(None, input, text)


async def _capture_static(collector: Collector, label: str, seconds: float = 2.0):
    window = collector.record_window()
    await asyncio.sleep(seconds)
    collector.stop_window()
    accel = _avg([s.accel for s in window])
    compass = _avg([s.compass for s in window])
    print(f"    [{label}] {len(window)} samples | "
          f"accel≈({accel[0]:.3f}, {accel[1]:.3f}, {accel[2]:.3f}) "
          f"compass≈({compass[0]:.1f}, {compass[1]:.1f}, {compass[2]:.1f})")
    return {"label": label, "accel": accel, "compass": compass, "n": len(window)}


def _analyze(poses: dict, spin: list[Sample]) -> None:
    print("\n" + "=" * 72)
    print("ANALYSIS")
    print("=" * 72)

    # ---- Accelerometer: scale + axis identification ----
    level = poses.get("level")
    if level:
        a = level["accel"]
        raw_mag = _mag(a)
        print("\nAccelerometer scale:")
        print(f"  level resting |accel| (raw)      = {raw_mag:.3f}")
        for sf in (1000.0, 4096.0, 1.0):
            print(f"    /{sf:<6.0f} -> {raw_mag / sf:.4f} g "
                  f"{'  <-- ~1 g expected' if abs(raw_mag / sf - 1.0) < 0.1 else ''}")

    up = poses.get("level")
    fwd = poses.get("nose_down")
    right = poses.get("right_down")
    print("\nAccelerometer axis identification (gravity dominates each pose):")
    mapping = {}
    if up:
        i, s = _dominant_axis(up["accel"])
        # 'up' axis: in the level pose gravity reads along +up if the sensor
        # reports the reaction (specific force). Record the observed sign.
        mapping["up"] = (i, s)
        print(f"  level      -> gravity on native {_axis_label(i, s)}  (=> UP axis is native {AXIS_NAMES[i]})")
    if fwd:
        i, s = _dominant_axis(fwd["accel"])
        mapping["forward"] = (i, s)
        print(f"  nose-down  -> gravity on native {_axis_label(i, s)}  (=> FORWARD axis is native {AXIS_NAMES[i]})")
    if right:
        i, s = _dominant_axis(right["accel"])
        mapping["right"] = (i, s)
        print(f"  right-down -> gravity on native {_axis_label(i, s)}  (=> RIGHT axis is native {AXIS_NAMES[i]})")

    if {"right", "forward", "up"} <= mapping.keys():
        axes = {mapping[k][0] for k in ("right", "forward", "up")}
        if len(axes) == 3:
            print("\n  Proposed native -> (right, forward, up) accel mapping:")
            for host in ("right", "forward", "up"):
                idx, sgn = mapping[host]
                print(f"    host {host:<8} = {_axis_label(idx, sgn)}_native")
            print("  Compare against imu.lua Halo remap: host(X,Y,Z)=(-devZ, devY, devX)")
        else:
            print("\n  ! Two poses picked the same native axis — re-run and hold poses steadier.")

    # ---- Magnetometer: independent axis search (mag axes are OFTEN != accel) ----
    print("\nMagnetometer (independent frame search from the level 360° spin):")
    mag_frame = None
    offsets = (0.0, 0.0, 0.0)
    if spin:
        cs = [s.compass for s in spin]
        mins = tuple(min(c[i] for c in cs) for i in range(3))
        maxs = tuple(max(c[i] for c in cs) for i in range(3))
        offsets = tuple((mins[i] + maxs[i]) / 2 for i in range(3))
        amps = tuple((maxs[i] - mins[i]) / 2 for i in range(3))
        print(f"  hard-iron offset (per axis)      = ({offsets[0]:.1f}, {offsets[1]:.1f}, {offsets[2]:.1f})")
        print(f"  half-amplitude   (per axis)      = ({amps[0]:.1f}, {amps[1]:.1f}, {amps[2]:.1f})")
        centered = [tuple(cs[k][i] - offsets[i] for i in range(3)) for k in range(len(cs))]

        # Search signed permutations: which native axes are (right, forward, up)?
        perm, signs = _find_sensor_frame(centered)
        mag_frame = (perm, signs)
        host = ("right", "forward", "up")
        print("  Discovered magnetometer native -> (right, forward, up):")
        for h in range(3):
            print(f"    host {host[h]:<8} = {_axis_label(perm[h], signs[h])}_native")
        # translate to the imu.lua compass pack order (host X=right, Y=forward, Z=up)
        packed = ", ".join(_axis_label(perm[h], signs[h]) for h in range(3))
        print(f"  => imu.lua should pack compass as host(X,Y,Z) = ({packed})_native")
        print("     (imu.lua currently packs (+x, +z, -y)_native — compare!)")

        avg_mag = sum(_mag(v) for v in centered) / len(centered)
        if avg_mag > 0:
            print(f"  mean centered |compass| (raw)    = {avg_mag:.1f}  "
                  f"=> raw->uT scale ≈ {SYDNEY_TOTAL_FIELD_UT / avg_mag:.4f} "
                  f"(Flutter example uses 0.15)")

        # inclination sign check using the discovered UP axis
        up_vals = [signs[2] * v[perm[2]] for v in centered]
        up_mean = sum(up_vals) / len(up_vals)
        direction = "UP (matches Sydney)" if up_mean > 0 else "DOWN (unexpected for Sydney)"
        print(f"  vertical field on discovered UP  = {up_mean:+.1f} -> points {direction}  "
              f"(Sydney inclination ≈ {SYDNEY_INCLINATION_DEG}°)")
    else:
        print("  (no spin data captured)")

    # ---- Heading at North using the discovered magnetometer frame ----
    north = poses.get("north")
    if north and mag_frame:
        perm, signs = mag_frame
        cen = tuple(north["compass"][i] - offsets[i] for i in range(3))
        right = signs[0] * cen[perm[0]]
        fwd = signs[1] * cen[perm[1]]
        heading = (math.degrees(math.atan2(right, fwd))) % 360   # 0 = forward = North
        print("\nHeading check (facing North, discovered frame):")
        print(f"  right={right:.1f}  forward={fwd:.1f}  -> heading {heading:.1f}° "
              f"(ideal ~0/360°)")
        print(f"  after +{SYDNEY_DECLINATION_DEG}° declination      = "
              f"{(heading + SYDNEY_DECLINATION_DEG) % 360:.1f}°")

    print("\n" + "=" * 72)
    print("Accel axis id uses the static poses (sensitive to sloppy poses); the")
    print("magnetometer uses a robust spin-based frame search. If the discovered")
    print("compass pack order differs from imu.lua's, that is the axis bug to fix.")
    print("Review imu_diag_*.csv for the full trace.")
    print("=" * 72)


def _write_csv(path: str, samples: list[Sample]) -> None:
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["t", "cx", "cy", "cz", "ax", "ay", "az"])
        for s in samples:
            w.writerow([f"{s.t:.3f}", *s.compass, *s.accel])
    print(f"\nWrote {len(samples)} samples to {path}")


async def main():
    parser = argparse.ArgumentParser(description="Halo/Frame IMU axis & magnitude diagnostic.")
    parser.add_argument("--name", default=None,
                        help='exact BLE device name, e.g. "Halo AB"; defaults to the nearest device')
    parser.add_argument("--spin-seconds", type=float, default=15.0,
                        help="duration of the 360° magnetometer spin capture")
    args = parser.parse_args()

    frame = BrilliantMsg()
    collector = Collector()
    poses: dict = {}
    spin: list[Sample] = []

    try:
        name = await frame.connect(name=args.name)
        hw = await frame.send_lua("print(frame.HARDWARE_VERSION)", await_print=True)
        fw = await frame.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
        print(f"Connected to {name} | hardware {hw} | firmware {fw}")

        await frame.print_short_text("IMU Diagnostic")
        await frame.upload_stdlua_libs(lib_names=["data", "code"])
        await frame.upload_frame_app(local_filename="lua/imu_diag_frame_app.lua")
        frame.attach_print_response_handler()
        await frame.start_frame_app()

        frame.register_data_response_handler(collector, [IMU_DATA_MSG], collector.handle_data)
        await frame.send_message(IMU_SUBS_MSG, TxCode(value=20).pack())  # ~stream on
        await asyncio.sleep(0.5)
        if not collector.samples:
            print("WARNING: no IMU samples arriving — check the device is streaming.")

        print("\nGuided poses (hold each steady; capture is ~2 s):")
        await _prompt("  1) Lay glasses LEVEL, facing forward, on the table. Press Enter…")
        poses["level"] = await _capture_static(collector, "level")

        await _prompt("  2) Tilt NOSE-DOWN ~90° (front pointing at floor). Press Enter…")
        poses["nose_down"] = await _capture_static(collector, "nose_down")

        await _prompt("  3) Roll RIGHT temple down ~90° (right side to floor). Press Enter…")
        poses["right_down"] = await _capture_static(collector, "right_down")

        await _prompt(f"  4) Hold LEVEL and be ready to rotate a full 360° over ~{args.spin_seconds:.0f}s. Press Enter…")
        window = collector.record_window()
        print("     Rotating… spin smoothly through a full turn.")
        await asyncio.sleep(args.spin_seconds)
        collector.stop_window()
        spin = list(window)
        print(f"     captured {len(spin)} spin samples")

        await _prompt("  5) Face NORTH (use your phone compass), hold LEVEL. Press Enter…")
        poses["north"] = await _capture_static(collector, "north")

        # stop streaming
        await frame.send_message(IMU_SUBS_MSG, TxCode(value=0).pack())
        frame.unregister_data_response_handler(collector)

        _write_csv(f"imu_diag_{int(time.time())}.csv", collector.samples)
        _analyze(poses, spin)

        frame.detach_print_response_handler()
        await frame.stop_frame_app()

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        await frame.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
