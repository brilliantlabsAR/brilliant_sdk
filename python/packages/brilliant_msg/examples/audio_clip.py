import asyncio
import argparse

from brilliant_msg import BrilliantMsg, RxAudio, TxCode
import tempfile

async def main():
    """
    Subscribe to an Audio stream from Frame and save a short clip as a WAV file
    """
    parser = argparse.ArgumentParser(description="Connect to a Halo/Frame device and run this example.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB" or "Frame 4F"; defaults to the nearest device',
    )
    args = parser.parse_args()
    frame = BrilliantMsg()
    speaker = None

    try:
        name = await frame.connect(name=args.name)
        fw = await frame.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
        tag = await frame.send_lua("print(frame.GIT_TAG)", await_print=True)
        batt = await frame.send_lua("print(frame.battery_level())", await_print=True)
        print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

        # Let the user know we're starting
        await frame.print_short_text('Loading...')

        # debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
        batt_mem = await frame.send_lua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', await_print=True)
        print(f"Battery Level/Memory used: {batt_mem}")

        # send the std lua files to Frame that handle data accumulation, TxCode signalling and audio
        await frame.upload_stdlua_libs(lib_names=['data', 'code', 'audio'])

        # Send the main lua application from this project to Frame that will run the app
        await frame.upload_frame_app(local_filename="lua/audio_frame_app.lua")

        # attach the print response handler so we can see stdout from Frame Lua print() statements
        frame.attach_print_response_handler()

        # "require" the main frame_app lua file to run it, and block until it has started.
        # It signals that it is ready by sending something on the string response channel.
        await frame.start_frame_app()

        # hook up the RxAudio receiver in single whole clip mode
        rx_audio = RxAudio()
        audio_queue = await rx_audio.attach(frame)

        # Tell Frame to start streaming audio
        await frame.send_message(0x30, TxCode(value=1).pack())

        # Send the stop-streaming message after 5 seconds of recording
        await asyncio.sleep(5)
        await frame.send_message(0x30, TxCode(value=0).pack())

        # get the audio samples from RxAudio as a single block
        audio_samples = await asyncio.wait_for(audio_queue.get(), timeout=10.0)

        # write the audio samples out to a WAV file
        wav_bytes = RxAudio.to_wav_bytes(audio_samples, sample_rate=8000, bits_per_sample=16)

        with tempfile.NamedTemporaryFile(delete=False, prefix="frame_audio_", suffix=".wav") as temp_wav_file:
            temp_wav_file.write(wav_bytes)
            temp_wav_file_path = temp_wav_file.name

        print(f"WAV file saved to: {temp_wav_file_path}")

        # stop the audio stream listener and clean up its resources
        rx_audio.detach(frame)

        # unhook the print handler
        frame.detach_print_response_handler()

        # break out of the frame app loop and reboot Frame
        await frame.stop_frame_app()

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        # clean disconnection
        await frame.disconnect()
        if speaker is not None:
            speaker.delete()

if __name__ == "__main__":
    asyncio.run(main())