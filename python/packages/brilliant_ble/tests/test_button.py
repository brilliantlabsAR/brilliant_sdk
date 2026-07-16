"""
Tests the Frame specific Lua button library over Bluetooth.
"""

import asyncio
import argparse
from brilliant_ble import BrilliantBle, BrilliantDeviceType


async def main():
    parser = argparse.ArgumentParser(description="Connect to a Halo/Frame device over BLE and run this test.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB" or "Frame 4F"; defaults to the nearest device',
    )
    args = parser.parse_args()
    b = BrilliantBle()

    name = await b.connect(name=args.name, print_response_handler=lambda s: print(s))
    fw = await b.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
    tag = await b.send_lua("print(frame.GIT_TAG)", await_print=True)
    batt = await b.send_lua("print(frame.battery_level())", await_print=True)
    print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

    if b.type != BrilliantDeviceType.HALO:
        print("Button example is Halo-only")
        await b.disconnect()
        return

    # Register button callbacks for single click, double click, and long press
    await b.send_lua("frame.button.single((function()print('Single!')end))")
    await b.send_lua("frame.button.double((function()print('Double!')end))")
    await b.send_lua("frame.button.long((function()print('Long!')end))")

    print("Waiting for button events...")

    # Keep receiving and printing messages
    while True:
        await asyncio.sleep(0.1)

    await b.disconnect()


asyncio.run(main())
