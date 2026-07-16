"""Keep the device awake even in the charging cradle (useful during development)."""
import asyncio
import argparse
from brilliant_ble import BrilliantBle
from brilliant_ble import BrilliantDeviceType

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

        # stop any application, if running, so we can send lua commands
        await frame.send_break_signal()
        fw = await frame.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
        tag = await frame.send_lua("print(frame.GIT_TAG)", await_print=True)
        batt = await frame.send_lua("print(frame.battery_level())", await_print=True)
        print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

        # Keep Frame awake even in charging cradle (for development)
        await frame.send_lua("frame.stay_awake(true);print(0)", await_print=True)
        if frame.type != BrilliantDeviceType.HALO:
            print("Frame will stay awake - even in the charging cradle - until frame.send_lua('frame.stay_awake(false)')")
        else:
            print("Halo will stay awake")

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())