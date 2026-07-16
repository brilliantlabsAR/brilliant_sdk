import asyncio
import argparse

from brilliant_ble import BrilliantBle, BrilliantDeviceType

async def set_palette(f: BrilliantBle, palette_data: bytes):
    """
    Sets the current palette for future bitmap() calls.
    palette_data: string of RGB triplets, e.g. "\x00\x00\x00\xFF\x00\x00\x00\xFF\x00" for black, red, green
    """
    for i in range(0, len(palette_data), 3):
        # take 3 bytes
        chunk = palette_data[i:i+3]
        if len(chunk) == 3:  # only process complete RGB triples
            r, g, b = chunk
            await f.send_lua(f"frame.display.assign_color({i//3},{r},{g},{b})print(0)", await_print=True)
    return 

async def restore_default_palette(frame: BrilliantBle):
    # Set the palette back to the firmware default
    await frame.send_lua(f"frame.display.assign_color_ycbcr(0, 0, 4, 4);print(0)", await_print=True) # VOID
    await frame.send_lua(f"frame.display.assign_color_ycbcr(1, 15, 4, 4);print(0)", await_print=True) # WHITE
    await frame.send_lua(f"frame.display.assign_color_ycbcr(2, 7, 4, 4);print(0)", await_print=True) # GREY
    await frame.send_lua(f"frame.display.assign_color_ycbcr(3, 5, 3, 6);print(0)", await_print=True) # RED
    await frame.send_lua(f"frame.display.assign_color_ycbcr(4, 9, 3, 5);print(0)", await_print=True) # PINK
    await frame.send_lua(f"frame.display.assign_color_ycbcr(5, 2, 2, 5);print(0)", await_print=True) # DARKBROWN
    await frame.send_lua(f"frame.display.assign_color_ycbcr(6, 4, 2, 5);print(0)", await_print=True) # BROWN
    await frame.send_lua(f"frame.display.assign_color_ycbcr(7, 9, 2, 5);print(0)", await_print=True) # ORANGE
    await frame.send_lua(f"frame.display.assign_color_ycbcr(8, 13, 2, 4);print(0)", await_print=True) # YELLOW
    await frame.send_lua(f"frame.display.assign_color_ycbcr(9, 4, 4, 3);print(0)", await_print=True) # DARKGREEN
    await frame.send_lua(f"frame.display.assign_color_ycbcr(10, 6, 2, 3);print(0)", await_print=True) # GREEN
    await frame.send_lua(f"frame.display.assign_color_ycbcr(11, 10, 1, 3);print(0)", await_print=True) # LIGHTGREEN
    await frame.send_lua(f"frame.display.assign_color_ycbcr(12, 1, 5, 2);print(0)", await_print=True) # NIGHTBLUE
    await frame.send_lua(f"frame.display.assign_color_ycbcr(13, 4, 5, 2);print(0)", await_print=True) # SEABLUE
    await frame.send_lua(f"frame.display.assign_color_ycbcr(14, 8, 5, 2);print(0)", await_print=True) # SKYBLUE
    await frame.send_lua(f"frame.display.assign_color_ycbcr(15, 13, 4, 3);print(0)", await_print=True) # CLOUDBLUE
    print("Default palette set.")

