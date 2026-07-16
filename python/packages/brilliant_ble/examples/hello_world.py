"""Print 'Hello' on the device display (Halo or Frame)."""
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

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())
