import asyncio
import argparse
import time
from aioconsole import ainput
from brilliant_ble import BrilliantBle

total_data_received = 0
last_data_time = time.time()


def receive_data(data):
    global total_data_received
    global last_data_time
    total_data_received += len(data)

    if len(data) == 1:
        throughput = total_data_received / (time.time() - last_data_time)
        last_data_time = time.time()
        total_data_received = 0
        print(f"Throughput: {throughput/1000:.2f} KB/s")


async def main():
    parser = argparse.ArgumentParser(description="Connect to a Halo/Frame device over BLE and run this test.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB" or "Frame 4F"; defaults to the nearest device',
    )
    args = parser.parse_args()

    lua_script = """
    data = string.rep('a',frame.bluetooth.max_length())
    
    while true do
        for i = 1, 100 do frame.bluetooth.send(data) end
        frame.bluetooth.send('X')
    end
    """

    b = BrilliantBle()

    name = await b.connect(name=args.name, data_response_handler=receive_data)

    await b.send_break_signal()
    fw = await b.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
    tag = await b.send_lua("print(frame.GIT_TAG)", await_print=True)
    batt = await b.send_lua("print(frame.battery_level())", await_print=True)
    print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")
    await b.upload_file_from_string(lua_script, "test.lua")
    # why do we need to sleep to make sure the upload gets its reply?
    # Maybe the future from the send_lua() await_print misses getting completed
    # if some other data is moving?
    await asyncio.sleep(5.0)

    print("Testing throughput: Press Enter to quit")
    await b.send_lua("require('test')")

    # Wait until a keypress
    await ainput("")

    await b.send_break_signal()
    await b.send_lua("frame.file.remove('test.lua');print(0)", await_print=True)
    await b.disconnect()

if __name__ == "__main__":
    asyncio.run(main())