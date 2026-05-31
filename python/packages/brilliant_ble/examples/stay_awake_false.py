import asyncio
from brilliant_ble import BrilliantBle
from brilliant_ble import BrilliantDeviceType

async def main():
    frame = BrilliantBle()

    try:
        await frame.connect()

        # stop any application, if running, so we can send lua commands
        await frame.send_break_signal()

        # Restore normal behavior that Frame turns off when placed in the charging cradle (and puts it to sleep now)
        if frame.type == BrilliantDeviceType.FRAME:
            await frame.send_lua("frame.stay_awake(false);print(0)", await_print=True)
            print("Frame will switch off when placed in the charging cradle, and will be put to sleep now (tap to wake)")
        else:
            print("Halo will sleep now")

        await frame.send_lua("frame.sleep()", await_print=False)
        # already disconnected from sleep - don't await frame.disconnect()

    except Exception as e:
        print(f"Not connected to Device: {e}")
        return

if __name__ == "__main__":
    asyncio.run(main())