import asyncio
import argparse
from brilliant_ble import BrilliantBle, BrilliantDeviceType

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
        print("Display example is Halo-only")
        await b.disconnect()
        return

    
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
    await b.send_lua("frame.display.text('Hello Halo!', 50, 50, 0xFFFFFF)")
    await b.send_lua("frame.display.text('The quick brown fox jumped', 50, 150, 0xFFFFFF)")
    await b.send_lua("frame.display.text('over the lazy dog.', 50, 200, 0xFFFFFF)")

    # Change font and scaling
    await b.send_lua("frame.display.set_font(0, 12, 2)")
    await b.send_lua("frame.display.text('Big Bold!', 30, 100, 0x00FF00)")

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
    await asyncio.sleep(1.0)

    # Disconnect Bluetooth
    await b.disconnect()

asyncio.run(main())
