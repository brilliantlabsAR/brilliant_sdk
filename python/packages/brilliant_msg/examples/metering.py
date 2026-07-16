import asyncio
import argparse

from brilliant_msg import BrilliantMsg, TxCode, RxMeteringData
from brilliant_ble import BrilliantDeviceType

async def main():
    """
    Query the metering data on Frame repeatedly and print the changing values to the console
    """
    parser = argparse.ArgumentParser(description="Connect to a Halo/Frame device and run this example.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB" or "Frame 4F"; defaults to the nearest device',
    )
    args = parser.parse_args()
    frame = BrilliantMsg()
    try:
        name = await frame.connect(name=args.name)
        fw = await frame.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
        tag = await frame.send_lua("print(frame.GIT_TAG)", await_print=True)
        batt = await frame.send_lua("print(frame.battery_level())", await_print=True)
        print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

        if frame.type != BrilliantDeviceType.FRAME:
            print("Metering data is a Frame-only feature")
            return

        # debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
        batt_mem = await frame.send_lua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', await_print=True)
        print(f"Battery Level/Memory used: {batt_mem}")

        # Let the user know we're starting
        await frame.print_short_text('Loading...')

        # send the std lua files to Frame that our app needs to handle data accumulation and camera
        await frame.upload_stdlua_libs(lib_names=['data', 'camera', 'code'], minified=False)

        # Send the main lua application from this project to Frame that will run the app
        await frame.upload_frame_app(local_filename="lua/metering_frame_app.lua")

        # attach the print response handler so we can see stdout from Frame Lua print() statements
        # If we assigned this handler before the frameside app was running,
        # any await_print=True commands will echo the acknowledgement byte (e.g. "0" or "1"), but if we assign
        # the handler now we'll see any lua exceptions (or stdout print statements) when the app runs
        frame.attach_print_response_handler()

        # "require" the main frame_app lua file to run it, and block until it has started.
        # It signals that it is ready by sending something on the string response channel.
        await frame.start_frame_app()

        # NOTE: Now that the Frameside app has started there is no need to send snippets of Lua
        # code directly (in fact, we would need to send a break_signal if we wanted to because
        # the main app loop on Frame is running).
        # From this point we do message-passing with first-class types and send_message() (or send_data())

        # hook up the RxMeteringData receiver
        rx_metering_data = RxMeteringData()
        metering_data_queue = await rx_metering_data.attach(frame)

        for i in range(30):
            # send the code to trigger the query for the metering values
            await frame.send_message(0x12, TxCode().pack())

            result = await asyncio.wait_for(metering_data_queue.get(), timeout=10.0)
            print(f"Iteration {i+1}: {result}")

            await asyncio.sleep(1.0)



        # stop the metering data receiver and clean up its resources
        rx_metering_data.detach(frame)

        # unhook the print handler
        frame.detach_print_response_handler()

        # break out of the frame app loop and reboot Frame
        await frame.stop_frame_app()

    except Exception as e:
        print(f"An error occurred: {e}")
    finally:
        # clean disconnection
        await frame.disconnect()

if __name__ == "__main__":
    asyncio.run(main())