"""
Tests the Frame specific Lua button library over Bluetooth.
"""

import asyncio
from frame_ble import FrameBle, BrilliantDeviceType


async def main():
    b = FrameBle()

    await b.connect(print_response_handler=lambda s: print(s))

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
