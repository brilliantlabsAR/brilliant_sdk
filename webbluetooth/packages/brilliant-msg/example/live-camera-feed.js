import { FrameMsg, StdLua, TxCaptureSettings, RxPhoto } from 'frame-msg';
import { BrilliantDeviceType } from 'frame-ble';
import frameApp from './lua/live_camera_feed_frame_app.lua?raw';

/**
 * Demonstrates capturing a sequence of photos from the Frame camera and displaying them
 * on a webpage to create a live feed effect.
 * This example involves:
 * - Iteratively requesting photos from the Frame device using `TxCaptureSettings`.
 * - Receiving the JPEG image data via `RxPhoto`.
 * - Displaying each newly captured photo in an HTML image element, replacing the previous one.
 */
export async function run() {
  const frame = new FrameMsg();

  try {
    // Web Bluetooth API requires a user gesture to initiate the connection
    // This is usually a button click or similar event
    console.log("Connecting to Frame...");
    const deviceId = await frame.connect();
    console.log('Connected to:', deviceId);

    // debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
    const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', {awaitPrint: true});
    console.log(`Battery Level/Memory used: ${battMem}`);

    // Let the user know we're starting
    await frame.printShortText('Loading...');

    // send the std lua files to Frame
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.CameraMin]);

    // Send the main lua application from this project to Frame that will run the app
    await frame.uploadFrameApp(frameApp);

    // attach the print response handler so we can see stdout from Frame Lua print() statements
    // If we assigned this handler before the frameside app was running,
    // any await_print=True commands will echo the acknowledgement byte (e.g. "1"), but if we assign
    // the handler now we'll see any lua exceptions (or stdout print statements)
    frame.attachPrintResponseHandler(console.log);

    // "require" the main frame_app lua file to run it, and block until it has started.
    // It signals that it is ready by sending something on the string response channel.
    await frame.startFrameApp();

    // hook up the RxPhoto receiver
    const upright = frame.ble.type === BrilliantDeviceType.FRAME; // rotate images from Frame 90 degrees counterclockwise, not Halo
    const rxPhoto = new RxPhoto({upright: upright});
    const photoQueue = await rxPhoto.attach(frame);

    // create the element to display the photo
    const img = document.createElement('img');
    const imageDiv = document.getElementById('image1');
    if (imageDiv) {
      // Clear any existing content in the div
      while (imageDiv.firstChild) {
        imageDiv.removeChild(imageDiv.firstChild);
      }
      imageDiv.appendChild(img);
    }

    // loop 20 times - take a photo and display it in the div
    for (let i = 0; i < 20; i++) {
      // Request the photo by sending a TxCaptureSettings message
      const resolution = frame.ble.type === BrilliantDeviceType.FRAME ? 512 : 640;
      await frame.sendMessage(0x0d, new TxCaptureSettings({resolution: resolution}).pack());

      // get the jpeg bytes as soon as they're ready
      const jpegBytes = await photoQueue.get();
      console.log("Photo received, length:", jpegBytes.length);

      // display the image on the web page
      // overwriting the previous image
      img.src = URL.createObjectURL(new Blob([jpegBytes], { type: 'image/jpeg' }));
    }

    // stop the photo listener and clean up its resources
    rxPhoto.detach(frame);

    // unhook the print handler
    frame.detachPrintResponseHandler()

    // break out of the frame app loop and reboot Frame
    await frame.stopFrameApp()
  }
  catch (error) {
    console.error("Error:", error);
  }
  finally {
    // Ensure the Frame is disconnected in case of an error
    try {
      await frame.disconnect();
      console.log("Disconnected from Frame.");
    } catch (disconnectError) {
      console.error("Error during disconnection:", disconnectError);
    }
  }
};
