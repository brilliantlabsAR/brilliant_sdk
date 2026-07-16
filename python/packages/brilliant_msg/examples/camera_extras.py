import asyncio
import argparse
import io
import traceback
from PIL import Image
import qoi
from brilliant_ble import BrilliantDeviceType
from brilliant_msg import BrilliantMsg, RxPhoto

async def main():
    parser = argparse.ArgumentParser(description="Connect to a Halo/Frame device and run this example.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB" or "Frame 4F"; defaults to the nearest device',
    )
    args = parser.parse_args()
    frame = BrilliantMsg()
    try:
        name = await frame.connect(name=args.name)
        fw = await frame.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
        tag = await frame.send_lua("print(frame.GIT_TAG)", await_print=True)
        batt = await frame.send_lua("print(frame.battery_level())", await_print=True)
        print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

        # Send the main lua application from this project to Frame that will run the app
        await frame.upload_frame_app(local_filename="lua/camera_extras_frame_app.lua")

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
        if False: # enable for QOI (also change lua/camera_extras_frame_app.lua to output QOI)
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
