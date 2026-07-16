import asyncio
import argparse
from brilliant_ble import BrilliantBle

async def main():
    parser = argparse.ArgumentParser(description="Connect to a Halo/Frame device over BLE and run this example.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB" or "Frame 4F"; defaults to the nearest device',
    )
    args = parser.parse_args()
    frame = BrilliantBle()

    try:
        name = await frame.connect(name=args.name)
        fw = await frame.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
        tag = await frame.send_lua("print(frame.GIT_TAG)", await_print=True)
        batt = await frame.send_lua("print(frame.battery_level())", await_print=True)
        print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

        # Optionally attach the python print function to print incoming strings from Frame stdout
        frame._user_print_response_handler = print

        # await_print: wait for a print() to ensure the Lua has executed, not just that the command was sent successfully

        # Set up tap detection with a callback function
        await frame.send_lua("frame.imu.tap_callback(function()print('Tap detected!')end)print(0)", await_print=True)

        await asyncio.sleep(20)  # Keep the program running to listen for taps

        await frame.disconnect()

    except Exception as e:
        print(f"Not connected to Device: {e}")
        return

if __name__ == "__main__":
    asyncio.run(main())