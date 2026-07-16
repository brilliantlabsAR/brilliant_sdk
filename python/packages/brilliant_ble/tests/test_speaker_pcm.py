import asyncio
import argparse
from brilliant_ble import BrilliantBle, BrilliantDeviceType

# convert s8 to s16 le
def s8_to_s16_le(data: bytes) -> bytes:
    """Convert signed 8-bit PCM to little-endian signed 16-bit PCM."""
    out = bytearray(len(data) * 2)
    j = 0
    for b in data:
        s8 = b - 256 if b >= 128 else b
        s16 = (s8 << 8) & 0xffff
        out[j] = s16 & 0xff
        out[j + 1] = (s16 >> 8) & 0xff
        j += 2
    return bytes(out)


async def main():
    parser = argparse.ArgumentParser(description="Connect to a Halo/Frame device over BLE and run this test.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB" or "Frame 4F"; defaults to the nearest device',
    )
    args = parser.parse_args()
    b = BrilliantBle()
    name = await b.connect(name=args.name)
    fw = await b.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
    tag = await b.send_lua("print(frame.GIT_TAG)", await_print=True)
    batt = await b.send_lua("print(frame.battery_level())", await_print=True)
    print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

    if b.type != BrilliantDeviceType.HALO:
        print("Speaker PCM example is Halo-only")
        await b.disconnect()
        return

    frame_size = 400
 
    # load the sample s8 pcm audio
    with open("audio/female_w1_8k_s8.pcm", "rb") as f:
        data8 = f.read()

    b._user_print_response_handler = print

    # 16-bit
    data = s8_to_s16_le(data8)
    await b.send_lua("frame.speaker.start{encoder='pcm', sample_rate=8000, bit_depth=16, channels=1, volume=50};print('speaker started')", await_print=True)
    
    # Send and play frame by frame
    for i in range(0, len(data), frame_size):
        frame = data[i:i + frame_size]
        await b.send_audio(frame, await_bt_response=False) # takes < 1ms, compared with 30-80ms for withResponse
        await asyncio.sleep(0.024) # 16000 bytes/second for s16 = 1/40 second (should be 0.025)

    # 4. Stop playback
    await b.send_lua("frame.speaker.stop();print('speaker stopped')", await_print=True)
    await asyncio.sleep(1.0)

    await b.disconnect()

asyncio.run(main())
