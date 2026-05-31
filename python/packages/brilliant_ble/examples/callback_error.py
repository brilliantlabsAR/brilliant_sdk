import asyncio
from brilliant_ble import FrameBle

async def main():
    frame = FrameBle()

    try:
        await frame.connect()

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


        await frame.disconnect()

    except Exception as e:
        print(f"Not connected to Device: {e}")
        return

if __name__ == "__main__":
    asyncio.run(main())