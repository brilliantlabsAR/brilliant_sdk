import asyncio
import argparse
from pathlib import Path

from brilliant_msg import BrilliantMsg, TxSprite

async def main():
    """
    Displays sample images on the Frame display.

    The images are indexed (palette) PNG images, in 2, 4, and 16 colors (that is, 1-, 2- and 4-bits-per-pixel).

    They are using the standard palette from the Frame firmware. If you want to display sprites that have
    palettes of other colors, the frameside app must call `sprite.set_palette()` (which lua/sprite_frame_app.lua does)
    or call the underlying `frame.display.assign_color()` before the `frame.display.bitmap()` call.
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

        # send the std lua files to Frame that handle data accumulation and sprite parsing
        await frame.upload_stdlua_libs(lib_names=['data', 'sprite'])

        # Send the main lua application from this project to Frame that will run the app
        await frame.upload_frame_app(local_filename="lua/sprite_frame_app.lua")

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

        # send the 1-bit image to Frame in chunks
        # Note that the frameside app is expecting a message of type TxSprite on msgCode 0x20
        sprite = TxSprite.from_indexed_png_bytes(Path("images/logo_1bit.png").read_bytes())
        await frame.send_message(0x20, sprite.pack())
        await asyncio.sleep(5.0)

        # send a 2-bit image
        sprite = TxSprite.from_indexed_png_bytes(Path("images/street_2bit.png").read_bytes())
        await frame.send_message(0x20, sprite.pack())
        await asyncio.sleep(5.0)

        # send a 4-bit image
        sprite = TxSprite.from_indexed_png_bytes(Path("images/hotdog_4bit.png").read_bytes())
        await frame.send_message(0x20, sprite.pack())
        await asyncio.sleep(5.0)

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