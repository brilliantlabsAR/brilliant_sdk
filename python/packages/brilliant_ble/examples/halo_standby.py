"""Put a Halo into standby (low-power sleep), then disconnect.

Standby is a Halo-only feature; the device wakes on AAD, tap, Bluetooth or
the button.
"""
import asyncio
import argparse

from brilliant_ble import BrilliantBle, BrilliantDeviceType


async def main():
    parser = argparse.ArgumentParser(
        description="Connect to a Halo device over BLE and put it into standby.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB"; defaults to the first device found',
    )
    args = parser.parse_args()
    frame = BrilliantBle()

    try:
        await frame.connect(name=args.name)

        # stop any application, if running, so we can send lua commands
        await frame.send_break_signal()

        if frame._type != BrilliantDeviceType.HALO:
            print("standby() is a Halo-only feature")
            return

        await frame.send_lua("frame.standby()", await_print=False)
        print("Halo put into Standby mode (wakes on AAD, tap, bluetooth, button)")

        # Give Halo time to run the standby() in the Lua REPL before disconnecting
        await asyncio.sleep(1)

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        await frame.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
