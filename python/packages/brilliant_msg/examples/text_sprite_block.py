import asyncio
import argparse

from brilliant_msg import BrilliantMsg, TxCode, TxTextSpriteBlock

async def main():
    """
    Print rasterized text with a user-specified font on Frame's display using TxTextSpriteBlock
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
        batt_mem = await frame.ble.send_lua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', await_print=True)
        print(f"Battery Level/Memory used: {batt_mem}")
        await frame.ble.send_lua("frame.display.power_save(false);frame.display.set_brightness(1);print(0)", await_print=True)

        # Let the user know we're starting
        await frame.print_short_text('Loading...')

        # send the std lua files to Frame that handle data accumulation and sprite text display
        await frame.upload_stdlua_libs(lib_names=['data', 'code', 'text_sprite_block'])

        # Send the main lua application from this project to Frame that will run the app
        await frame.upload_frame_app(local_filename="lua/text_sprite_block_frame_app.lua")

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

        # Send the text for display on Frame
        # Note that the frameside app is expecting a message of type TxTextSpriteBlock on msgCode 0x20
        tsb = TxTextSpriteBlock(width=256,
                                line_height=30,
                                font_size=20,
                                max_display_lines=4,
                                font_family="fonts/NotoSansCJK-VF.ttf.ttc"
        )

        # get the sprites for the text we want to display
        sprites = tsb.create_text_sprites("Hello, friend!\nこんにちは、友人！\n朋友你好！\nПривет, друг!\n안녕, 친구!")

        # send the Image Sprite Block header
        await frame.send_message(0x20, tsb.pack())
        # then send all the slices
        for spr in sprites:
            await frame.send_message(0x20, spr.pack())
            await asyncio.sleep(0.5)

        await asyncio.sleep(5.0)

        # send a message to clear the display
        await frame.send_message(0x21, TxCode().pack()) 

        # right-to-left script is also supported
        tsb = TxTextSpriteBlock(width=256,
                                line_height=30,
                                font_size=20,
                                max_display_lines=1,
                                font_family="fonts/NotoSansHebrew-Regular.ttf"
        )

        sprites = tsb.create_text_sprites("שלום, חבר!")

        # send the Image Sprite Block header
        await frame.send_message(0x20, tsb.pack())
        # then send all the slices
        for spr in sprites:
            await frame.send_message(0x20, spr.pack())
            await asyncio.sleep(0.5)

        await asyncio.sleep(2.0)

        # send a message to clear the display and start a fresh TextSpriteBlock
        await frame.send_message(0x21, TxCode().pack()) 

        # right-to-left script is also supported
        tsb = TxTextSpriteBlock(width=256,
                                line_height=30,
                                font_size=18,
                                max_display_lines=1,
                                font_family="fonts/NotoKufiArabic-Regular.ttf"
        )

        sprites = tsb.create_text_sprites("مرحبا يا صديق")

        # send the Image Sprite Block header
        await frame.send_message(0x20, tsb.pack())
        # then send all the slices
        for spr in sprites:
            await frame.send_message(0x20, spr.pack())
            await asyncio.sleep(0.5)

        await asyncio.sleep(2.0)

        # send a message to clear the display and start a fresh TextSpriteBlock
        await frame.send_message(0x21, TxCode().pack()) 

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