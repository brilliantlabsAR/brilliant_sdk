import asyncio
import argparse

from brilliant_msg import BrilliantMsg, RxIMU, TxCode

async def main():
    """
    Subscribe to IMU updates from Frame and print them to the console
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

        # Let the user know we're starting
        await frame.print_short_text('Loading...')

        # debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
        batt_mem = await frame.send_lua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', await_print=True)
        print(f"Battery Level/Memory used: {batt_mem}")

        # send the std lua files to Frame that handle data accumulation, TxCode signalling and IMU sending
        await frame.upload_stdlua_libs(lib_names=['data', 'code', 'imu'])

        # Send the main lua application from this project to Frame that will run the app
        await frame.upload_frame_app(local_filename="lua/imu_frame_app.lua")

        # attach the print response handler so we can see stdout from Frame Lua print() statements
        frame.attach_print_response_handler()

        # "require" the main frame_app lua file to run it, and block until it has started.
        # It signals that it is ready by sending something on the string response channel.
        await frame.start_frame_app()

        # hook up the RxIMU receiver
        rx_imu = RxIMU(smoothing_samples=5)
        imu_queue = await rx_imu.attach(frame)

        # Subscribe for IMU updates
        await frame.send_message(0x40, TxCode(value=1).pack())

        for _ in range(1,100):
            # get the IMU update as soon as it arrives
            imu_update = await asyncio.wait_for(imu_queue.get(), timeout=10.0)
            # note that raw eCompass values will need to be calibrated before use
            print(f"pitch: {imu_update.pitch:.2f} roll: {imu_update.roll:.2f} compass: {imu_update.compass}")

        # Unsubscribe for IMU updates
        await frame.send_message(0x40, TxCode(value=0).pack())

        # stop the IMU listener and clean up its resources
        rx_imu.detach(frame)

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