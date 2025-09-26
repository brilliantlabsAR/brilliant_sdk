import asyncio
from frame_ble import FrameBle, BrilliantDeviceType

async def main():
    frame = FrameBle()

    try:
        await frame.connect()

        # remove any main.lua from Halo
        if (frame._type == BrilliantDeviceType.HALO):
            await frame.send_remove_signal()
            print("Remove sent")
        else:
            print("This script is intended for the Halo device only.")

        await frame.disconnect()

    except Exception as e:
        print(f"Not connected to Frame: {e}")
        return

if __name__ == "__main__":
    asyncio.run(main())