import asyncio
from frame_ble import FrameBle, BrilliantDeviceType

async def main():
    frame = FrameBle()

    try:
        await frame.connect()

        if frame.type == BrilliantDeviceType.FRAME:
            # stop any application, if running, so we can send lua commands
            await frame.send_break_signal()

            # Set the palette back to the firmware default
            await frame.send_lua("frame.display.assign_color_ycbcr(1, 0, 4, 4);print(0)", await_print=True) # VOID
            await frame.send_lua("frame.display.assign_color_ycbcr(2, 15, 4, 4);print(0)", await_print=True) # WHITE
            await frame.send_lua("frame.display.assign_color_ycbcr(3, 7, 4, 4);print(0)", await_print=True) # GREY
            await frame.send_lua("frame.display.assign_color_ycbcr(4, 5, 3, 6);print(0)", await_print=True) # RED
            await frame.send_lua("frame.display.assign_color_ycbcr(5, 9, 3, 5);print(0)", await_print=True) # PINK
            await frame.send_lua("frame.display.assign_color_ycbcr(6, 2, 2, 5);print(0)", await_print=True) # DARKBROWN
            await frame.send_lua("frame.display.assign_color_ycbcr(7, 4, 2, 5);print(0)", await_print=True) # BROWN
            await frame.send_lua("frame.display.assign_color_ycbcr(8, 9, 2, 5);print(0)", await_print=True) # ORANGE
            await frame.send_lua("frame.display.assign_color_ycbcr(9, 13, 2, 4);print(0)", await_print=True) # YELLOW
            await frame.send_lua("frame.display.assign_color_ycbcr(10, 4, 4, 3);print(0)", await_print=True) # DARKGREEN
            await frame.send_lua("frame.display.assign_color_ycbcr(11, 6, 2, 3);print(0)", await_print=True) # GREEN
            await frame.send_lua("frame.display.assign_color_ycbcr(12, 10, 1, 3);print(0)", await_print=True) # LIGHTGREEN
            await frame.send_lua("frame.display.assign_color_ycbcr(13, 1, 5, 2);print(0)", await_print=True) # NIGHTBLUE
            await frame.send_lua("frame.display.assign_color_ycbcr(14, 4, 5, 2);print(0)", await_print=True) # SEABLUE
            await frame.send_lua("frame.display.assign_color_ycbcr(15, 8, 5, 2);print(0)", await_print=True) # SKYBLUE
            await frame.send_lua("frame.display.assign_color_ycbcr(16, 13, 4, 3);print(0)", await_print=True) # CLOUDBLUE
            print("Default palette set.")

            #await frame.send_lua("frame.display.text('Hello, World!', 50, 100, {color='ORANGE'});frame.display.show();print(0)", await_print=True)
        else:
            print("This script is intended for the Frame device only.")

        await frame.disconnect()

    except Exception as e:
        print(f"Not connected to Frame: {e}")
        return

if __name__ == "__main__":
    asyncio.run(main())