import asyncio
import argparse
from PIL import Image
import io
import numpy as np

from brilliant_msg import BrilliantMsg, RxPhoto, TxCaptureSettings, TxSprite, TxImageSpriteBlock
from brilliant_ble import BrilliantDeviceType

async def main():
    """
    Repeatedly take photos using the Frame camera and display them on the Frame display
    """
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

        # debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
        batt_mem = await frame.send_lua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', await_print=True)
        print(f"Battery Level/Memory used: {batt_mem}")

        # Let the user know we're starting
        await frame.print_short_text('Loading...')

        # send the std lua files to Frame that our app needs to handle data accumulation, camera, and image display
        await frame.upload_stdlua_libs(lib_names=['data', 'camera', 'image_sprite_block'])

        # Send the main lua application from this project to Frame that will run the app
        await frame.upload_frame_app(local_filename="lua/camera_image_sprite_block_frame_app.lua")

        # attach the print response handler so we can see stdout from Frame Lua print() statements
        # If we assigned this handler before the frameside app was running,
        # any await_print=True commands will echo the acknowledgement byte (e.g. "1"), but if we assign
        # the handler now we'll see any lua exceptions (or stdout print statements)
        frame.attach_print_response_handler()

        # "require" the main frame_app lua file to run it, and block until it has started.
        # It signals that it is ready by sending something on the string response channel.
        await frame.start_frame_app()

        # NOTE: Now that the Frameside app has started there is no need to send snippets of Lua
        # code directly (in fact, we would need to send a break_signal if we wanted to because
        # the main app loop on Frame is running).
        # From this point we do message-passing with first-class types and send_message() (or send_data())

        # hook up the RxPhoto receiver
        rx_photo = RxPhoto(upright=frame.ble.type == BrilliantDeviceType.FRAME)
        photo_queue = await rx_photo.attach(frame)

        # compute the capture msg once
        resolution: int = 256 if frame.ble.type == BrilliantDeviceType.FRAME else 640

        capture_msg_bytes = TxCaptureSettings(resolution=resolution, quality_index=0, pan=-40).pack()

        print("Camera capture/display loop starting: Press Ctrl+C to quit")

        while True:

            try:
                # Request the photo capture
                await frame.send_message(0x0d, capture_msg_bytes)

                # get the jpeg bytes as soon as they're ready
                jpeg_bytes = await asyncio.wait_for(photo_queue.get(), timeout=10.0)

                # load the image with PIL
                image = Image.open(io.BytesIO(jpeg_bytes))

                # if Halo device, crop to 256x256 center square
                if frame.ble.type == BrilliantDeviceType.HALO:
                    width, height = image.size
                    new_size = 256
                    left = (width - new_size) / 2
                    top = (height - new_size) / 2
                    right = (width + new_size) / 2
                    bottom = (height + new_size) / 2
                    image = image.crop((left, top, right, bottom))

                # '1': black and white with dither
                image = image.convert('1')

                # regrettably need to unpack the nicely packed bits into bytes
                data_array = np.frombuffer(image.tobytes(), dtype=np.uint8)
                unpacked = np.unpackbits(data_array)

                # extract pixel data from unpacked.tobytes() at 1bpp and create TxSprite manually
                sprite = TxSprite(width=256,
                                height=256,
                                num_colors=2,
                                palette_data=bytes([0,0,0,255,255,255]),
                                pixel_data=unpacked.tobytes())

                # Quantize and send the image to Frame in chunks as an ImageSpriteBlock rendered progressively
                # Note that the frameside app is expecting a message of type TxImageSpriteBlock on msgCode 0x20
                isb = TxImageSpriteBlock(sprite, sprite_line_height=32)

                # send the Image Sprite Block header
                await frame.send_message(0x20, isb.pack())

                # then send all the slices
                for spr in isb.sprite_lines:
                    await frame.send_message(0x20, spr.pack())

            except asyncio.CancelledError:
                print(f"Loop cancelled, exiting")
                break

        # stop the photo receiver and clean up its resources
        rx_photo.detach(frame)

        # unhook the print handler
        frame.detach_print_response_handler()

        # break out of the frame app loop and reboot Frame
        await frame.stop_frame_app()

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        # clean disconnection
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())