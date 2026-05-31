"""
Tests the Frame specific Lua libraries over Bluetooth.
"""
import asyncio
from brilliant_ble import BrilliantBle


async def main():
    b = BrilliantBle()

    await b.connect(print_response_handler=lambda s: print(s))

    await b.send_lua("frame.imu.tap_callback((function()print('Tap!')end))")
    print("Waiting for taps... Tap the device to see output. Ctrl+C to stop.")

    try:
        while True:
            await asyncio.sleep(1)
    except asyncio.CancelledError:
        pass
    finally:
        await b.disconnect()

asyncio.run(main())
