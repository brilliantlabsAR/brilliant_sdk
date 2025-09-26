import asyncio
from frame_ble import FrameBle
import time

# Convert frame data to a Lua-compatible hexadecimal string
def bin2lua_hex(data: bytes) -> str:
    return '"' + ''.join(f'\\x{b:02x}' for b in data) + '"'

async def main():
    b = FrameBle()
    await b.connect()

    # 1. Configure the speaker in LC3 mode
    await b.send_lua("frame.speaker.start{encoder='lc3', sample_rate=8000, bit_depth=16, channels=1, bitrate=16000}")
    await b.send_lua("frame.speaker.volume(50)")
    

    # 2. Load LC3 audio frames (each frame is 60 bytes)
    with open("tests/audio/female_w1_8k_s16.lc3", "rb") as f:
        data = f.read()
    #bitrate 32000 / 800 = 40 bytes per second
    frame_size = 400  # LC3 @ 8kHz / 10ms / 32kbps

    # 3. Send and play frame by frame
    for i in range(0, len(data), frame_size):
        frame = data[i:i + frame_size]
        lua_hex = bin2lua_hex(frame)
        #await b.send_lua(f"frame.speaker.play({lua_hex})")
        # print(time.time())
        await b.send_audio(frame)
        # await asyncio.sleep(0.01)  # 10ms playback interval (adjust based on actual latency)

    # 4. Stop playback
    await b.send_lua("frame.speaker:stop()")
    await asyncio.sleep(1.0)

    await b.disconnect()

asyncio.run(main())
