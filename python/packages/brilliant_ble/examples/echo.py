"""Send Lua snippets to the device REPL and print the results (a tour of the Lua API over BLE)."""
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

        # Print literals or computed Lua expressions
        print("Sending Lua commands to print literals and computed expressions...")
        await frame.send_lua("print(123)", await_print=True)
        await frame.send_lua("print('echo!')", await_print=True)
        await frame.send_lua("print(5*5*5)", await_print=True)

        # Frame Lua API is available in these commands; see https://docs.brilliant.xyz/frame/building-apps-lua/
        print("Printing some API values...")
        await frame.send_lua("print(frame.HARDWARE_VERSION)", await_print=True)
        await frame.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
        await frame.send_lua("print(frame.battery_level())", await_print=True)

        # "Returns the amount of memory currently used by the program in Kilobytes."
        print("Printing memory usage...")
        await frame.send_lua("print(collectgarbage('count'))", await_print=True)

        # Multiple statements are ok
        print("Multiple statements in one send_lua() are ok...")
        await frame.send_lua("my_var = 2^8; print(my_var)", await_print=True)

        # receive the printed response synchronously as a returned result from send_lua()
        print("Lua expressions can be sent with send_lua() and the printed result received as a return value...")
        my_exponent = 10
        response = await frame.send_lua(f"my_var = 2^{my_exponent}; print(my_var)", await_print=True)
        print(f"Answer was: {response}")

        # we can define a global function that persists until a reset
        print("Defining a global Lua function to compute Fibonacci numbers...")
        await frame.send_lua("fib=setmetatable({[0]=0,[1]=1},{__index=function(t,n) t[n]=t[n-1]+t[n-2]; return t[n] end});print(0)", await_print=True)
        my_fib_num = 20
        # and then call it
        fib_answer = await frame.send_lua(f"print(fib[{my_fib_num}])", await_print=True)
        print(f"Fibonacci number {my_fib_num} is: {fib_answer}")

        # If lines of code will be too long to fit in a single bluetooth packet(~240 bytes, depending)
        # then other strategies are needed, including sending Lua files to Frame and then calling their functions.
        # see custom_lua_functions.py for examples.
        # For structured message-passing of images, audio etc. between Frame and host, consider the frame-msg package.

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())