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

    # 1. Configure the speaker in LC3 mode and set up BLE data handler
    await b.send_lua("frame.speaker.start{encoder='lc3', sample_rate=8000, duration=1000, channels=1, bitrate=32000, volume=50}")
    await b.send_lua("function ble_event(d)frame.speaker.play(d)end")
    await b.send_lua("frame.bluetooth.receive_callback(ble_event)")
    await asyncio.sleep(1.0)

    # 2. Load LC3 audio frames (each frame is 60 bytes)
    with open("audio/female_w1_8k_s16.lc3", "rb") as f:
        data = f.read()
    # bitrate 32000 / 800 = 40 bytes per second
    frame_size = 400  # LC3 @ 8kHz / 10ms / 32kbps

    # 3. Send and play frame by frame
    for i in range(0, len(data), frame_size):
        frame = data[i:i + frame_size]
        await b.send_data(frame, await_data=False, show_me=False, await_bt_response=False)
        await asyncio.sleep(0.1)  # 10ms playback interval (adjust based on actual latency)

    # 4. Stop playback
    await b.send_lua("frame.speaker:stop()")
    await asyncio.sleep(1.0)

    await b.disconnect()

asyncio.run(main())
