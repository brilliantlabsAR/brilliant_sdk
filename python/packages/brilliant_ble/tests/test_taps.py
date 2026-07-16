"""
Tests the Frame specific Lua libraries over Bluetooth.
"""
import asyncio
import argparse
from brilliant_ble import BrilliantBle


async def main():
    parser = argparse.ArgumentParser(description="Connect to a Halo/Frame device over BLE and run this test.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB" or "Frame 4F"; defaults to the nearest device',
    )
    args = parser.parse_args()
    b = BrilliantBle()

    await b.connect(name=args.name, print_response_handler=lambda s: print(s))

    await b.send_lua("frame.imu.tap_callback((function()print('Tap!')end))")
    print("Waiting for taps... Tap the device to see output. Ctrl+C to stop.")

    try:
        while True:
            await asyncio.sleep(1)
    except asyncio.CancelledError:
        pass
    finally:
        await b.disconnect()

asyncio.run(main())
