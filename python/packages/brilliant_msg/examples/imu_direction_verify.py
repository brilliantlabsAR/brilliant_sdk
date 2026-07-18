"""
Verify the firmware pitch/roll axis diagnosis on real hardware (no reflash).

For the current pose it reads BOTH:
  * frame.imu.direction()  -> firmware's roll/pitch/heading (current, suspected buggy)
  * frame.imu.raw()        -> raw device-frame accel axes (dev.x, dev.y, dev.z)

then checks:
  1. firmware roll  == atan2(dev.x, dev.z), pitch == atan2(dev.y, dev.z)
     (confirms direction() computes tilt on the RAW device axes)
  2. the corrected host-frame tilt using the SDK-verified accel remap
     host(X,Y,Z) = (-dev.z, dev.y, dev.x):
        roll_fix  = atan2(-dev.z, dev.x)
        pitch_fix = atan2( dev.y, dev.x)

Hold the glasses in a pose and read the numbers. When worn LEVEL the corrected
values should be ~0/0 while the firmware ones are ~90 (the bug).

    uv run python <this> --name "Halo EC" --seconds 20
"""
import argparse
import asyncio
import math

from brilliant_msg import BrilliantMsg

DIR_LUA = (
    "d=frame.imu.direction();"
    "print(string.format('%.2f %.2f %.2f', d.roll, d.pitch, d.heading))"
)
RAW_LUA = (
    "r=frame.imu.raw();"
    "print(string.format('%.2f %.2f %.2f', "
    "r.accelerometer.x, r.accelerometer.y, r.accelerometer.z))"
)


def nums(s):
    try:
        return [float(x) for x in s.strip().split()]
    except (ValueError, AttributeError):
        return None


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", default=None)
    ap.add_argument("--seconds", type=float, default=20.0)
    args = ap.parse_args()

    frame = BrilliantMsg()
    try:
        name = await frame.connect(name=args.name)
        fw = await frame.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
        print(f"Connected to {name} | firmware {fw}\n")
        print(f"{'fw_roll':>8} {'fw_pitch':>8} {'fw_head':>7} | "
              f"{'dev.x':>8} {'dev.y':>8} {'dev.z':>8} | "
              f"{'chk_roll':>8} {'chk_pit':>8} | {'fix_roll':>8} {'fix_pit':>8}")
        print("-" * 100)
        loop = asyncio.get_event_loop()
        end = loop.time() + args.seconds
        while loop.time() < end:
            d = nums(await frame.send_lua(DIR_LUA, await_print=True))
            r = nums(await frame.send_lua(RAW_LUA, await_print=True))
            if not d or not r:
                print("  (unparseable response, skipping)")
                await asyncio.sleep(0.3)
                continue
            fw_roll, fw_pitch, fw_head = d
            dx, dy, dz = r
            # reproduce firmware's current formula from raw:
            chk_roll = math.degrees(math.atan2(dx, dz))
            chk_pitch = math.degrees(math.atan2(dy, dz))
            # corrected host-frame formula:
            fix_roll = math.degrees(math.atan2(-dz, dx))
            fix_pitch = math.degrees(math.atan2(dy, dx))
            print(f"{fw_roll:8.2f} {fw_pitch:8.2f} {fw_head:7.2f} | "
                  f"{dx:8.1f} {dy:8.1f} {dz:8.1f} | "
                  f"{chk_roll:8.2f} {chk_pitch:8.2f} | {fix_roll:8.2f} {fix_pitch:8.2f}")
            await asyncio.sleep(0.4)
    except Exception as e:
        print(f"error: {type(e).__name__}: {e}")
    finally:
        await frame.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
