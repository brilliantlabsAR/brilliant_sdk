"""
Tests the Frame specific Lua libraries over Bluetooth.
"""

import asyncio
from brilliant_ble import BrilliantBle


async def main():
    b = BrilliantBle()

    try:
        await b.connect(print_response_handler=lambda s: print(s))

        # Enable taps
        await b.send_lua("frame.imu.tap_callback((function()print('Tap!')end))")

        while True:
            print("Accelerometer\t\t\t\t\t\t\t\tCompass")
            await b.send_lua("resp = frame.imu.raw()")

            await b.send_lua(
                "print(tostring(resp['accelerometer']['x'])..'\t'..tostring(resp['accelerometer']['y'])..'\t'..tostring(resp['accelerometer']['z'])..'\t'..tostring(resp['compass']['x'])..'\t'..tostring(resp['compass']['y'])..'\t'..tostring(resp['compass']['z']))",
                await_print=True,
            )
            await asyncio.sleep(0.1)
    except asyncio.CancelledError:
        pass
    finally:
        await b.disconnect()

asyncio.run(main())
