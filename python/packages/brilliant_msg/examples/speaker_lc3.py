import asyncio
import argparse

from brilliant_msg import BrilliantMsg, TxCode
from brilliant_ble import BrilliantDeviceType

async def main():
    """
    Play an LC3 file on the Halo speakers
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
            print("Speaker is a Halo-only feature")
            return

        # debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
        batt_mem = await frame.send_lua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', await_print=True)
        print(f"Battery Level/Memory used: {batt_mem}")

        # Let the user know we're starting
        await frame.print_short_text('Loading...')

        # send the std lua files to Frame that handle data accumulation and text display
        await frame.upload_stdlua_libs(lib_names=['data', 'code'])

        # Send the main lua application from this project to Frame that will run the app
        await frame.upload_frame_app(local_filename="lua/speaker_frame_app.lua")

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

        # Send the code to start speaker playback
        # Note that the frameside app is expecting a message of type TxCode on msgCode 0x42
        # with a value of 1/0 for start/stop
        await frame.send_message(0x42, TxCode(1).pack())
        await asyncio.sleep(1.0)

        # load and send LC3 frames from the sample file
        with open("audio/female_w1_8k_s16.lc3", "rb") as f:
            data = f.read()
        # bitrate 32000 / 800 = 40 bytes per frame
        frame_size = 400  # LC3 @ 8kHz / 10ms / 32kbps / 10 frames per packet

        # Send and play 5 frames at a time
        for i in range(0, len(data), frame_size):
            audio_frame = data[i:i + frame_size]
            await frame.send_audio(audio_frame, await_bt_response=False)
            await asyncio.sleep(0.09)  # 10ms frames, 10 frames per packet

        # let the playback finish before we stop the stream and exit
        await asyncio.sleep(1.0)

        # send the command that will call frame.speaker.stop()
        await frame.send_message(0x42, TxCode(0).pack())
        await asyncio.sleep(1.0)

        # unhook the print handler
        frame.detach_print_response_handler()

        # break out of the frame app loop and reboot Halo
        await frame.stop_frame_app()

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        # clean disconnection
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())