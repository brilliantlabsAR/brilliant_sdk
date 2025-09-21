import asyncio
from frame_ble import FrameBle, BrilliantDeviceType

async def main():
    frame = FrameBle()

    try:
        await frame.connect()

        # initialize Halo display
        if frame._type == BrilliantDeviceType.HALO:
            await frame.send_lua("frame.display.power_save(false);frame.display.set_brightness(0);print(0)", await_print=True)

        # Print "Hello, Frame!" on the Frame display
        # wait for a printed string to come back from Frame to ensure the Lua has executed, not just that the command was sent successfully
        if frame._type == BrilliantDeviceType.HALO:
            await frame.send_lua("frame.display.clear();print(0)", await_print=True)
            # 4 colours, darkest to lightest
            cols = [0x61A4EA, 0x72B5F9, 0x9FCBFF, 0xECF3FF]
            for i in range(0, 4):
                await frame.send_lua(f"frame.display.text('NOA', 1, {4-i}, {cols[i]});print(0)", await_print=True)

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

            # send the bitmap to the display 
            for i in range(0, 3):
                await frame.send_lua(f"frame.display.bitmap(1, {64-i*16 + 20}, 24, 2, {i+1}, '{bitmap_str}', {{x_scale=16, y_scale=16}});print(0)", await_print=True)

        else:
            await frame.send_lua("frame.display.text('Hello, Frame!', 1, 1);frame.display.show();print(0)", await_print=True)

        print("'Hello, Frame!' sent")
        await asyncio.sleep(3)  # Wait for a few seconds to see the message

        await frame.disconnect()

    except Exception as e:
        print(f"Not connected to Frame: {e}")
        return

if __name__ == "__main__":
    asyncio.run(main())
