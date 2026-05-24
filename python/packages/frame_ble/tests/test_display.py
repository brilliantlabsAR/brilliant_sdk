import asyncio
from frame_ble import FrameBle

async def main():
    b = FrameBle()
    await b.connect(print_response_handler=lambda s: print(s))
    
    
    # --- Brightness test ---
    await b.send_lua("frame.display.show(true)")
    await asyncio.sleep(1.0)

    # --- Basic clear operations ---
    await b.send_lua("frame.display.clear(0x000000)")  # Black
    await asyncio.sleep(0.5)

    await b.send_lua("frame.display.clear(0xFF0000)")  # Red
    await asyncio.sleep(1)
    
    await b.send_lua("frame.display.clear(0x00FF00)")  # Green
    await asyncio.sleep(1)
    
    await b.send_lua("frame.display.clear(0x0000FF)")  # Blue
    await asyncio.sleep(1)

    await b.send_lua("frame.display.clear(0x000000)")  # Clear again before drawing

    # --- Text rendering ---
    await b.send_lua("frame.display.set_font(0)")  # Default font ID 0
    await b.send_lua("frame.display.text('Hello Frame!', 50, 50, 0xFFFFFF)")
    await b.send_lua("frame.display.text('The quick brown fox jumped', 50, 150, 0xFFFFFF)")
    await b.send_lua("frame.display.text('over the lazy dog.', 50, 200, 0xFFFFFF)")

    # Change font and scaling
    await b.send_lua("frame.display.set_font(0, 12, 2)")
    await b.send_lua("frame.display.text('Big Bold!', 30, 100, 0x00FF00)")

    # # --- Get font list from Lua (for debugging or dynamic UI) ---
    # font_list = await b.send_lua("return frame.display.get_font_list()")
    # print("Font List:", font_list)

    # --- Drawing primitives ---
    await b.send_lua("frame.display.set_pixel(10, 10, 0x00FFFF)")  # Cyan pixel

    await b.send_lua("frame.display.line(20, 20, 100, 100, 0xFFFF00)")  # Yellow line

    # Filled and outlined rectangles
    await b.send_lua("frame.display.rect(120, 20, 60, 40, 0xFF00FF, true)")   # Filled magenta rect
    await b.send_lua("frame.display.rect(120, 80, 60, 40, 0xFF00FF, false)")  # Outlined

    # Filled and outlined circles
    await b.send_lua("frame.display.circle(200, 50, 20, 0x00FF00, true)")   # Green filled
    await b.send_lua("frame.display.circle(200, 100, 20, 0x00FF00, false)") # Green outline

    # Polygon (triangle)
    await b.send_lua("frame.display.polygon({160,160, 170,180, 150,180}, 0xFF8800)")

    # Draw individual character (ASCII code for 'A')
    await b.send_lua("frame.display.char(string.byte('A'), 50, 200, 0xFFFFFF)")

    for brightness in [0, 25, 50, 75, 100]:
        await b.send_lua(f"frame.display.brightness({brightness})")
        await asyncio.sleep(0.5)

    # --- Power saving test ---
    await b.send_lua("frame.display.power_save(true)")
    await asyncio.sleep(5.0)

    await b.send_lua("frame.display.power_save(false)")
    await b.send_lua("frame.display.show(true)")
    await asyncio.sleep(1.0)

    # Disconnect Bluetooth
    await b.disconnect()

asyncio.run(main())
