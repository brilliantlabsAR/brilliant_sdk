import { BrilliantMsg, StdLua, TxCaptureSettings, TxManualExpSettings, RxPhoto } from 'brilliant-msg';
import { BrilliantDeviceType } from 'brilliant-ble';
import frameApp from './lua/manual_exposure_frame_app.lua?raw';

/**
 * Demonstrates taking a photo using the Frame camera with specific manual exposure settings.
 * This example involves:
 * - Sending `TxManualExpSettings` to the Frame device to configure parameters like shutter speed and gain.
 * - Sending `TxCaptureSettings` to request the photo capture.
 * - Using `RxPhoto` to receive the JPEG image data from the Frame.
 * - Displaying the captured photo within an HTML image element on the webpage.
 */
export async function run() {
  const frame = new BrilliantMsg();

  try {
    // Web Bluetooth API requires a user gesture to initiate the connection
    // This is usually a button click or similar event
    console.log("Connecting to Frame...");
    const deviceId = await frame.connect();
    console.log('Connected to:', deviceId);

    // debug only: check our current battery level and memory usage (which varies between 16kb and 31kb or so even after the VM init)
    const battMem = await frame.sendLua('print(frame.battery_level() .. " / " .. collectgarbage("count"))', {awaitPrint: true});
    console.log(`Battery Level/Memory used: ${battMem}`);

    if (frame.ble.type === BrilliantDeviceType.FRAME) {
      // Let the user know we're starting
      await frame.printShortText('Loading...');

      // send the std lua files to Frame
      await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.CameraMin, StdLua.CodeMin]);

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
      const rxPhoto = new RxPhoto();
      const photoQueue = await rxPhoto.attach(frame);

      // take the default manual exposure settings
      // and send them to Frame before taking the photo
      await frame.sendMessage(0x0c, new TxManualExpSettings({}).pack());

      // NOTE: it takes up to 200ms for manual camera settings to take effect!
      console.log("Waiting 200ms for manual exposure settings to take effect...");
      await new Promise(resolve => setTimeout(resolve, 200));

      // Request the photo by sending a TxCaptureSettings message
      await frame.sendMessage(0x0d, new TxCaptureSettings({}).pack());

      // get the jpeg bytes as soon as they're ready
      const jpegBytes = await photoQueue.get();
      console.log("Photo received, length:", jpegBytes.length);

      // display the image on the web page
      const img = document.createElement('img');
      img.src = URL.createObjectURL(new Blob([jpegBytes], { type: 'image/jpeg' }));
      const imageDiv = document.getElementById('image1');
      if (imageDiv) {
        // Clear any existing content in the div
        while (imageDiv.firstChild) {
          imageDiv.removeChild(imageDiv.firstChild);
        }
        imageDiv.appendChild(img);
      }

      // stop the photo listener and clean up its resources
      rxPhoto.detach(frame);

      // unhook the print handler
      frame.detachPrintResponseHandler()

      // break out of the frame app loop and reboot Frame
      await frame.stopFrameApp()
    } else {
      console.log("Manual exposure is only available on Frame devices, not Halo. Disconnecting...");
    }
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
