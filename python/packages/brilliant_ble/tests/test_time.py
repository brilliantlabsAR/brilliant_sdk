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
    b = BrilliantBle()
    name = await b.connect(name=args.name, print_response_handler=lambda s: print(s))
    fw = await b.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
    tag = await b.send_lua("print(frame.GIT_TAG)", await_print=True)
    batt = await b.send_lua("print(frame.battery_level())", await_print=True)
    print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

    print("print(frame.time.utc())")
    await b.send_lua("print(frame.time.utc())")
    await asyncio.sleep(1.0)

    print("print(frame.time.utc(100))")
    await b.send_lua("print(frame.time.utc(100))")   
    await asyncio.sleep(5.0)

    print("print(frame.time.utc())")
    await b.send_lua("print(frame.time.utc())")
    await asyncio.sleep(1.0)

    print("print(frame.time.zone('+04:30'))")
    await b.send_lua("print(frame.time.zone('+04:30'))")
    await asyncio.sleep(1.0)

    print("print(frame.time.zone())")
    await b.send_lua("print(frame.time.zone())")
    await asyncio.sleep(1.0)

    print("print(frame.time.zone('+3:30'))")
    await b.send_lua("print(frame.time.zone('+3:30'))")
    await asyncio.sleep(1.0)

    print("print(frame.time.zone())")
    await b.send_lua("print(frame.time.zone())")
    await asyncio.sleep(1.0)

    print("print(frame.time.zone('5:30'))")
    await b.send_lua("print(frame.time.zone('5:30'))")
    await asyncio.sleep(1.0)

    print("print(frame.time.zone())")
    await b.send_lua("print(frame.time.zone())")
    await asyncio.sleep(1.0)

    print("print(frame.time.zone('-7:30'))")
    await b.send_lua("print(frame.time.zone('-7:30'))")
    await asyncio.sleep(1.0)

    print("print(frame.time.zone())")
    await b.send_lua("print(frame.time.zone())")
    await asyncio.sleep(1.0)

    print("print(frame.time.utc(1708551112))")
    await b.send_lua("print(frame.time.utc(1708551112))")   
    await asyncio.sleep(1.0)

    print("print(frame.time.date())")
    await b.send_lua("print(frame.time.date()['year'])")
    await b.send_lua("print(frame.time.date()['month'])")
    await b.send_lua("print(frame.time.date()['day'])")

    await b.send_lua("print(frame.time.date()['hour'])")
    await b.send_lua("print(frame.time.date()['minute'])")
    await b.send_lua("print(frame.time.date()['second'])")

    await b.send_lua("print(frame.time.date()['weekday'])")
    await b.send_lua("print(frame.time.date()['day of year'])")
    await b.send_lua("print(frame.time.date()['is daylight saving'])")
    await asyncio.sleep(1.0)

    print("print(frame.time.utc())")
    await b.send_lua("print(frame.time.utc())")
    await asyncio.sleep(1.0)

    print("print(frame.time.utc(0))")
    await b.send_lua("print(frame.time.utc(0))")
    await asyncio.sleep(1.0)

    print("frame.time.utc() increments during frame.sleep()")
    await b.send_lua("print(frame.time.utc())", await_print=True)
    await b.send_lua("frame.sleep(5)print('5 second sleep completed')", await_print=True, timeout=10)
    await b.send_lua("print(frame.time.utc())", await_print=True)
    await asyncio.sleep(1.0)

    from datetime import datetime
    print("print(frame.time.utc()) 10 times in a tight loop")
    for i in range(10):
        print(f'Host time: {datetime.now()}')
        await b.send_lua(f"print(frame.time.utc())", await_print=True)


    # Disconnect Bluetooth
    await b.disconnect()

asyncio.run(main())
