import asyncio
import argparse
from brilliant_ble import BrilliantBle, BrilliantDeviceType

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
        print("Speaker LC3 example is Halo-only")
        await b.disconnect()
        return

    # 1. Configure the speaker in LC3 mode
    await b.send_lua("frame.speaker.start{encoder='lc3', sample_rate=8000, duration=1000, channels=1, bitrate=32000, volume=50};print('start')", await_print=True)  

    # 2. Load LC3 audio frames (each frame is 40 bytes)
    with open("audio/female_w1_8k_s16.lc3", "rb") as f:
        data = f.read()
    #bitrate 32000 / 800 = 40 bytes per frame
    frame_size = 400  # LC3 @ 8kHz / 10ms / 32kbps / 10 frames per packet

    # 3. Send and play frame by frame (with NO bluetooth ACK for each write)
    for i in range(0, len(data), frame_size):
        frame = data[i:i + frame_size]
        await b.send_audio(frame, await_bt_response=False) # takes < 1ms
        await asyncio.sleep(0.09)  # 10ms playback interval x 10 frames per packet, sleep for 100ms

    # 4. Send and play frame by frame (with bluetooth ACK for each write)
    # for i in range(0, len(data), frame_size):
    #     frame = data[i:i + frame_size]
    #     start = time.perf_counter()
    #     await b.send_audio(frame, await_bt_response=True) # can take 30-80ms, so unless we send 8+ frames per packet, we won't keep up
    #     elapsed = time.perf_counter() - start
    #     remaining = 0.1 - elapsed # 10ms playback interval x 10 frames per packet = 100ms, sleep the remaining time
    #     if remaining > 0:
    #         await asyncio.sleep(remaining)

    # 5. Leave a bit of time to finish
    await asyncio.sleep(1.0)

    # 6. Stop playback
    await b.send_lua("frame.speaker.stop();print('stop')", await_print=True)
    await asyncio.sleep(1.0)

    await b.disconnect()

asyncio.run(main())
