"""
paired_tap_counter.py — host-side client for lua/tap_counter.lua.

The Lua app counts IMU taps and sends the running total over BLE.
The host prints each update and can reset the count.

Usage:
    python paired_tap_counter.py                # real Halo hardware
    python paired_tap_counter.py --emulator     # emulator, injects 5 taps then resets

To switch from emulator to real hardware, change --emulator to nothing (or set
USE_EMULATOR = False below).  No other code changes are needed.
"""

import asyncio
import argparse

MSG_COUNT = 0x10   # Lua sends this code with the tap count byte
MSG_RESET = 0xFF   # Host sends this code to reset the counter


async def main() -> None:
    parser = argparse.ArgumentParser(description="Tap counter demo")
    parser.add_argument("--emulator", action="store_true", help="Use the emulator")
    args = parser.parse_args()

    # ---- connection ----
    if args.emulator:
        from halo_emulator import HaloEmulator, EmulatorBrilliantMsg
        emu = HaloEmulator(sandbox_dir="./lua")
        frame = EmulatorBrilliantMsg(emu)
    else:
        from brilliant_msg import BrilliantMsg          # type: ignore[import]
        frame = BrilliantMsg()

    try:
        await frame.connect()

        # Upload and start the Lua app
        await frame.upload_frame_app(
            local_filename="lua/tap_counter.lua",
            frame_filename="tap_counter.lua",
        )
        await frame.start_frame_app(frame_app_name="tap_counter", await_print=True)

        # ---- register handler for tap count messages ----
        def on_count(data: bytes) -> None:
            count = data[1]
            print(f"Tap count received: {count}")

        frame.register_data_response_handler(on_count, [MSG_COUNT], on_count)

        if args.emulator:
            # ---- emulator: inject events programmatically ----
            print("Injecting 5 taps...")
            for i in range(5):
                frame.inject_imu_tap()
                await asyncio.sleep(0.2)   # give Lua time to process each tap

            await asyncio.sleep(0.3)
            print("Sending reset...")
            await frame.send_message(MSG_RESET, b"")

            await asyncio.sleep(0.3)
            print("Injecting 2 more taps after reset...")
            frame.inject_imu_tap()
            await asyncio.sleep(0.2)
            frame.inject_imu_tap()
            await asyncio.sleep(0.3)

            frame.get_framebuffer().save("tap_counter_output.png")
            print("Saved tap_counter_output.png")

        else:
            # ---- real hardware: wait for physical taps ----
            print("Waiting for taps on device (30s)...")
            print("Press Ctrl+C to send a reset and exit.")
            try:
                await asyncio.sleep(30)
            except KeyboardInterrupt:
                print("\nSending reset...")
                await frame.send_message(MSG_RESET, b"")
                await asyncio.sleep(0.5)

        frame.unregister_data_response_handler(on_count)

    finally:
        await frame.stop_frame_app()
        await frame.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
