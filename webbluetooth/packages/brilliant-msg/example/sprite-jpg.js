import { BrilliantMsg, StdLua, TxSprite } from 'brilliant-msg';
import frameApp from './lua/sprite_jpg_frame_app.lua?raw';

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
 * Demonstrates fetching a JPG image, converting it to a `TxSprite`, and sending it to a Frame device.
 * This example involves:
 * - Fetching a JPG image from a local path.
 * - Displaying the original JPG image on the webpage.
 * - Converting the JPG image data into a `TxSprite` object using `TxSprite.fromImageBytes`.
 *   This process includes resizing the image and quantizing its colors to a limited palette.
 * - Sending the entire packed `TxSprite` (header, palette, and pixel data) to the Frame device
 *   in a single message.
 * - Displaying the generated `TxSprite` (as a PNG) on the webpage for comparison with the original.
 * - The Frame device is expected to display the received sprite.
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

    // Let the user know we're starting
    await frame.printShortText('Loading...');

    // send the std lua files to Frame that handle data accumulation and text display
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.SpriteMin]);

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

    // Quantize the image and send the image to Frame in chunks
    // read in the image bytes from "images/koala.jpg" and send it to the Frame
    const response = await fetch(new URL('./images/koala.jpg', import.meta.url));
    const imageBytes = new Uint8Array(await response.arrayBuffer());

    // display the source image on the web page
    displayImage(imageBytes, 'image/jpeg', 'image1');

    const sprite = await TxSprite.fromImageBytes(imageBytes);
    await frame.sendMessage(0x20, sprite.pack());

    // display the sprite on the web page
    displayImage(sprite.toPngBytes(), 'image/png', 'image2');

    // sleep for 20 seconds to allow the user to see the image
    await new Promise(resolve => setTimeout(resolve, 20000));

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
