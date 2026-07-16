import asyncio
import argparse
from brilliant_ble import BrilliantBle, BrilliantDeviceType

async def set_standard_palette(b: BrilliantBle):
    
    frame_standard_palette = [
        0, 0, 0,          # 0: VOID 
        255, 255, 255,    # 1: WHITE 
        128, 128, 128,    # 2: GREY 
        255, 0, 0,        # 3: RED 
        255, 192, 203,    # 4: PINK
        101, 67, 33,      # 5: DARKBROWN
        150, 75, 0,       # 6: BROWN 
        255, 165, 0,      # 7: ORANGE 
        255, 255, 0,      # 8: YELLOW 
        0, 100, 0,        # 9: DARKGREEN
        0, 255, 0,        # 10: GREEN
        144, 238, 144,    # 11: LIGHTGREEN 
        25, 25, 112,      # 12: NIGHTBLUE
        0, 0, 205,        # 13: SEABLUE
        135, 206, 235,    # 14: SKYBLUE
        240, 248, 255     # 15: CLOUDBLUE 
    ]
    
    for i in range(16):
        start_index = i * 3
        r = frame_standard_palette[start_index]
        g = frame_standard_palette[start_index + 1]
        b_val = frame_standard_palette[start_index + 2]
        
        lua_command = f"frame.display.assign_color({i}, {r}, {g}, {b_val});print(0)"
        await b.send_lua(lua_command, await_print=True)
    

async def draw_palette_swatch(b: BrilliantBle, start_x=20, start_y=20):
    cols = 4  
    rows = 4 
    for row in range(rows):
        for col in range(cols):
            x = start_x + col * 60
            y = start_y + row * 60
            palette_index = row * cols + col
            lua_command = f"frame.display.bitmap({x}, {y}, 32, 4, {palette_index}, string.rep('\\xFF', 256));print(0)"
            await b.send_lua(lua_command, await_print=True)

async def full_display_palette(b: BrilliantBle):
    for palette_index in range(16):
        lua_command = f"frame.display.bitmap(0, 0, 320, 4, {palette_index}, string.rep('\\xFF', 320*240/2));print(0)"
        await b.send_lua(lua_command, await_print=True)

