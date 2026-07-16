import asyncio
import argparse
from pathlib import Path
from random import randint

from brilliant_msg import BrilliantMsg, TxSprite, TxSpriteCoords, TxCode

async def main():
    """
    Sends a sprite to Frame once, then moves it around the screen.

    The sprite is a 1-bit indexed PNG image.
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

        # send the std lua files to Frame that handle data accumulation and sprite parsing and placement
        await frame.upload_stdlua_libs(lib_names=['data', 'code', 'sprite', 'sprite_coords'])

        # Send the main lua application from this project to Frame that will run the app
        await frame.upload_frame_app(local_filename="lua/sprite_game_app.lua")

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
        sprite = TxSprite.from_indexed_png_bytes(Path("images/rings_1bit.png").read_bytes())
        await frame.send_message(0x20, sprite.pack())

        # send the sprite coordinates to Frame 10 times with random positions
        # Note that the frameside app is expecting a message of type TxSpriteCoords on msgCode 0x40
        # and a message of type TxCode on msgCode 0x50 to draw everything
        for _ in range(10):
            # place sprite 0x20 at a random position on the 640x400/320x240 display,
            # given that the sprite is 200x200 pixels and the top-left corner is at (1,1)
            x = randint(1, 120)
            y = randint(1, 40)
            coords = TxSpriteCoords(0x20, x, y, 0)

            # place the sprite at the new position
            await frame.send_message(0x40, coords.pack())

            # flip the buffers to show the results of all the draw calls
            await frame.send_message(0x50, TxCode().pack())

            await asyncio.sleep(1.0)

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