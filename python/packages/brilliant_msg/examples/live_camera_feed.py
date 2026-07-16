import asyncio
import argparse
from PIL import Image
import io
import cv2
import numpy as np

from brilliant_msg import BrilliantMsg, RxPhoto, TxCaptureSettings
from brilliant_ble import BrilliantDeviceType

async def main():
    """
    Take photos continuously using the Frame camera and display them in an OpenCV window
    """
    parser = argparse.ArgumentParser(description="Connect to a Halo/Frame device and run this example.")
    parser.add_argument(
        "--name",
        default=None,
        help='exact BLE device name, e.g. "Halo AB" or "Frame 4F"; defaults to the nearest device',
    )
    args = parser.parse_args()
    frame = None
    rx_photo = None
    window_name = "Camera Feed"
    
    try:
        # Initialize OpenCV Window on Main Thread
        cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
        
        frame = BrilliantMsg()
        name = await frame.connect(name=args.name)
        fw = await frame.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
        tag = await frame.send_lua("print(frame.GIT_TAG)", await_print=True)
        batt = await frame.send_lua("print(frame.battery_level())", await_print=True)
        print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

        # debug only: check our current battery level and memory usage
        batt_mem = await frame.send_lua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', await_print=True)
        print(f"Battery Level/Memory used: {batt_mem}")

        # Let the user know we're starting
        await frame.print_short_text('Loading...')

        # send the std lua files to Frame
        await frame.upload_stdlua_libs(lib_names=['data', 'camera'])

        # Send the main lua application
        await frame.upload_frame_app(local_filename="lua/camera_frame_app.lua")

        frame.attach_print_response_handler()

        # Start the frame app
        await frame.start_frame_app()

        # hook up the RxPhoto receiver
        rx_photo = RxPhoto(upright=frame.ble.type == BrilliantDeviceType.FRAME)
        photo_queue = await rx_photo.attach(frame)

        if frame.ble.type == BrilliantDeviceType.FRAME:
            # give the frame some time for the autoexposure loop to run
            print("Letting autoexposure loop run for 5 seconds to settle")
            
            # We process the UI loop during the sleep to prevent "spinning wheel"
            for _ in range(50):
                await asyncio.sleep(0.1)
                cv2.waitKey(1)

        print("Starting continuous capture - Ctrl+C to stop")

        # Main capture loop
        capture_count = 0
        while True:
            # Check if window was closed via 'X' button
            if cv2.getWindowProperty(window_name, cv2.WND_PROP_VISIBLE) < 1:
                print("Window closed, exiting...")
                break

            # Request a photo
            resolution: int = 720 if frame.ble.type == BrilliantDeviceType.FRAME else 640
            await frame.send_message(0x0d, TxCaptureSettings(resolution=resolution).pack())
            
            try:
                # Wait for image with short timeout to keep UI responsive
                # If the image takes > 0.1s, we catch TimeoutError, update UI, and wait again
                jpeg_bytes = await asyncio.wait_for(photo_queue.get(), timeout=0.1)
                
                # Convert PIL Image to OpenCV format
                pil_image = Image.open(io.BytesIO(jpeg_bytes))
                cv_image = np.array(pil_image)
                
                # Convert RGB to BGR (OpenCV uses BGR)
                if cv_image.shape[2] == 3:
                    cv_image = cv2.cvtColor(cv_image, cv2.COLOR_RGB2BGR)
                
                # Display image
                cv2.imshow(window_name, cv_image)
                
                capture_count += 1
                print(f"Captured frame {capture_count}", end="\r")

            except asyncio.TimeoutError:
                # No frame arrived yet, just continue to keep UI alive
                pass
            
            # Pump OpenCV events (Required for Mac GUI)
            # waitKey(1) blocks for 1ms. 
            key = cv2.waitKey(1) & 0xFF
            if key == 27:  # ESC key
                break
            
            # Small yield to let other async tasks run
            await asyncio.sleep(0.01)
            
    except asyncio.CancelledError:
        print("\nCapture loop cancelled")
    except Exception as e:
        print(f"\nAn error occurred: {e}")
    finally:
        # Clean up resources
        print("\nCleaning up resources...")
        cv2.destroyAllWindows()
        if rx_photo and frame:
            rx_photo.detach(frame)
        if frame:
            frame.detach_print_response_handler()
            await frame.stop_frame_app()
            await frame.disconnect()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nProgram interrupted by user")