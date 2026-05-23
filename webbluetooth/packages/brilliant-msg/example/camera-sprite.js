import { FrameMsg, StdLua, TxCaptureSettings, RxPhoto, TxSprite, TxImageSpriteBlock } from 'frame-msg';
import { BrilliantDeviceType } from 'frame-ble';
import frameApp from './lua/camera_sprite_frame_app.lua?raw';

/**
 * Creates or updates an <img> element within a specified div to display a JPEG image.
 * @param {Uint8Array} imageBytes - The byte array of the JPEG image.
 * @param {string} mimeType - The mime type of the image bytes, e.g. 'image/jpeg'.
 * @param {string} divId - The ID of the div element to display the image in.
 */
function displayImage(imageBytes, mimeType, divId) {
  const img = document.createElement('img');
  img.src = URL.createObjectURL(new Blob([imageBytes], { type: mimeType }));
  const imageDiv = document.getElementById(divId);
  if (imageDiv) {
    imageDiv.innerHTML = ''; // Clear any existing content
    imageDiv.appendChild(img);
  }
}

/**
 * Demonstrates a round-trip image manipulation workflow with a Frame device.
 * This example involves:
 * 1. Capturing a photo from the Frame camera using `TxCaptureSettings` to initiate and `RxPhoto` to receive the image data.
 * 2. Displaying this original photo on the webpage.
 * 3. Converting the received JPEG photo into a `TxSprite` using `TxSprite.fromImageBytes`, which involves resizing and color quantization.
 * 4. Displaying the generated sprite (as a PNG) on the webpage for comparison.
 * 5. Creating a `TxImageSpriteBlock` from this `TxSprite`, which splits the sprite into smaller, transmittable lines.
 * 6. Sending this `TxImageSpriteBlock` (header first, then each sprite line) back to the Frame device for display on its screen.
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
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.CameraMin, StdLua.ImageSpriteBlockMin]);

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

    // give Frame some time for the autoexposure to settle
    console.log("Waiting 2s for autoexposure to settle...");
    await new Promise(resolve => setTimeout(resolve, 2000));
    console.log("Taking photo...");

    // Request the photo by sending a TxCaptureSettings message
    const resolution = frame.ble.type === BrilliantDeviceType.FRAME ? 512 : 640;
    await frame.sendMessage(0x0d, new TxCaptureSettings({resolution: resolution}).pack());

    // get the jpeg bytes as soon as they're ready
    const jpegBytes = await photoQueue.get();
    console.log("Photo received, length:", jpegBytes.length);

    // display the source image on the web page
    displayImage(jpegBytes, 'image/jpeg', 'image1');

    // send the photo back to Frame as a sprite block
    console.log("Sending sprite back to Frame for display...");
    const sprite = await TxSprite.fromImageBytes(jpegBytes);

    // display the sprite on the web page
    displayImage(sprite.toPngBytes(), 'image/png', 'image2');

    const isb = new TxImageSpriteBlock({ image: sprite, spriteLineHeight: 20 });
    // send the Image Sprite Block header
    await frame.sendMessage(0x20, isb.pack());

    // then send all the slices
    for (const spr of isb.spriteLines) {
      await frame.sendMessage(0x20, spr.pack());
    }

    // sleep for 20 seconds to allow the user to see the image
    console.log("Displaying sprite for 20 seconds...");
    await new Promise(resolve => setTimeout(resolve, 20000));

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
