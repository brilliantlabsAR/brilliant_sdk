import asyncio
from frameutils import Bluetooth

# Convert frame data to a Lua-compatible hexadecimal string
def bin2lua_hex(data: bytes) -> str:
    return '"' + ''.join(f'\\x{b:02x}' for b in data) + '"'

async def main():
    b = Bluetooth()
    await b.connect()

    # 1. Configure the speaker in pcm mode
    await b.send_lua("frame.speaker.start{encoder='pcm', sample_rate=8000, is_signed = 1, bit_depth=8, channels=1}")
    await b.send_lua("frame.speaker.volume(10)")


    with open("/home/lht/fl/alif/applications/frame/tests/female_w1_8k_s8.pcm", "rb") as f:
        data = f.read()

    frame_size = 320

    # 3. Send and play frame by frame
    for i in range(0, len(data), frame_size):
        frame = data[i:i + frame_size]
        # lua_hex = bin2lua_hex(frame)
        # await b.send_lua(f"frame.speaker.play({lua_hex})")
        await b.send_audio(frame)
        # await asyncio.sleep(0.01)  # 10ms playback interval (adjust based on actual latency)

    # 4. Stop playback
    await b.send_lua("frame.speaker:stop()")
    await asyncio.sleep(1.0)

    await b.disconnect()

asyncio.run(main())
