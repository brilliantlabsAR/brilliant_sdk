import asyncio
import argparse
from PIL import Image
import io
import cv2
import numpy as np
import threading
import queue

from brilliant_msg import BrilliantMsg, RxPhoto, RxAutoExpResult, TxCaptureSettings, TxAutoExpSettings, TxManualExpSettings
from brilliant_ble import BrilliantDeviceType

class CameraDisplay:
    def __init__(self, window_name="Live Camera Feed"):
        self.window_name = window_name
        self.image_queue = queue.Queue(maxsize=1)
        self.autoexp_queue = queue.Queue(maxsize=1)
        self.running = True
        self.latest_autoexp = None
        self.last_image = None

    def stop(self):
        self.running = False

    def update_image(self, jpeg_bytes):
        try:
            # Replace old image with new one
            if self.image_queue.full():
                try:
                    self.image_queue.get_nowait()
                except queue.Empty:
                    pass
            self.image_queue.put_nowait(jpeg_bytes)
        except queue.Full:
            pass  # Skip frame if queue is full

    def update_autoexp(self, autoexp_data):
        try:
            # Replace old data with new one
            if self.autoexp_queue.full():
                try:
                    self.autoexp_queue.get_nowait()
                except queue.Empty:
                    pass
            self.autoexp_queue.put_nowait(autoexp_data)
        except queue.Full:
            pass  # Skip data if queue is full

    def create_params_display(self, autoexp_data, width):
        # Create a blank image for parameters display
        params_height = 230  # Height of the parameters panel
        params_img = np.zeros((params_height, width, 3), dtype=np.uint8)

        # Background color - dark gray
        params_img[:, :] = (25, 25, 25)

        # Display parameters as text
        font = cv2.FONT_HERSHEY_SIMPLEX
        font_scale = 0.5
        color = (255, 255, 255)  # White text
        thickness = 1
        line_spacing = 25

        # Format and display the exposure parameters
        lines = [
            f"Shutter: {int(autoexp_data['shutter'])}",
            f"Analog Gain: {int(autoexp_data['analog_gain'])}",
            f"RGB Gains: R:{autoexp_data['red_gain']:.2f} G:{autoexp_data['green_gain']:.2f} B:{autoexp_data['blue_gain']:.2f}",
            f"Error: {autoexp_data['error']:.4f}",
            f"Brightness (Center Weighted): {autoexp_data['brightness']['center_weighted_average']:.2f}",
            f"Brightness (Scene): {autoexp_data['brightness']['scene']:.2f}"
        ]

        # Add matrix and spot brightness values
        matrix = autoexp_data['brightness']['matrix']
        spot = autoexp_data['brightness']['spot']

        lines.extend([
            f"Matrix Brightness: R:{matrix['r']:.2f} G:{matrix['g']:.2f} B:{matrix['b']:.2f} Avg:{matrix['average']:.2f}",
            f"Spot Brightness: R:{spot['r']:.2f} G:{spot['g']:.2f} B:{spot['b']:.2f} Avg:{spot['average']:.2f}"
        ])

        # Draw each line of text
        y_pos = 30
        for line in lines:
            cv2.putText(params_img, line, (20, y_pos), font, font_scale, color, thickness)
            y_pos += line_spacing

        return params_img

    def run(self):
        cv2.namedWindow(self.window_name, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(self.window_name, 720, 950)  # Adjust initial window size

        while self.running:
            try:
                # Check for new auto-exposure data first
                got_new_autoexp = False
                try:
                    self.latest_autoexp = self.autoexp_queue.get_nowait()
                    got_new_autoexp = True
                except queue.Empty:
                    pass

                # Check if there's a new image
                got_new_image = False
                try:
                    jpeg_bytes = self.image_queue.get(timeout=0.1)

                    # Convert PIL Image to OpenCV format
                    pil_image = Image.open(io.BytesIO(jpeg_bytes))
                    cv_image = np.array(pil_image)

                    # Convert RGB to BGR (OpenCV uses BGR)
                    if cv_image.shape[2] == 3:  # If it has 3 channels
                        cv_image = cv2.cvtColor(cv_image, cv2.COLOR_RGB2BGR)

                    # Store this image for future auto-exposure updates
                    self.last_image = cv_image.copy()
                    got_new_image = True

                    # Create combined display if we have auto-exposure data
                    if self.latest_autoexp:
                        params_display = self.create_params_display(self.latest_autoexp, cv_image.shape[1])
                        # Stack parameters display above the image
                        combined_image = np.vstack([params_display, cv_image])
                        # Display combined image
                        cv2.imshow(self.window_name, combined_image)
                    else:
                        # Display just the image if no auto-exposure data yet
                        cv2.imshow(self.window_name, cv_image)

                except queue.Empty:
                    pass

                # Update display if we have either new image or new auto-exposure data
                if (got_new_image or got_new_autoexp) and self.latest_autoexp is not None and self.last_image is not None:
                    params_display = self.create_params_display(self.latest_autoexp, self.last_image.shape[1])
                    combined_image = np.vstack([params_display, self.last_image])
                    cv2.imshow(self.window_name, combined_image)
                elif got_new_image and self.last_image is not None:
                    # Display just the image if no auto-exposure data yet
                    cv2.imshow(self.window_name, self.last_image)

                # Process events and check for key press
                key = cv2.waitKey(10) & 0xFF
                if key == 27:  # ESC key
                    self.running = False
                    break

            except Exception as e:
                print(f"Error in display thread: {e}")
                break

        cv2.destroyAllWindows()

async def main(display):
    """
    Take photos continuously using the Frame camera and display them with auto-exposure parameters
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
    rx_autoexp = None

    try:
        frame = BrilliantMsg()
        name = await frame.connect(name=args.name)
        fw = await frame.send_lua("print(frame.FIRMWARE_VERSION)", await_print=True)
        tag = await frame.send_lua("print(frame.GIT_TAG)", await_print=True)
        batt = await frame.send_lua("print(frame.battery_level())", await_print=True)
        print(f"{name} | firmware {fw} | git {tag} | battery {batt}%")

        if frame.type != BrilliantDeviceType.FRAME:
            print("Live camera feed with parameters is a Frame-only feature")
            return

        # debug only: check our current battery level and memory usage
        batt_mem = await frame.send_lua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', await_print=True)
        print(f"Battery Level/Memory used: {batt_mem}")

        # Let the user know we're starting
        await frame.print_short_text('Loading...')

        # send the std lua files to Frame
        await frame.upload_stdlua_libs(lib_names=['data', 'battery', 'camera', 'code', 'plain_text'])

        # Send the main lua application
        await frame.upload_frame_app(local_filename="lua/live_camera_frame_app.lua")

        frame.attach_print_response_handler()

        # Start the frame app
        await frame.start_frame_app()

        # hook up the RxPhoto receiver
        rx_photo = RxPhoto()
        photo_queue = await rx_photo.attach(frame)

        # hook up the RxAutoExpResult receiver
        rx_autoexp = RxAutoExpResult()
        autoexp_queue = await rx_autoexp.attach(frame)

        # prime the camera with initial settings and give them time to take effect
        #await frame.send_message(0x0f, TxManualExpSettings(manual_shutter=1600).pack())
        #await asyncio.sleep(0.2)

        # custom auto exposure limits can be set here in the constructor
        # e.g. tx_auto_exp = TxAutoExpSettings(shutter_limit=1600, analog_gain_limit=32, rgb_gain_limit=1023)
        tx_auto_exp = TxAutoExpSettings(exposure=0.1, shutter_limit=10000, analog_gain_limit=16, rgb_gain_limit=287)
        #tx_auto_exp = TxAutoExpSettings()

        # send the auto exposure parameters to Frame before iterating over the loop
        await frame.send_message(0x0e, tx_auto_exp.pack())

        # give the frame some time for the autoexposure loop to run (50 times; every 0.1s)
        print("Letting autoexposure loop run for 5 seconds to settle")
        await asyncio.sleep(5.0)

        print("Starting continuous capture")

        # Create tasks for handling both photo and auto-exposure data
        photo_task = asyncio.create_task(handle_photos(frame, photo_queue, display))
        autoexp_task = asyncio.create_task(handle_autoexp(autoexp_queue, display))

        # Wait for either task to complete or the display to close
        while display.running:
            if photo_task.done():
                print("Photo task ended")
                break
            if autoexp_task.done():
                print("Auto-exposure task ended")
                break
            await asyncio.sleep(0.1)

        # Cancel tasks
        photo_task.cancel()
        autoexp_task.cancel()

    except asyncio.CancelledError:
        print("\nCapture loop cancelled")
    except Exception as e:
        print(f"\nAn error occurred: {e}")
    finally:
        # Clean up resources
        print("\nCleaning up resources...")
        if rx_photo and frame:
            rx_photo.detach(frame)
        if rx_autoexp and frame:
            rx_autoexp.detach(frame)
        if frame:
            frame.detach_print_response_handler()
            await frame.stop_frame_app()
            await frame.disconnect()
        display.stop()

async def handle_photos(frame, photo_queue, display):
    """Handle photo capture in a separate task"""
    capture_count = 0
    try:
        while True:
            if not display.running:
                break

            # Request a photo
            await frame.send_message(0x0d, TxCaptureSettings(resolution=720).pack())

            # get the jpeg bytes
            jpeg_bytes = await asyncio.wait_for(photo_queue.get(), timeout=10.0)

            # Update the display
            display.update_image(jpeg_bytes)

            capture_count += 1
            print(f"Captured frame {capture_count}", end="\r")

            # delay between captures, adjust this value as needed
            # to let the auto-exposure algorithm run between captures
            await asyncio.sleep(1.0)
    except asyncio.CancelledError:
        print("\nPhoto capture task cancelled")
        raise
    except Exception as e:
        print(f"\nError in photo capture task: {e}")
        raise

async def handle_autoexp(autoexp_queue, display):
    """Handle auto-exposure data in a separate task"""
    try:
        while True:
            # Get auto-exposure data
            autoexp_data = await autoexp_queue.get()

            # Update the display with new auto-exposure data
            display.update_autoexp(autoexp_data)
    except asyncio.CancelledError:
        print("\nAuto-exposure task cancelled")
        raise
    except Exception as e:
        print(f"\nError in auto-exposure task: {e}")
        raise

if __name__ == "__main__":
    display = CameraDisplay()

    def run_async():
        try:
            asyncio.run(main(display))
        except KeyboardInterrupt:
            display.stop()

    async_thread = threading.Thread(target=run_async, daemon=True)
    async_thread.start()

    # OpenCV GUI must run on the main thread on macOS
    try:
        display.run()
    except KeyboardInterrupt:
        display.stop()

    async_thread.join(timeout=5.0)
