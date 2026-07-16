"""
Tests the Frame specific Lua libraries over Bluetooth.
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

    try:
        while True:
            await b.send_lua("print('Battery Level: ' .. tostring(frame.battery_level()))")
            if b.type == BrilliantDeviceType.HALO:
                await b.send_lua("print('Charging: ' .. tostring(frame.battery_charging()))")
            await asyncio.sleep(5)

    except asyncio.CancelledError:
        pass
    finally:
        await b.disconnect()


asyncio.run(main())
