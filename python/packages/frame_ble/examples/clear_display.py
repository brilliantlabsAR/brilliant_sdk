import asyncio
from frame_ble import FrameBle, BrilliantDeviceType

async def main():
    frame = FrameBle()

    try:
        await frame.connect()

        # stop any application, if running, so we can send lua commands
        await frame.send_break_signal()

        # initialize Halo display
        await frame.send_lua("frame.display.power_save(false);print(0)", await_print=True)

        # Clear the display
        if frame._type == BrilliantDeviceType.HALO:
            await frame.send_lua("frame.display.clear();print(0)", await_print=True)
        else:
            await frame.send_lua("frame.display.text('', 1, 1);frame.display.show();print(0)", await_print=True)
        print("Display cleared")

        await frame.disconnect()

    except Exception as e:
        print(f"Not connected to Device: {e}")
        return

if __name__ == "__main__":
    asyncio.run(main())