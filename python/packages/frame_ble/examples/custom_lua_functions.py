import asyncio
from frame_ble import FrameBle

async def main():
    frame = FrameBle()

    try:
        await frame.connect()

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

        await frame.disconnect()

    except Exception as e:
        print(f"Not connected to Device: {e}")
        return

if __name__ == "__main__":
    asyncio.run(main())