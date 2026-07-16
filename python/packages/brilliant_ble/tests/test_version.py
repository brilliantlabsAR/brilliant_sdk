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

    await b.send_lua("print(frame.HARDWARE_VERSION)")
    await b.send_lua("print(frame.FIRMWARE_VERSION)")
    await b.send_lua("print(frame.GIT_TAG)")

    await asyncio.sleep(1)

    await b.disconnect()


asyncio.run(main())
