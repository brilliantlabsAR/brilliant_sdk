"""
Tests the Frame specific Lua libraries over Bluetooth.
"""

import asyncio
from frame_ble import FrameBle


async def main():
    b = FrameBle()

    await b.connect(print_response_handler=lambda s: print(s))
    
    
    while True:
        await b.send_lua("print(frame.battery_level())")
        await b.send_lua("print(frame.battery_charging())")
        await asyncio.sleep(10)

    await b.disconnect()


asyncio.run(main())
