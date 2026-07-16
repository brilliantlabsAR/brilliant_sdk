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

    try:
        await b.connect(name=args.name, print_response_handler=lambda s: print(s))

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
