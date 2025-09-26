import asyncio
from frame_ble import FrameBle

async def main():
    frame = FrameBle()

    try:
        await frame.connect()

        # Optionally attach the python print function to print incoming strings from Frame stdout
        frame._user_print_response_handler = print

        # await_print: wait for a print() to ensure the Lua has executed, not just that the command was sent successfully

        # Set up tap detection with a callback function
        await frame.send_lua("frame.imu.tap_callback(function()print('Tap detected!')end)print(0)", await_print=True)

        await asyncio.sleep(20)  # Keep the program running to listen for taps

        await frame.disconnect()

    except Exception as e:
        print(f"Not connected to Frame: {e}")
        return

if __name__ == "__main__":
    asyncio.run(main())