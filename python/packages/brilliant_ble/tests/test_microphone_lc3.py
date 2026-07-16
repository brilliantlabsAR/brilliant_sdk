"""
Tests the Halo-specific Lua libraries over Bluetooth.
Records LC3-encoded audio via Bluetooth and saves it as both .lc3 and .wav files.
"""

import asyncio
import argparse
from brilliant_ble import BrilliantBle, BrilliantDeviceType
import numpy as np
import lc3
import wave
from datetime import datetime

audio_buffer = b""  # Global buffer to store incoming LC3 audio data


def receive_data(data):
    """
    Callback function to handle incoming Bluetooth data chunks.
    Appends received data to the global audio buffer.
    """
    global audio_buffer
    audio_buffer += data
    print(f"Received {len(audio_buffer)} bytes", end="\r")


async def record_and_save(b: BrilliantBle, sample_rate, bitrate, frame_duration_ms, channels=1):
    """
    Starts microphone recording using LC3 encoder on the device,
    receives LC3 audio data via Bluetooth,
    and saves both .lc3 and decoded .wav files.
    """
    global audio_buffer
    audio_buffer = b""

    # Ensure microphone is stopped before starting
    await b.send_break_signal()
    await asyncio.sleep(1)
    await b.send_lua("frame.microphone.stop()")

    print(f"Recording LC3 audio: {sample_rate} Hz, {bitrate} bps, {channels} channels")

    # Start microphone recording with LC3 encoder
    await b.send_lua(
        f"frame.microphone.start{{encoder='lc3', sample_rate={sample_rate}, bitrate={bitrate}, channels={channels}}}"
    )
    
    await asyncio.sleep(1)

    # Loop: read LC3 frames and send them over Bluetooth
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

    # Wait to ensure all data is received
    await asyncio.sleep(5)

    # Generate timestamped filenames
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    lc3_filename = f"audio_{timestamp}.lc3"
    wav_filename = f"audio_{timestamp}.wav"

    # Save raw LC3 file
    with open(lc3_filename, "wb") as f:
        f.write(audio_buffer)
    print(f"Saved LC3 audio to {lc3_filename}")

    # Decode LC3 buffer to PCM
    frame_bytes = int(round(bitrate * frame_duration_ms / 1000 / 8)) * channels
    decoder = lc3.Decoder(frame_duration_ms*1000, sample_rate, 1)
    
    print(f"Decoding {len(audio_buffer)} bytes into {frame_bytes} byte frames")
    wavfile = wave.open(wav_filename, 'wb')
    wavfile.setnchannels(channels)
    wavfile.setsampwidth(2)
    wavfile.setframerate(sample_rate)
    

    for i in range(0, len(audio_buffer), frame_bytes):
        chunk = audio_buffer[i:i + frame_bytes]
        if len(chunk) < frame_bytes:
            break  # Skip incomplete frame
        try:
            if channels == 2:
                
                pcm_left = decoder.decode(chunk[0:frame_bytes//2], bit_depth=16)
                pcm_right = decoder.decode(chunk[frame_bytes//2:], bit_depth=16)
             
                # Interleave stereo PCM
                interleaved = np.zeros(len(pcm_left), dtype=np.int16)
                interleaved[0::2] = np.frombuffer(pcm_left, dtype=np.int16)
                interleaved[1::2] = np.frombuffer(pcm_right, dtype=np.int16)
                wavfile.writeframesraw(interleaved.tobytes())
                
            else:
                pcm = decoder.decode(chunk, bit_depth=16)
                wavfile.writeframesraw(pcm)
           
        except Exception as e:
            print(f"\nDecoding error at offset {i}: {e}")
            break
    print(f"Saved decoded audio to {wav_filename}")
    wavfile.close()


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

    if b.type != BrilliantDeviceType.HALO:
        print("LC3 microphone example is Halo-only")
        await b.disconnect()
        return


    await record_and_save(b, sample_rate=16000, bitrate=32000, frame_duration_ms=10, channels=1)
    await b.disconnect()

1
asyncio.run(main())
