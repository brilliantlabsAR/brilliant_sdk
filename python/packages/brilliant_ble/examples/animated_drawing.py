"""Halo-only: upload and run a small animated drawing Lua app on the display."""
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
        name = await frame.connect(name=args.name)
        fw = await frame.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
        tag = await frame.send_lua("print(frame.GIT_TAG)", await_print=True)
        batt = await frame.send_lua("print(frame.battery_level())", await_print=True)
        print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

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

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())