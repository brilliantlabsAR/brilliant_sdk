import asyncio
import argparse
from brilliant_ble import BrilliantBle


async def main():
    parser = argparse.ArgumentParser(description="Connect to a Halo/Frame device over BLE and run this test.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB" or "Frame 4F"; defaults to the nearest device',
    )
    args = parser.parse_args()
    bluetooth = BrilliantBle()

    name = await bluetooth.connect(
        name=args.name,
        print_response_handler=lambda string: print(f"Print: {string}"),
        data_response_handler=lambda data: print(f"Data: {bytes(data).decode()}"),
    )

    await bluetooth.send_reset_signal()
    fw = await bluetooth.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
    tag = await bluetooth.send_lua("print(frame.GIT_TAG)", await_print=True)
    batt = await bluetooth.send_lua("print(frame.battery_level())", await_print=True)
    print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")
    await bluetooth.send_lua("function ble_event(d)frame.bluetooth.send(d)end")
    await bluetooth.send_lua("frame.bluetooth.receive_callback(ble_event)")
    await bluetooth.send_lua("for i=1,10 do print(i); frame.sleep(1) end")

    await asyncio.sleep(1)
    await bluetooth.send_data(b"hello there")
    await asyncio.sleep(1)
    await bluetooth.send_data(b"hello")
    await asyncio.sleep(10)

    await bluetooth.disconnect()


asyncio.run(main())
