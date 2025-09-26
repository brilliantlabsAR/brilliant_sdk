import asyncio
from frame_ble import FrameBle

async def main():
    b = FrameBle()

    # Connect to the device
    await b.connect(print_response_handler=lambda s: print(s))

    # Register the add callback to print a message when triggered
    await b.send_lua(
        "frame.microphone.aad_callback(function() print('Acoustic Activity Detected!') end)"
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