import asyncio
import argparse
from brilliant_ble import BrilliantBle, BrilliantDeviceType

async def main():
    parser = argparse.ArgumentParser(description="Connect to a Halo/Frame device over BLE and run this test.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB" or "Frame 4F"; defaults to the nearest device',
    )
    args = parser.parse_args()
    b = BrilliantBle()

    # Connect to the device
    name = await b.connect(name=args.name, print_response_handler=lambda s: print(s))
    fw = await b.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
    tag = await b.send_lua("print(frame.GIT_TAG)", await_print=True)
    batt = await b.send_lua("print(frame.battery_level())", await_print=True)
    print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

    if b.type != BrilliantDeviceType.HALO:
        print("AAD example is Halo-only")
        await b.disconnect()
        return

    # Register the add callback to print a message when triggered
    # From the aad_callback documentation:
    #
    # /**
    #  * @brief frame.microphone.aad_callback(func, threshold, silent_period)
    #  *
    #  * Register acoustic activity detection callback with optional configuration.
    #  *
    #  * @param func Callback function or nil to clear
    #  * @param threshold Optional threshold in dB SPL (60-100). Defaults to 90 dB if not provided.
    #  *                  Hardware supports: 60, 65, 70, 75, 80, 85, 90, 95, 97.5 dB
    #  * @param silent_period Optional silent period in milliseconds (default: 1000 ms).
    #  *                      Time to wait before next detection after triggering.
    #  *
    #  * Examples:
    #  *   frame.microphone.aad_callback(my_func)           -- Use defaults (90 dB, 1000 ms)
    #  *   frame.microphone.aad_callback(my_func, 75)       -- 75 dB threshold, 1000 ms silent period
    #  *   frame.microphone.aad_callback(my_func, 80, 500)  -- 80 dB threshold, 500 ms silent period
    #  *   frame.microphone.aad_callback(nil)               -- Clear callback
    #  */
    await b.send_lua(
        "frame.microphone.aad_callback(function() print('Acoustic Activity Detected!') end, 60, 2000)"
    )

    print("Waiting for acoustic activity detection... Ctrl+C to stop.")

    # Keep the connection alive to monitor callback triggers
    try:
        while True:
            await asyncio.sleep(1)  # Wait indefinitely for callback events
    except asyncio.CancelledError:
        pass
    finally:
        await b.disconnect()

    # Disconnect from the device
    await b.disconnect()

asyncio.run(main())