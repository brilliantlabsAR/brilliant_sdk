import asyncio
import argparse
import traceback

from brilliant_msg import BrilliantMsg, RxAudio, TxCode
from brilliant_ble import BrilliantDeviceType
import tempfile
import time

async def main():
    """
    Subscribe to an Audio stream from Halo upon wake from Audio Activity Detection (AAD) 
    and save a short clip as a WAV file
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

        if frame.type != BrilliantDeviceType.HALO:
            print("Wake-on-audio is a Halo-only feature")
            return

        # Let the user know we're starting
        await frame.print_short_text('Loading...')

        # debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
        batt_mem = await frame.send_lua('print(frame.HARDWARE_VERSION .. " " .. frame.FIRMWARE_VERSION .. " / " .. frame.battery_level() .. " / " .. collectgarbage("count"))', await_print=True)
        print(f"Battery Level/Memory used: {batt_mem}")

        halo_time = await frame.send_lua(f'frame.time.utc({time.time()})print(frame.time.utc())', await_print=True)
        print(f"{time.time()} Current time on Halo: {halo_time}")

        # send the std lua files to Frame that handle data accumulation, TxCode signalling and audio
        await frame.upload_stdlua_libs(lib_names=['data', 'code'])

        # Send the main lua application from this project to Frame that will run the app
        await frame.upload_frame_app(local_filename="lua/wake_on_audio_frame_app.lua")

        # attach the print response handler so we can see stdout from Frame Lua print() statements
        frame.attach_print_response_handler()

        # hook up the RxAudio receiver in single whole clip mode
        rx_audio = RxAudio(streaming=True)
        audio_queue = await rx_audio.attach(frame)

        # "require" the main frame_app lua file to run it, and block until it has started.
        # It signals that it is ready by sending something on the string response channel.
        await frame.start_frame_app()

        # Halo enters standby, then starts streaming audio on wake (AAD, tap, Bluetooth)
        print(f"{time.time()} Waiting for wake/audio...")

        # Wait until the first audio chunk is available, then accumulate every chunk.
        data = bytearray(await audio_queue.get())
        print(f"{time.time()} Received audio samples, now waiting for the rest and then save the clip...")

        # Continue collecting chunks until the stream ends.
        while True:
            audio_chunk = await audio_queue.get()
            if audio_chunk is None:
                break
            data.extend(audio_chunk)

        # print data length in bytes and duration in seconds (data length / (sample_rate * bytes_per_sample))
        print(f"{time.time()} Total audio data received: {len(data)} bytes, duration: {len(data) / (8000 * 2)} seconds")

        # write the audio samples out to a WAV file
        wav_bytes = RxAudio.to_wav_bytes(bytes(data), sample_rate=8000, bits_per_sample=16)

        with tempfile.NamedTemporaryFile(delete=False, prefix="frame_audio_", suffix=".wav") as temp_wav_file:
            temp_wav_file.write(wav_bytes)
            temp_wav_file_path = temp_wav_file.name

        print(f"{time.time()} WAV file saved to: {temp_wav_file_path}")

        # stop the audio stream listener and clean up its resources
        rx_audio.detach(frame)

        # unhook the print handler
        frame.detach_print_response_handler()

        # break out of the frame app loop and reboot Frame
        await frame.stop_frame_app()

    # print error and stack trace if anything goes wrong
    except Exception as e:
        print(f"An error occurred: {e}")
        print(f"Traceback: {traceback.format_exc()}")
    finally:
        # clean disconnection
        await frame.disconnect()
        if speaker is not None:
            speaker.delete()

if __name__ == "__main__":
    asyncio.run(main())