async def main():
    """
    Displays images on Halo using the bitmap() function.
    """
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

        if frame._type != BrilliantDeviceType.HALO:
            return print("This script is for Halo only")
            
        # initialize Halo display
        await frame.send_lua("frame.display.power_save(false);frame.display.brightness(25);frame.display.clear();print(0)", await_print=True)

        # debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
        batt_mem = await frame.send_lua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', await_print=True)
        print(f"Battery Level/Memory used: {batt_mem}")

        await frame.send_lua("frame.display.text('Hello, Halo!', 50, 50);print(0)", await_print=True)

        # some quick bitmaps in break/repl mode
        await frame.send_lua("frame.display.bitmap(20, 20, 240, 16, 0, string.rep('\\x10', 4800))print(0)", await_print=True)
        await frame.send_lua("frame.display.bitmap(50, 50, 200, 2, 0, string.rep('\\x77', 2000))print(0)", await_print=True)
        await frame.send_lua("frame.display.bitmap(60, 70, 100, 2, 0, string.rep('\\x55', 100))print(0)", await_print=True)
        await frame.send_lua("frame.display.bitmap(70, 90, 100, 2, 0, string.rep('\\xff\\x00\\xff', 100))print(0)", await_print=True)
        await frame.send_lua("frame.display.bitmap(80, 120, 8, 2, 0, string.rep('\\x55\\xAA', 4), {x_scale=20, y_scale=20})print(0)", await_print=True)

        await asyncio.sleep(2)
        await frame.send_lua("frame.display.clear();print(0)", await_print=True)

        # 24-bit, 1, 2, and 4-bit bitmaps with scaling
        # (RGB bitmaps don't x_scale/y_scale, only indexed bitmaps)
        # red/green/blue squares
        await frame.send_lua("frame.display.bitmap(48, 48, 48, 0, 0, string.rep('\\xFF\\x00\\x00\\xFF\\x00\\x00\\xFF\\x00\\x00', 800))print(0)", await_print=True)
        await frame.send_lua("frame.display.bitmap(96, 48, 48, 0, 0, string.rep('\\x00\\xFF\\x00\\x00\\xFF\\x00\\x00\\xFF\\x00', 800))print(0)", await_print=True)
        await frame.send_lua("frame.display.bitmap(144, 48, 48, 0, 0, string.rep('\\x00\\x00\\xFF\\x00\\x00\\xFF\\x00\\x00\\xFF', 800))print(0)", await_print=True)
        # blue/black rectangles x3 
        await frame.send_lua("frame.display.bitmap(48, 164, 24, 2, 0, string.rep('\\x0F', 3), {palette_data='\\x00\\x00\\x00\\x00\\x00\\xFF', x_scale=8, y_scale=8})print(0)", await_print=True)
        # black/red/green/blue squares x
        await frame.send_lua("frame.display.bitmap(48, 180, 24, 4, 0, string.rep('\\x1B', 6), {palette_data='\\x00\\x00\\x00\\xFF\\x00\\x00\\x00\\xFF\\x00\\x00\\x00\\xFF', x_scale=8, y_scale=8})print(0)", await_print=True)
        # 16-colours, cycling through black/RGB 0..15, x2
        await frame.send_lua("frame.display.bitmap(48, 196, 24, 16, 0, string.rep('\\x01\\x23\\x45\\x67\\x89\\xAB\\xCD\\xEF\\x01\\x23\\x45\\x67', 1), {palette_data='\\x00\\x00\\x00'..string.rep('\\xFF\\x00\\x00\\x00\\xFF\\x00\\x00\\x00\\xFF',5), x_scale=8, y_scale=8})print(0)", await_print=True)
        
        await asyncio.sleep(2)
        await frame.send_lua("frame.display.clear();print(0)", await_print=True)

        # setting global palette first
        # blue/black rectangles x3 
        await set_palette(frame, b"\x00\x00\x00\x00\x00\xFF")
        await frame.send_lua("frame.display.bitmap(48, 64, 24, 2, 0, string.rep('\\x0F', 3), {x_scale=8, y_scale=8})print(0)", await_print=True)
        # black/red/green/blue squares x
        await set_palette(frame, b"\x00\x00\x00\xFF\x00\x00\x00\xFF\x00\x00\x00\xFF")
        await frame.send_lua("frame.display.bitmap(48, 80, 24, 4, 0, string.rep('\\x1B', 6), {x_scale=8, y_scale=8})print(0)", await_print=True)
        # 16-colours, cycling through black/RGB*5 0..15
        await set_palette(frame, b"\x00\x00\x00" + b"\xFF\x00\x00\x00\xFF\x00\x00\x00\xFF"*5)
        await frame.send_lua("frame.display.bitmap(48, 96, 24, 16, 0, string.rep('\\x01\\x23\\x45\\x67\\x89\\xAB\\xCD\\xEF\\x01\\x23\\x45\\x67', 1), {x_scale=8, y_scale=8})print(0)", await_print=True)

        await asyncio.sleep(2)

        # put the original global palette back (16-colours)
        await restore_default_palette(frame)

        await frame.send_lua("frame.display.clear();print(0)", await_print=True)
        await frame.send_lua("frame.display.bitmap(48, 96, 24, 16, 0, string.rep('\\x01\\x23\\x45\\x67\\x89\\xAB\\xCD\\xEF\\x01\\x23\\x45\\x67', 1), {x_scale=8, y_scale=8})print(0)", await_print=True)

        await asyncio.sleep(5)
        await frame.send_lua("frame.display.clear();print(0)", await_print=True)

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        # clean disconnection
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())