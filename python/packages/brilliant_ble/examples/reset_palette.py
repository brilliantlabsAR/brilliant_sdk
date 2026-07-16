"""Restore the device display colour palette to the firmware defaults (Halo or Frame)."""
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
        # stop any application, if running, so we can send lua commands
        frame._user_print_response_handler = None
        await frame.send_break_signal()
        fw = await frame.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
        tag = await frame.send_lua("print(frame.GIT_TAG)", await_print=True)
        batt = await frame.send_lua("print(frame.battery_level())", await_print=True)
        print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

        if frame.type == BrilliantDeviceType.FRAME:
            # Set the palette back to the firmware default
            await frame.send_lua("frame.display.assign_color_ycbcr('VOID', 0, 4, 4);print(0)", await_print=True) # VOID
            await frame.send_lua("frame.display.assign_color_ycbcr('WHITE', 15, 4, 4);print(0)", await_print=True) # WHITE
            await frame.send_lua("frame.display.assign_color_ycbcr('GREY', 7, 4, 4);print(0)", await_print=True) # GREY
            await frame.send_lua("frame.display.assign_color_ycbcr('RED', 5, 3, 6);print(0)", await_print=True) # RED
            await frame.send_lua("frame.display.assign_color_ycbcr('PINK', 9, 3, 5);print(0)", await_print=True) # PINK
            await frame.send_lua("frame.display.assign_color_ycbcr('DARKBROWN', 2, 2, 5);print(0)", await_print=True) # DARKBROWN
            await frame.send_lua("frame.display.assign_color_ycbcr('BROWN', 4, 2, 5);print(0)", await_print=True) # BROWN
            await frame.send_lua("frame.display.assign_color_ycbcr('ORANGE', 9, 2, 5);print(0)", await_print=True) # ORANGE
            await frame.send_lua("frame.display.assign_color_ycbcr('YELLOW', 13, 2, 4);print(0)", await_print=True) # YELLOW
            await frame.send_lua("frame.display.assign_color_ycbcr('DARKGREEN', 4, 4, 3);print(0)", await_print=True) # DARKGREEN
            await frame.send_lua("frame.display.assign_color_ycbcr('GREEN', 6, 2, 3);print(0)", await_print=True) # GREEN
            await frame.send_lua("frame.display.assign_color_ycbcr('LIGHTGREEN', 10, 1, 3);print(0)", await_print=True) # LIGHTGREEN
            await frame.send_lua("frame.display.assign_color_ycbcr('NIGHTBLUE', 1, 5, 2);print(0)", await_print=True) # NIGHTBLUE
            await frame.send_lua("frame.display.assign_color_ycbcr('SEABLUE', 4, 5, 2);print(0)", await_print=True) # SEABLUE
            await frame.send_lua("frame.display.assign_color_ycbcr('SKYBLUE', 8, 5, 2);print(0)", await_print=True) # SKYBLUE
            await frame.send_lua("frame.display.assign_color_ycbcr('CLOUDBLUE', 13, 4, 3);print(0)", await_print=True) # CLOUDBLUE

        else:
            # Set the palette back to the firmware default
            # Halo also supports the color name string, but we can also use index values 0..15
            await frame.send_lua("frame.display.assign_color_ycbcr(0, 0, 4, 4);print(0)", await_print=True) # VOID
            await frame.send_lua("frame.display.assign_color_ycbcr(1, 15, 4, 4);print(0)", await_print=True) # WHITE
            await frame.send_lua("frame.display.assign_color_ycbcr(2, 7, 4, 4);print(0)", await_print=True) # GREY
            await frame.send_lua("frame.display.assign_color_ycbcr(3, 5, 3, 6);print(0)", await_print=True) # RED
            await frame.send_lua("frame.display.assign_color_ycbcr(4, 9, 3, 5);print(0)", await_print=True) # PINK
            await frame.send_lua("frame.display.assign_color_ycbcr(5, 2, 2, 5);print(0)", await_print=True) # DARKBROWN
            await frame.send_lua("frame.display.assign_color_ycbcr(6, 4, 2, 5);print(0)", await_print=True) # BROWN
            await frame.send_lua("frame.display.assign_color_ycbcr(7, 9, 2, 5);print(0)", await_print=True) # ORANGE
            await frame.send_lua("frame.display.assign_color_ycbcr(8, 13, 2, 4);print(0)", await_print=True) # YELLOW
            await frame.send_lua("frame.display.assign_color_ycbcr(9, 4, 4, 3);print(0)", await_print=True) # DARKGREEN
            await frame.send_lua("frame.display.assign_color_ycbcr(10, 6, 2, 3);print(0)", await_print=True) # GREEN
            await frame.send_lua("frame.display.assign_color_ycbcr(11, 10, 1, 3);print(0)", await_print=True) # LIGHTGREEN
            await frame.send_lua("frame.display.assign_color_ycbcr(12, 1, 5, 2);print(0)", await_print=True) # NIGHTBLUE
            await frame.send_lua("frame.display.assign_color_ycbcr(13, 4, 5, 2);print(0)", await_print=True) # SEABLUE
            await frame.send_lua("frame.display.assign_color_ycbcr(14, 8, 5, 2);print(0)", await_print=True) # SKYBLUE
            await frame.send_lua("frame.display.assign_color_ycbcr(15, 13, 4, 3);print(0)", await_print=True) # CLOUDBLUE

        print("Default palette set.")
    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())