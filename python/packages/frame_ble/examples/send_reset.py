import asyncio
from frame_ble import FrameBle

async def main():
    frame = FrameBle()

    try:
        await frame.connect()

        # soft reset the Frame
        await frame.send_reset_signal()
        print("Reset sent")

        await frame.disconnect()

    except Exception as e:
        print(f"Not connected to Device: {e}")
        return

if __name__ == "__main__":
    asyncio.run(main())