"""
Tests the Frame specific Lua libraries over Bluetooth.
"""

import asyncio
from frame_ble import FrameBle


async def main():
    b = FrameBle()

    await b.connect(print_response_handler=lambda s: print(s))

    try:
        while True:
            await b.send_lua("print('Battery Level: ' .. tostring(frame.battery_level()))")
            await b.send_lua("print('Charging: ' .. tostring(frame.battery_charging()))")
            await asyncio.sleep(5)

    except asyncio.CancelledError:
        pass
    finally:
        await b.disconnect()


asyncio.run(main())
