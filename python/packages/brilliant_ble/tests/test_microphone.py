"""
Tests the Frame-specific Lua libraries over Bluetooth.
Records audio and saves it as a WAV file with timestamped filename.
"""

import asyncio
import argparse
from brilliant_ble import BrilliantBle
import numpy as np
import wave
from datetime import datetime

audio_buffer = b""  # Global buffer to store incoming audio data


def receive_data(data):
    """
    Callback function to handle incoming Bluetooth data chunks.
    """
    global audio_buffer
    audio_buffer += data
    print(f"Received {len(audio_buffer)} bytes", end="\r")


async def record_and_save(b: BrilliantBle, sample_rate, bit_depth, channels=2):
    """
    Sends commands to start/stop microphone recording on the device,
    receives audio data over Bluetooth, and saves it as a timestamped WAV file.
    """
    global audio_buffer
    audio_buffer = b""
    
        # Stop recording
    await b.send_break_signal()
    await asyncio.sleep(1)
    await b.send_lua("frame.microphone.stop()")


    print(f"Streaming at {sample_rate / 1000}kHz, {bit_depth}bit, {channels} channels")

    # Start microphone recording
    await b.send_lua(
        f"frame.microphone.start{{sample_rate={sample_rate}, bit_depth={bit_depth}, channels={channels}}}"
    )
    
    
    # Read audio buffer and send it over Bluetooth in chunks
    await b.send_lua(
        f"while true do "
        f"s=frame.microphone.read({240}); " 
        f"if s==nil then break end "
        f"if s~='' then "
        f"while true do "
        f"if (pcall(frame.bluetooth.send,s)) then break end "
        f"end "
        f"end "
        f"end"
    )
    
    # Record for a few seconds
    await asyncio.sleep(5)

    # Stop recording
    await b.send_break_signal()
    await asyncio.sleep(1)
    await b.send_lua("frame.microphone.stop()")

    print("\nStopping recording...")
    
    # Wait for data to finish transmitting
    await asyncio.sleep(5)


    print("\nConverting to WAV...")

   # Choose dtype and sample width based on bit depth
    if bit_depth == 16:
        dtype = np.int16
        sampwidth = 2
        audio_data = np.frombuffer(audio_buffer, dtype=dtype)

    elif bit_depth == 8:
        dtype = np.int8  # Raw signed 8-bit from device
        sampwidth = 1
        signed_data = np.frombuffer(audio_buffer, dtype=dtype)

        # Convert signed int8 [-128, 127] to unsigned uint8 [0, 255]
        audio_data = (signed_data.astype(np.int16) + 128).astype(np.uint8)

    # Generate timestamped filename
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"output_{timestamp}.wav"

    # Save to WAV file
    with wave.open(filename, "wb") as wf:
        wf.setnchannels(channels)
        wf.setsampwidth(sampwidth)
        wf.setframerate(sample_rate)
        wf.writeframes(audio_data.tobytes())

    print(f"\nAudio saved as {filename}")


async def main():
    parser = argparse.ArgumentParser(description="Connect to a Halo/Frame device over BLE and run this test.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB" or "Frame 4F"; defaults to the nearest device',
    )
    args = parser.parse_args()
    b = BrilliantBle()
    name = await b.connect(name=args.name, data_response_handler=receive_data)
    fw = await b.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
    tag = await b.send_lua("print(frame.GIT_TAG)", await_print=True)
    batt = await b.send_lua("print(frame.battery_level())", await_print=True)
    print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")
    await record_and_save(b, sample_rate=16000, bit_depth=16, channels=1)
    await b.disconnect()


asyncio.run(main())
