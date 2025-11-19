import asyncio
from frame_ble import FrameBle

# Convert frame data to a Lua-compatible hexadecimal string
def bin2lua_hex(data: bytes) -> str:
    return '"' + ''.join(f'\\x{b:02x}' for b in data) + '"'

async def main():
    b = FrameBle()
    await b.connect()

    b._user_print_response_handler = print

    # 1. Configure the speaker in pcm mode
    await b.send_lua("frame.speaker.start{encoder='pcm', sample_rate=8000, is_signed = 1, bit_depth=8, channels=1};print(0)", await_print=True)
    await b.send_lua("frame.speaker.volume(50);print(1)", await_print=True)
    await b.send_lua("print(frame.bluetooth.max_length())", await_print=True)
    print(b.max_data_payload())


    with open("tests/audio/female_w1_8k_s8.pcm", "rb") as f:
        data = f.read()

    frame_size = 400

    # 3. Send and play frame by frame
    for i in range(0, len(data), frame_size):
        frame = data[i:i + frame_size]
        await b.send_audio(frame, await_bt_response=False) # takes < 1ms, compared with 30-80ms for withResponse
        await asyncio.sleep(0.05) # 8000 bytes/second = 1/20 second (should be 0.05)

    # 4. Stop playback
    await b.send_lua("frame.speaker.stop();print(2)", await_print=True)
    await asyncio.sleep(1.0)

    await b.disconnect()

asyncio.run(main())
