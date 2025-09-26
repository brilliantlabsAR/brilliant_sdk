"""
Tests the Frame specific Lua libraries over Bluetooth.
"""

import asyncio
from frame_ble import FrameBle


async def main():
    b = FrameBle()

    await b.connect(print_response_handler=lambda s: print(s))

    await b.send_lua("frame.imu.tap_callback((function()print('Tap!')end))")

    await asyncio.sleep(100)

    await b.disconnect()


asyncio.run(main())
