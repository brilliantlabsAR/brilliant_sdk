import asyncio
from brilliant_ble import FrameBle, BrilliantDeviceType

async def main():
    frame = FrameBle()

    try:
        await frame.connect()

        # initialize the display
        await frame.send_lua("frame.display.power_save(false);print(0)", await_print=True)

        # Print "Hello, Frame/Halo!" on the display
        # wait for a printed string to come back from the device to ensure the Lua has executed, not just that the command was sent successfully
        if frame._type == BrilliantDeviceType.HALO:
            await frame.send_lua("frame.display.clear();print(0)", await_print=True)
            await frame.send_lua("frame.display.text('Hello, Halo!', 50, 50);print(0)", await_print=True)
        else:
            await frame.send_lua("frame.display.text('Hello, Frame!', 1, 1);frame.display.show();print(0)", await_print=True)

        print("'Hello' sent")
        await asyncio.sleep(3)  # Wait for a few seconds to see the message

        await frame.disconnect()

    except Exception as e:
        print(f"Not connected to Device: {e}")
        return

if __name__ == "__main__":
    asyncio.run(main())
