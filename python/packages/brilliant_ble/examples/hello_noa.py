"""Draw 'NOA' on the display, using a custom-palette bitmap on Halo and text on Frame."""
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

        # initialize Halo display
        if frame._type == BrilliantDeviceType.HALO:
            await frame.send_lua("frame.display.power_save(false);frame.display.brightness(25);print(0)", await_print=True)

        # Print "Hello, Frame!" on the Frame display
        # wait for a printed string to come back from Frame to ensure the Lua has executed, not just that the command was sent successfully
        if frame._type == BrilliantDeviceType.HALO:
            await frame.send_lua("frame.display.clear();print(0)", await_print=True)
            # 4 colours, darkest to lightest
            cols = [0x000000, 0x61A4EA, 0x72B5F9, 0x9FCBFF, 0xECF3FF]
            for i in range(0, 4):
                await frame.send_lua(f"frame.display.text('NOA', 110, {30-i}, {cols[i+1]});print(0)", await_print=True)

            # website font bitmap
            N = [0b11000110, 0b11100110, 0b11110110, 0b11011110, 0b11001110, 0b11000110]
            O = [0b01111100, 0b11000110, 0b11000110, 0b11000110, 0b11000110, 0b01111100]
            A = [0b01111100, 0b11000110, 0b11000110, 0b11111110, 0b11000110, 0b11000110]

            # concatenate the bitmaps horizontally, with N[0] then A[0] etc, so there are 18 bytes in all
            bitmap = []
            for i in range(6):
                bitmap.append(N[i])
                bitmap.append(O[i])
                bitmap.append(A[i])

            # convert to a string of hex values, e.g. "\xC6\xE6\xF6..."
            bitmap_str = "".join([f"\\x{b:02X}" for b in bitmap])
            print(f"bitmap: {bitmap_str}")
            
            # write cols into a string of hex values, e.g. "\x00\x61\xA4..."
            palette_str = "".join([f"\\x{(c>>16)&0xFF:02X}\\x{(c>>8)&0xFF:02X}\\x{(c>>0)&0xFF:02X}" for c in cols])
            print(f"palette: {palette_str}")

            # send the bitmap to the display (240 wide, x=1+8..256-8 to center horizontally, 60+30 high, y=1+45..256-45 to center vertically, )
            for i in range(0, 4):
                await frame.send_lua(f"frame.display.bitmap(9, {46+40-i*10}, 24, 2, {i}, '{bitmap_str}', {{x_scale=10, y_scale=10, palette_data='{palette_str}'}});print(0)", await_print=True, show_me=True)
            print("'NOA' sent in text and bitmap with a custom palette")
        else:
            await frame.send_lua("frame.display.text('Hello, Frame!', 1, 1);frame.display.show();print(0)", await_print=True)
            print("'Hello, Frame!' sent")
    
        await asyncio.sleep(5)  # Wait for a few seconds to see the message

        if frame._type == BrilliantDeviceType.HALO:
            await frame.send_lua("frame.display.clear();print(0)", await_print=True)
        else:
            await frame.send_lua("frame.display.text(' ', 1, 1);frame.display.show();print(0)", await_print=True)

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())
