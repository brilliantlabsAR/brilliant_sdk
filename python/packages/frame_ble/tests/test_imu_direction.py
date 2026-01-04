"""
Tests the Frame specific Lua libraries over Bluetooth.
"""

import asyncio
from frame_ble import FrameBle


async def main():
    b = FrameBle()

    try:
        await b.connect(print_response_handler=lambda s: print(s))

        # Enable taps
        await b.send_lua("frame.imu.tap_callback((function()print('Tap!')end))")

        while True:
            await b.send_lua("resp = frame.imu.direction()")

            await b.send_lua(
                "print('roll: '..tostring(resp['roll'])..'\tpitch: '..tostring(resp['pitch'])..'\theading: '..tostring(resp['heading']))",
                await_print=True,
            )
            await asyncio.sleep(0.1)
    except asyncio.CancelledError:
        pass
    finally:
        await b.disconnect()

asyncio.run(main())
