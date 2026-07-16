"""Upload a Lua file of helper functions to the device and call them over BLE."""
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
        # Note that the upload_file() function will receive a byte from Frame after every packet, and a nil
        # when the end of file is reached and the file is saved. To reduce noise in the log, you can
        # attach the print handler after files are loaded.
        frame._user_print_response_handler = None

        # If I have too much code to fit in a single send_lua() command due to bluetooth MTU limits (~240 bytes)
        # I can put my functions into a file and send it over. (The library splits the file for sending and
        # reassembles it on the other side.)
        await frame.upload_file("lua/fibonacci.lua", "fibonacci.lua")

        # "require()" a file in Lua to execute it - in this case, create the fibonacci(n) function definition.
        # Note that this require() statement completes after the file is run. Other Lua files might
        # begin a main running loop when started with require(), so putting a print() statement afterwards
        # and await_print=True would not work in that case.
        # await_print: wait for a print() to ensure the Lua has executed, not just that the command was sent successfully
        await frame.send_lua("require('fibonacci');print(0)", await_print=True)

        # we can call the function(s) loaded from the file
        my_fib_num = 20
        response = await frame.send_lua(f"print('Fibonacci({my_fib_num}) = ' .. fibonacci({my_fib_num}))", await_print=True)
        print(response)

        # For structured message-passing of images, audio etc. between Frame and host, consider the frame-msg package.

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())