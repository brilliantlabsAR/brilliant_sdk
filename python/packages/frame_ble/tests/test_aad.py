import asyncio
from frame_ble import FrameBle

async def main():
    b = FrameBle()

    # Connect to the device
    await b.connect(print_response_handler=lambda s: print(s))

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

    print("Waiting for acoustic activity detection...")

    # Keep the connection alive to monitor callback triggers
    try:
        while True:
            await asyncio.sleep(1)  # Wait indefinitely for callback events
    except KeyboardInterrupt:
        print("\nStopping test...")

    # Disconnect from the device
    await b.disconnect()

asyncio.run(main())