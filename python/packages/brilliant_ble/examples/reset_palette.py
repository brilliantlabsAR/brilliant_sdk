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
        tag = await frame.send_lua("print(frame.GIT_TAG == '' and 'untagged' or frame.GIT_TAG)", await_print=True)
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
            # Set the palette back to the firmware default (Halo stores the
            # palette as RGB since 0.8.8; these are the firmware's defaults).
            # Halo also supports the color name string, but we can also use index values 0..15
            await frame.send_lua("frame.display.assign_color(0, 0, 0, 0);print(0)", await_print=True) # VOID
            await frame.send_lua("frame.display.assign_color(1, 255, 255, 255);print(0)", await_print=True) # WHITE
            await frame.send_lua("frame.display.assign_color(2, 128, 128, 128);print(0)", await_print=True) # GREY
            await frame.send_lua("frame.display.assign_color(3, 255, 0, 0);print(0)", await_print=True) # RED
            await frame.send_lua("frame.display.assign_color(4, 255, 192, 203);print(0)", await_print=True) # PINK
            await frame.send_lua("frame.display.assign_color(5, 101, 67, 33);print(0)", await_print=True) # DARKBROWN
            await frame.send_lua("frame.display.assign_color(6, 150, 75, 0);print(0)", await_print=True) # BROWN
            await frame.send_lua("frame.display.assign_color(7, 255, 165, 0);print(0)", await_print=True) # ORANGE
            await frame.send_lua("frame.display.assign_color(8, 255, 255, 0);print(0)", await_print=True) # YELLOW
            await frame.send_lua("frame.display.assign_color(9, 0, 100, 0);print(0)", await_print=True) # DARKGREEN
            await frame.send_lua("frame.display.assign_color(10, 0, 255, 0);print(0)", await_print=True) # GREEN
            await frame.send_lua("frame.display.assign_color(11, 144, 238, 144);print(0)", await_print=True) # LIGHTGREEN
            await frame.send_lua("frame.display.assign_color(12, 25, 25, 112);print(0)", await_print=True) # NIGHTBLUE
            await frame.send_lua("frame.display.assign_color(13, 0, 0, 205);print(0)", await_print=True) # SEABLUE
            await frame.send_lua("frame.display.assign_color(14, 135, 206, 235);print(0)", await_print=True) # SKYBLUE
            await frame.send_lua("frame.display.assign_color(15, 240, 248, 255);print(0)", await_print=True) # CLOUDBLUE

        print("Default palette set.")
    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())