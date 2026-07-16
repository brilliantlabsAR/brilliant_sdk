"""Soft-reset the device (restart the Lua VM)."""
import asyncio
import argparse
from brilliant_ble import BrilliantBle

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
        fw = await frame.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
        tag = await frame.send_lua("print(frame.GIT_TAG)", await_print=True)
        batt = await frame.send_lua("print(frame.battery_level())", await_print=True)
        print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

        # soft reset the Frame
        await frame.send_reset_signal()
        print("Reset sent")

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())