async def main():
    parser = argparse.ArgumentParser(description="Connect to a Halo/Frame device over BLE and run this test.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB" or "Frame 4F"; defaults to the nearest device',
    )
    args = parser.parse_args()
    b = BrilliantBle()
    name = await b.connect(name=args.name, print_response_handler=lambda s: print(s))
    fw = await b.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
    tag = await b.send_lua("print(frame.GIT_TAG)", await_print=True)
    batt = await b.send_lua("print(frame.battery_level())", await_print=True)
    print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

    if b.type != BrilliantDeviceType.HALO:
        print("Display bitmap example is Halo-only")
        await b.disconnect()
        return

    print("Clear and set up display")
    await b.send_lua("frame.display.power_save(false);print(0)", await_print=True)
    await b.send_lua("frame.display.brightness(50);print(0)", await_print=True)
    await b.send_lua("frame.display.clear(0xFF00FF);print(0)", await_print=True)  # Purple
    await asyncio.sleep(1)
    await b.send_lua("frame.display.clear();print(0)", await_print=True)  # Black

    print("Setting display palette")
    await set_standard_palette(b)

    print("Drawing palette swatch")
    await draw_palette_swatch(b)
    await asyncio.sleep(5)

    print("Drawing large palette")
    await full_display_palette(b)
    await asyncio.sleep(5)

    # When color_format is 0, data is full rgb
    print("Draw full RGB")
    await b.send_lua("frame.display.clear();print(0)", await_print=True)  # Black
    await b.send_lua("frame.display.bitmap(40, 40, 100, 0, 0, string.rep('\\xff\\xff\\xff', 100*100));print(0)", await_print=True) 
    await asyncio.sleep(5)

    # # When color_format is 2, data is the global palette index, Test black and white stripes
    print("Draw 2-color")
    await b.send_lua("frame.display.clear();print(0)", await_print=True)  # Black
    await b.send_lua("frame.display.bitmap(0, 0, 320, 2, 0, string.rep('\\x00\\x00\\x00\\x00\\xff\\xff\\xff\\xff', 320/8*240/8));print(0)", await_print=True)
    await asyncio.sleep(5)

    # When color_format is 4, test 4 colored vertical stripes
    print("Draw 4-color")
    await b.send_lua("frame.display.clear();print(0)", await_print=True)  # Black
    width = 320
    hight = 240
    byte_color = 4  # The number of colors contained in each byte(8/2)
    test_color_num = 4 # Test shows four colors
    rows = int(width/byte_color/test_color_num)
    data1 = '\\x00' * rows
    data2 = '\\x55' * rows
    data3 = '\\xaa' * rows
    data4 = '\\xff' * rows
    data = data1 + data2 + data3 + data4
    count = int((width / byte_color) * (hight / rows / test_color_num))
    lua_command = f"frame.display.bitmap(0, 0, {width}, 4, 7, string.rep('{data}', {count}));print(0)"
    await b.send_lua(lua_command, await_print=True)
    await asyncio.sleep(5)

    # When color_format is 16, test 16 colored horizontal stripes
    print("Draw 16-color")
    await b.send_lua("frame.display.clear();print(0)", await_print=True)  # Black
    width = 320
    hight = 240
    byte_color = 2  # The number of colors contained in each byte(8/4)
    test_color_num = 16 # Test shows four colors
    data_list = ['\\x00', '\\x11', '\\x22', '\\x33',
                 '\\x44', '\\x55', '\\x66', '\\x77',
                 '\\x88', '\\x99', '\\xaa', '\\xbb',
                 '\\xcc', '\\xdd', '\\xee', '\\xff',
    ]
    line = int(hight/test_color_num)
    rows = int(width/byte_color*line)
    for i in range(0, 16):
        data = data_list[i]
        lua_command = f"frame.display.bitmap(0, {i*line}, {width}, 16, 0, string.rep('{data}', {rows}));print(0)"
        await b.send_lua(lua_command, await_print=True)
    await asyncio.sleep(5)

    # Use custom color palette, example:  displays 80x80 blue square
    print("Custom palette with bitmap - blue square - 2-color palette")
    await b.send_lua("frame.display.clear();print(0)", await_print=True)  # Black
    params = "{ \
                palette_data = \"\\xFF\\x00\\x00\\x00\\x00\\xFF\", \
                x_scale = 1,     \
                y_scale = 1,    \
            }"
    lua_command = f"frame.display.bitmap(40, 40, 80, 2, 0, string.rep('\\xff', 80/8 * 80), {params});print(0)"
    await b.send_lua(lua_command, await_print=True)
    await asyncio.sleep(5)

    # Test x_scale and y_scale, example:  displays 160x160 green square
    print("X-scale and Y-scale of 160px green square, 2-color palette")
    await b.send_lua("frame.display.clear();print(0)", await_print=True)  # Black
    params = "{ \
                palette_data = \"\\xFF\\x00\\x00\\x00\\xFF\\x00\", \
                x_scale = 20,     \
                y_scale = 20,    \
            }"
    lua_command = f"frame.display.bitmap(40, 40, 8, 2, 0, string.rep('\\xff', 8/8 * 8), {params});print(0)"
    await b.send_lua(lua_command, await_print=True)
    await asyncio.sleep(5)

    # Test x_scale and y_scale, example:  displays 4x80px squares
    print("X-scale and Y-scale of 4x80px squares, 4-color palette (white, red, green, blue)")
    await b.send_lua("frame.display.clear();print(0)", await_print=True)  # Black
    params = "{ \
                palette_data = \"\\xFF\\xFF\\xFF\\xFF\\x00\\x00\\x00\\xFF\\x00\\x00\\x00\\xFF\", \
                x_scale = 80,     \
                y_scale = 80,    \
            }"
    lua_command = f"frame.display.bitmap(1, 1, 4, 4, 0, string.rep('\\x1B', 1), {params});print(0)"
    await b.send_lua(lua_command, await_print=True)
    await asyncio.sleep(5)

    # Test x_scale and y_scale, example:  displays 16x20px rectangles
    print("X-scale and Y-scale of 16x20px rectangles, 16-color palette (standard palette provided as custom palette)")
    await b.send_lua("frame.display.clear();print(0)", await_print=True)  # Black
    params = "{\
                palette_data = \"\\x00\\x00\\x00\\xFF\\xFF\\xFF\\x80\\x80\\x80\\xFF\\x00\\x00\\xFF\\xC0\\xCB\\x65\\x43\\x21\\x96\\x4B\\x00\\xFF\\xA5\\x00\\xFF\\xFF\\x00\\x00\\x64\\x00\\x00\\xFF\\x00\\x90\\xEE\\x90\\x19\\x19\\x70\\x00\\x00\\xCD\\x87\\xCE\\xEB\\xF0\\xF8\\xFF\",\
                x_scale = 20,\
                y_scale = 240,\
            }"
    lua_command = f"frame.display.bitmap(1, 1, 16, 16, 0, '\\x01\\x23\\x45\\x67\\x89\\xAB\\xCD\\xEF', {params});print(0)"
    await b.send_lua(lua_command, await_print=True)
    await asyncio.sleep(20)

    await b.send_lua("frame.display.clear();print(0)", await_print=True)  # Black
    await b.send_lua("frame.display.power_save(true);print(0)", await_print=True)

    # Disconnect Bluetooth
    await b.disconnect()

asyncio.run(main())
