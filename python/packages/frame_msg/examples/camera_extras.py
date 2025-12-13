import asyncio
import traceback
import sys
from pathlib import Path
from frame_msg import FrameMsg, RxPhoto, TxCaptureSettings

async def main():
    frame = FrameMsg()
    try:
        await frame.connect()

        lua_script = '''
        require('camera_extras')

        -- Capture a frame with the enhancements of this library
        capture()

        -- Transfer the frame over Bluetooth as it is read
        MTU = frame.bluetooth.max_length()
        while true do
            data = frame.camera.read(MTU // 2 - 1)
            if data == nil then break end
            print(tohex(data))
        end

        print('END')
        sleep(0.3)
        '''

        # Send the library dependencies
        await frame.upload_stdlua_libs(lib_names=['camera_extras'], minified=False)

        # Send the main lua application from this project to Frame that will run the app
        await frame.upload_file_from_string(lua_script, "frame_app.lua")

        # attach the print response handler so we can see stdout from Frame Lua print() statements
        frame.attach_print_response_handler()

        # "require" the main frame_app lua file to run it, and block until it has started.
        await frame.start_frame_app()

	# Wait for 5 seconds that the script runs
        await asyncio.sleep(30.0)

        # unhook the print handler
        frame.detach_print_response_handler()

        # break out of the frame app loop and reboot Frame
        await frame.stop_frame_app()

    except Exception as e:
        print(f"An error occurred: {e}")
        traceback.print_exc()
    finally:
        # clean disconnection
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())
