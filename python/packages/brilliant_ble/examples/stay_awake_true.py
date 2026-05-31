import asyncio
from brilliant_ble import BrilliantBle
from brilliant_ble import BrilliantDeviceType

async def main():
    frame = BrilliantBle()

    try:
        await frame.connect()

        # stop any application, if running, so we can send lua commands
        await frame.send_break_signal()

        # Keep Frame awake even in charging cradle (for development)
        await frame.send_lua("frame.stay_awake(true);print(0)", await_print=True)
        if frame.type != BrilliantDeviceType.HALO:
            print("Frame will stay awake - even in the charging cradle - until frame.send_lua('frame.stay_awake(false)')")
        else:
            print("Halo will stay awake")

        await frame.disconnect()

    except Exception as e:
        print(f"Not connected to Device: {e}")
        return

if __name__ == "__main__":
    asyncio.run(main())