"""Restore normal sleep behaviour (device sleeps/turns off in the cradle) and put it to sleep now."""
import asyncio
import argparse
from brilliant_ble import BrilliantBle
from brilliant_ble import BrilliantDeviceType

async def main():
    parser = argparse.ArgumentParser(description="Connect to a Halo/Frame device over BLE and run this example.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB" or "Frame 4F"; defaults to the nearest device',
    )
    args = parser.parse_args()
    frame = BrilliantBle()

    try:
        name = await frame.connect(name=args.name)

        # stop any application, if running, so we can send lua commands
        await frame.send_break_signal()
        fw = await frame.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
        tag = await frame.send_lua("print(frame.GIT_TAG)", await_print=True)
        batt = await frame.send_lua("print(frame.battery_level())", await_print=True)
        print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

        # Restore normal behavior that Frame turns off when placed in the charging cradle (and puts it to sleep now)
        if frame.type == BrilliantDeviceType.FRAME:
            await frame.send_lua("frame.stay_awake(false);print(0)", await_print=True)
            print("Frame will switch off when placed in the charging cradle, and will be put to sleep now (tap to wake)")
        else:
            print("Halo will sleep now")

        await frame.send_lua("frame.sleep()", await_print=False)

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        # sleep() above usually drops the connection already, so this is a no-op
        # on the happy path, but it still cleans up if an error happened earlier
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())