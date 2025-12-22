import asyncio
import io
import traceback
from PIL import Image
from frame_ble import BrilliantDeviceType
from frame_msg import FrameMsg, RxPhoto

async def main():
    frame = FrameMsg()
    try:
        await frame.connect()

        lua_script = '''
        print('App Started')
        require('camera_extras')

        -- Capture a frame with the enhancements of this library
        if true then
            frame.camera.power_save(false)
            local start_time = frame.time.utc()

            --local pipeline = {}
            --frame.camera.mpix.op.debayer_3x3(pipeline)
            --frame.camera.mpix.op.jpeg_encode(pipeline)
            --frame.camera.mpix.set_pipeline(pipeline)
            frame.camera.capture{resolution=640, quality='VERY_HIGH'}
            while not frame.camera.image_ready() do
                frame.sleep(0.005)
            end

            local end_time = frame.time.utc()
            print(string.format("Capture and processing time: %.2f seconds", end_time - start_time))


        else
            capture()
        end

        -- Transfer the frame over Bluetooth as it is read
        MTU = frame.bluetooth.max_length()
        while true do
            data = frame.camera.read(MTU - 1)
            if data == nil then
                frame.bluetooth.send('\x08')
                break
            elseif data ~= '' then
                frame.bluetooth.send('\x07' .. data)
            end
        end
        '''

        # Send the library dependencies
        await frame.upload_stdlua_libs(lib_names=['camera_extras'], minified=False)

        # Send the main lua application from this project to Frame that will run the app
        await frame.upload_file_from_string(lua_script, "frame_app.lua")

        # attach the print response handler so we can see stdout from Frame Lua print() statements
        frame.attach_print_response_handler()

        # hook up the RxPhoto receiver
        rx_photo = RxPhoto(upright=frame.ble.type == BrilliantDeviceType.FRAME)
        photo_queue = await rx_photo.attach(frame)

        # "require" the main frame_app lua file to run it, and block until it has started.
        await frame.start_frame_app()

        # get the jpeg bytes as soon as they're ready
        jpeg_bytes = await asyncio.wait_for(photo_queue.get(), timeout=20.0)
        print("Received photo data from Frame: length =", len(jpeg_bytes))

        # display the image in the system viewer
        image = Image.open(io.BytesIO(jpeg_bytes))
        image.show()

        # stop the photo receiver and clean up its resources
        rx_photo.detach(frame)
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
