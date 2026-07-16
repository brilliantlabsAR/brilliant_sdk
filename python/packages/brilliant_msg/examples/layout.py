import asyncio
import argparse

from brilliant_msg import BrilliantMsg, TxCode, TxTextSpriteBlock
from brilliant_ble import BrilliantDeviceType

async def main():
    """
    Use a simple layout engine to draw in separate regions of the display
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

        if frame.type != BrilliantDeviceType.HALO:
            print("layout example is Halo-only")
            await frame.disconnect()
            return
        
        # debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
        batt_mem = await frame.send_lua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', await_print=True)
        print(f"Battery Level/Memory used: {batt_mem}")
        await frame.ble.send_lua("frame.display.power_save(false);frame.display.brightness(25);print(0)", await_print=True)

        # send the std lua files to Frame that handle data accumulation and text display
        await frame.upload_stdlua_libs(lib_names=['data', 'code', 'text_sprite_block'])

        # Upload the helper code for managing the layout
        await frame.ble.upload_file(local_file_path="lua/layout/view.lua", frame_file_path="view.lua")
        await frame.ble.upload_file(local_file_path="lua/layout/bg_view.lua", frame_file_path="bg_view.lua")
        await frame.ble.upload_file(local_file_path="lua/layout/header_view.lua", frame_file_path="header_view.lua")
        await frame.ble.upload_file(local_file_path="lua/layout/body_view.lua", frame_file_path="body_view.lua")
        await frame.ble.upload_file(local_file_path="lua/layout/footer_view.lua", frame_file_path="footer_view.lua")
        await frame.ble.upload_file(local_file_path="lua/layout/speech_wave.lua", frame_file_path="speech_wave.lua")
        await frame.ble.upload_file(local_file_path="lua/layout/noa_layout.lua", frame_file_path="noa_layout.lua")

        # Upload the main frame app that will run the layout example
        await frame.upload_frame_app(local_filename="lua/layout/layout_frame_app.lua")

        frame.attach_print_response_handler()

        await frame.start_frame_app()

        print(f"Starting layout")

        await asyncio.sleep(3.0)

        # send a code to switch to recording mode
        txc_record = TxCode(1)
        await frame.send_message(0x40, txc_record.pack())

        await asyncio.sleep(3.0)

        txc_speech = TxCode(1)
        await frame.send_message(0x41, txc_speech.pack())

        # Send the text for display
        # Note that the frameside app is expecting a message of type TxTextSpriteBlock on msgCode 0x20
        # the width needs to match the NoaLayout body width (216)
        tsb = TxTextSpriteBlock(width=216,
                                line_height=25,
                                font_size=20,
                                max_display_lines=4,
                                font_family="fonts/dogicapixel.ttf"
        )

        sprite_lines = tsb.create_text_sprites("your local\nweather is\n30° celsius\nand sunny")

        # send the Image Sprite Block header
        await frame.send_message(0x50, tsb.pack())
        # then send all the slices
        for spr in sprite_lines:
            await frame.send_message(0x50, spr.pack())
            await asyncio.sleep(0.5)

        # send a code to switch off speech wave animation
        txc_speech = TxCode(0)
        await frame.send_message(0x41, txc_speech.pack())

        # in recording mode for 4 seconds
        await asyncio.sleep(4)

        # clear the text
        txc_clear_txt = TxCode(0)
        await frame.send_message(0x51, txc_clear_txt.pack())

        await asyncio.sleep(2)

        # send a code to switch off recording mode
        txc_record = TxCode(0)
        await frame.send_message(0x40, txc_record.pack())

        await asyncio.sleep(3.0)

        print(f"Stopping layout")
        frame.detach_print_response_handler()

        await frame.stop_frame_app()

        await frame.disconnect()

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        if frame.ble.is_connected:
            await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())