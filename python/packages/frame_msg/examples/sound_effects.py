import asyncio

from frame_msg import FrameMsg, TxCode
from frame_ble import BrilliantDeviceType

async def main():
    """
    Play sound effects through the Halo speakers
    """
    frame = FrameMsg()
    try:
        await frame.connect()

        if frame.type != BrilliantDeviceType.HALO:
            print("Speaker is a Halo-only feature")
            return

        # debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
        batt_mem = await frame.send_lua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', await_print=True)
        print(f"Battery Level/Memory used: {batt_mem}")

        # Let the user know we're starting
        await frame.print_short_text('Loading...')

        # send the std lua files to Frame that handle data accumulation and text display
        await frame.upload_stdlua_libs(lib_names=['data', 'code'])
        await frame.ble.upload_file(local_file_path="lua/sfxr.min.lua", frame_file_path="sfxr.lua")

        # Send the main lua application from this project to Frame that will run the app
        await frame.upload_frame_app(local_filename="lua/sound_effects_frame_app.lua")

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

        # start the speaker
        await frame.send_message(0x42, TxCode(1).pack())
        await asyncio.sleep(1.0)

        # play a sine wave test tone
        await frame.send_message(0x42, TxCode(2).pack())
        await asyncio.sleep(5.0)

        for _ in range(10):
            # Send the code to play one random sound effect
            # Note that the frameside app is expecting a message of type TxCode on msgCode 0x42
            await frame.send_message(0x42, TxCode(3).pack())
            await asyncio.sleep(8.0)

        # start the speaker
        await frame.send_message(0x42, TxCode(0).pack())
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