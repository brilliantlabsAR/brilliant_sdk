import asyncio
import argparse
from brilliant_ble import BrilliantBle, BrilliantDeviceType

async def main():
    parser = argparse.ArgumentParser(description="Connect to a Halo/Frame device over BLE and run this example.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB" or "Frame 4F"; defaults to the nearest device',
    )
    args = parser.parse_args()
    frame = BrilliantBle()

    try:
        await frame.connect(name=args.name)

        if frame.type != BrilliantDeviceType.HALO:
            print("animated_drawing example is Halo-only")
            await frame.disconnect()
            return
        
        await frame.send_lua("frame.display.power_save(false);frame.display.brightness(25);print(0)", await_print=True)
        await frame.upload_file("lua/animated_drawing.lua", "animated_drawing.lua")

        frame._user_print_response_handler = print
        print(f"Starting animation")
        # Animation runs its own loop and won't return until we send a break signal, 
        # so don't await_print here or it will block forever
        await frame.send_lua("require('animated_drawing')", await_print=False)
        await asyncio.sleep(15)  # Let the animation run for a while
        
        print(f"Stopping animation")
        await frame.send_break_signal()

        await frame.disconnect()

    except Exception as e:
        print(f"Not connected to Device: {e}")
        return

if __name__ == "__main__":
    asyncio.run(main())