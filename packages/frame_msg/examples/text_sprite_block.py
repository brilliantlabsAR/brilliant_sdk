import asyncio

from frame_msg import FrameMsg, TxTextSpriteBlock

async def main():
    """
    Print rasterized text with a user-specified font on Frame's display using TxTextSpriteBlock
    """
    frame = FrameMsg()
    try:
        await frame.connect()

        # debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
        batt_mem = await frame.send_lua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', await_print=True)
        print(f"Battery Level/Memory used: {batt_mem}")

        # Let the user know we're starting
        await frame.print_short_text('Loading...')

        # send the std lua files to Frame that handle data accumulation and sprite text display
        await frame.upload_stdlua_libs(lib_names=['data', 'text_sprite_block'])

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
        tsb = TxTextSpriteBlock(width=320,
                                font_size=40,
                                max_display_rows=7,
                                text="Hello, friend!\nこんにちは、友人！\n朋友你好！\nПривет, друг!\n안녕, 친구!",
                                font_family="fonts/NotoSansCJK-VF.ttf.ttc"
        )

        # send the Image Sprite Block header
        await frame.send_message(0x20, tsb.pack())
        # then send all the slices
        for spr in tsb.sprites:
            await frame.send_message(0x20, spr.pack())
            await asyncio.sleep(1)

        await asyncio.sleep(1.0)

        # right-to-left script is also supported
        tsb = TxTextSpriteBlock(width=320,
                                font_size=40,
                                max_display_rows=2,
                                text="שלום, חבר!",
                                font_family="fonts/NotoSansHebrew-Regular.ttf"
        )

        # send the Image Sprite Block header
        await frame.send_message(0x20, tsb.pack())
        # then send all the slices
        for spr in tsb.sprites:
            await frame.send_message(0x20, spr.pack())

        await asyncio.sleep(2.0)

        # right-to-left script is also supported
        tsb = TxTextSpriteBlock(width=600,
                                font_size=40,
                                max_display_rows=2,
                                text="مرحبا يا صديق",
                                font_family="fonts/NotoKufiArabic-Regular.ttf"
        )

        # send the Image Sprite Block header
        await frame.send_message(0x20, tsb.pack())
        # then send all the slices
        for spr in tsb.sprites:
            await frame.send_message(0x20, spr.pack())

        await asyncio.sleep(2.0)

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