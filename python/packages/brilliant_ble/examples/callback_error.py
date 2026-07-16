"""Show how Lua errors raised inside tap/data callbacks behave, and how to catch them with pcall."""
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
        print("Setting up tap callback with error...")
        await frame.send_lua("frame.imu.tap_callback(function()print('tap')error('error in tap handler!')print('after error')end)print(0)", await_print=True)
        await asyncio.sleep(10) # wait to listen for taps

        # Set up data handler with a callback function that errors
        print("Setting up data callback with error...")
        await frame.send_lua("frame.bluetooth.receive_callback(function()print('data')error('error in data handler!')print('after error')end)print(0)", await_print=True)
        await asyncio.sleep(1)
        await frame.send_data(b"Hello!")
        await asyncio.sleep(1) # wait to let data processing occur
        await frame.send_data(b"Hello Again!")
        await asyncio.sleep(1) # wait to let data processing occur

        # Set up data handler with a callback function that errors, but use pcall to catch the error
        print("Setting up data callback with error and pcall/print...")
        await frame.send_lua("frame.bluetooth.receive_callback(function()print(0) rc,err=pcall(error, 'data error') if rc==false then print(err) end print('after error')  end) print(1)", await_print=True)
        await asyncio.sleep(1)
        await frame.send_data(b"Hello!")
        await asyncio.sleep(1)


    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())