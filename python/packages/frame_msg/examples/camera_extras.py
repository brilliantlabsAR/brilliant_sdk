import asyncio
import io
import traceback
from PIL import Image
import qoi
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
        frame.camera.power_save(false)

        local start_time = frame.time.utc()
        local pipeline = {}

        --frame.camera.mpix.op.crop(pipeline, 312, 232, 16, 16)

        frame.camera.mpix.op.debayer_2x2(pipeline)
        frame.camera.mpix.op.correct_black_level(pipeline)
        frame.camera.mpix.op.correct_white_balance(pipeline)

        -- denoising
        --frame.camera.mpix.op.kernel_denoise_3x3(pipeline) -- +24 seconds?

        -- palettization
        --frame.camera.mpix.op.palette_encode(pipeline, frame.camera.mpix.fmt.PALETTE4)
        --frame.camera.mpix.op.palette_decode(pipeline)

        -- pick the output encoding
        frame.camera.mpix.op.jpeg_encode(pipeline)
        --frame.camera.mpix.op.qoi_encode(pipeline)

        frame.camera.mpix.set_pipeline(pipeline)
        frame.camera.capture{resolution=640, quality='VERY_HIGH'}

        while not frame.camera.image_ready() do
            frame.sleep(0.1)
        end

        stats = frame.camera.mpix.get_stats()

        -- from camera_extras.lua helper
        auto_black_level(stats)
        auto_white_balance(stats)

        local end_time = frame.time.utc()
        print(string.format("Capture and processing time: %.2f seconds", end_time - start_time))

        -- Transfer the frame over Bluetooth as it is read
        start_time = frame.time.utc()
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
        end_time = frame.time.utc()
        print(string.format("Bluetooth transfer time: %.2f seconds", end_time - start_time))
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

        # get the image bytes as soon as they're ready
        image_bytes = await asyncio.wait_for(photo_queue.get(), timeout=40.0)
        print("Received photo data from Frame: length =", len(image_bytes))

        # decode and display the image in the system viewer
        if False: # enable for QOI
            rgb_array = qoi.decode(image_bytes)
            image = Image.fromarray(rgb_array)
        else:
            image = Image.open(io.BytesIO(image_bytes))

        image.show()

        # stop the photo receiver and clean up its resources
        rx_photo.detach(frame)
        # unhook the print handler after waiting a moment for the bluetooth transfer time message
        await asyncio.sleep(1.0)
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
