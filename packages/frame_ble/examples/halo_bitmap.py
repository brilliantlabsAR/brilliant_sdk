import asyncio

from frame_ble import FrameBle, BrilliantDeviceType

async def set_palette(f: FrameBle, palette_data: bytes):
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

async def restore_default_palette(frame: FrameBle):
    # Set the palette back to the firmware default
    # TODO update when Halo uses 1..16 instead of 0..15 and 4,3,3 instead of 10-bits for each channel
    await frame.send_lua(f"frame.display.assign_color_ycbcr(1-1, {0<<6}, {4<<7}, {4<<7});print(0)", await_print=True) # VOID
    await frame.send_lua(f"frame.display.assign_color_ycbcr(2-1, {15<<6}, {4<<7}, {4<<7});print(0)", await_print=True) # WHITE
    await frame.send_lua(f"frame.display.assign_color_ycbcr(3-1, {7<<6}, {4<<7}, {4<<7});print(0)", await_print=True) # GREY
    await frame.send_lua(f"frame.display.assign_color_ycbcr(4-1, {5<<6}, {3<<7}, {6<<7});print(0)", await_print=True) # RED
    await frame.send_lua(f"frame.display.assign_color_ycbcr(5-1, {9<<6}, {3<<7}, {5<<7});print(0)", await_print=True) # PINK
    await frame.send_lua(f"frame.display.assign_color_ycbcr(6-1, {2<<6}, {2<<7}, {5<<7});print(0)", await_print=True) # DARKBROWN
    await frame.send_lua(f"frame.display.assign_color_ycbcr(7-1, {4<<6}, {2<<7}, {5<<7});print(0)", await_print=True) # BROWN
    await frame.send_lua(f"frame.display.assign_color_ycbcr(8-1, {9<<6}, {2<<7}, {5<<7});print(0)", await_print=True) # ORANGE
    await frame.send_lua(f"frame.display.assign_color_ycbcr(9-1, {13<<6}, {2<<7}, {4<<7});print(0)", await_print=True) # YELLOW
    await frame.send_lua(f"frame.display.assign_color_ycbcr(10-1, {4<<6}, {4<<7}, {3<<7});print(0)", await_print=True) # DARKGREEN
    await frame.send_lua(f"frame.display.assign_color_ycbcr(12-1, {10<<6}, {1<<7}, {3<<7});print(0)", await_print=True) # LIGHTGREEN
    await frame.send_lua(f"frame.display.assign_color_ycbcr(13-1, {1<<6}, {5<<7}, {2<<7});print(0)", await_print=True) # NIGHTBLUE
    await frame.send_lua(f"frame.display.assign_color_ycbcr(14-1, {4<<6}, {5<<7}, {2<<7});print(0)", await_print=True) # SEABLUE
    await frame.send_lua(f"frame.display.assign_color_ycbcr(15-1, {8<<6}, {5<<7}, {2<<7});print(0)", await_print=True) # SKYBLUE
    await frame.send_lua(f"frame.display.assign_color_ycbcr(16-1, {13<<6}, {4<<7}, {3<<7});print(0)", await_print=True) # CLOUDBLUE
    print("Default palette set.")

async def main():
    """
    Displays images on Halo using the bitmap() function.
    """
    frame = FrameBle()
    try:
        await frame.connect()

        if frame._type != BrilliantDeviceType.HALO:
            return print("This script is for Halo only")
            
        # initialize Halo display
        await frame.send_lua("frame.display.power_save(false);frame.display.set_brightness(0);frame.display.clear();print(0)", await_print=True)

        # debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
        batt_mem = await frame.send_lua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', await_print=True)
        print(f"Battery Level/Memory used: {batt_mem}")

        await frame.send_lua("frame.display.text('Hello, Halo!', 1, 1)print(0)", await_print=True)

        # some quick bitmaps in break/repl mode
        await frame.send_lua("frame.display.bitmap(20, 20, 320, 16, 0, string.rep('\\x10', 4800))print(0)", await_print=True)
        await frame.send_lua("frame.display.bitmap(50, 50, 232, 2, 0, string.rep('\\x77', 1363))print(0)", await_print=True)
        await frame.send_lua("frame.display.bitmap(60, 70, 100, 2, 0, string.rep('\\x55', 100))print(0)", await_print=True)
        await frame.send_lua("frame.display.bitmap(70, 90, 100, 2, 0, string.rep('\\xff\\x00\\xff', 100))print(0)", await_print=True)
        await frame.send_lua("frame.display.bitmap(80, 120, 8, 2, 0, string.rep('\\x55\\xAA', 4), {x_scale=20, y_scale=20})print(0)", await_print=True)

        await asyncio.sleep(2)
        await frame.send_lua("frame.display.clear();print(0)", await_print=True)

        # 24-bit, 1, 2, and 4-bit bitmaps with scaling
        # TODO RGB bitmaps don't x_scale/y_scale properly yet
        # red/green/blue squares x8
        await frame.send_lua("frame.display.bitmap(48, 48, 24, 0, 0, string.rep('\\xFF\\x00\\x00\\x00\\xFF\\x00\\x00\\x00\\xFF', 8), {x_scale=8, y_scale=8})print(0)", await_print=True)
        # blue/black rectangles x3 
        await frame.send_lua("frame.display.bitmap(48, 64, 24, 2, 0, string.rep('\\x0F', 3), {palette_data='\\x00\\x00\\x00\\x00\\x00\\xFF', x_scale=8, y_scale=8})print(0)", await_print=True)
        # black/red/green/blue squares x
        await frame.send_lua("frame.display.bitmap(48, 80, 24, 4, 0, string.rep('\\x1B', 6), {palette_data='\\x00\\x00\\x00\\xFF\\x00\\x00\\x00\\xFF\\x00\\x00\\x00\\xFF', x_scale=8, y_scale=8})print(0)", await_print=True)
        # 16-colours, cycling through black/RGB 0..15, x2
        await frame.send_lua("frame.display.bitmap(48, 96, 24, 16, 0, string.rep('\\x01\\x23\\x45\\x67\\x89\\xAB\\xCD\\xEF\\x01\\x23\\x45\\x67', 1), {palette_data='\\x00\\x00\\x00'..string.rep('\\xFF\\x00\\x00\\x00\\xFF\\x00\\x00\\x00\\xFF',5), x_scale=8, y_scale=8})print(0)", await_print=True)
        
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

        await frame.send_lua("frame.display.bitmap(48, 96, 24, 16, 0, string.rep('\\x01\\x23\\x45\\x67\\x89\\xAB\\xCD\\xEF\\x01\\x23\\x45\\x67', 1), {x_scale=8, y_scale=8})print(0)", await_print=True)

        await asyncio.sleep(2)

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        # clean disconnection
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())