import { BrilliantMsg, StdLua, TxSprite, TxSpriteCoords, TxCode } from 'brilliant-msg';
import { BrilliantDeviceType } from 'brilliant-ble';
import frameApp from './lua/sprite_move_frame_app.lua?raw';

/**
 * Demonstrates sending a sprite to a Frame device and then moving it to random positions.
 * This example involves:
 * - Fetching an indexed PNG image and converting it to a `TxSprite` using `TxSprite.fromIndexedPngBytes`.
 * - Sending this initial `TxSprite` to the Frame device.
 * - Iteratively:
 *   - Generating random X and Y coordinates.
 *   - Sending these coordinates to the Frame device using a `TxSpriteCoords` message.
 *   - Sending a `TxCode` message to trigger the Frame device to redraw the sprite at the new coordinates.
 * - A short pause is included in each iteration to make the movement visible.
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
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.SpriteMin, StdLua.CodeMin, StdLua.SpriteCoordsMin]);

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

    // send the 1-bit image to Frame in chunks
    // Note that the frameside app is expecting a message of type TxSprite on msgCode 0x20
    let response = await fetch(new URL('./images/rings_1bit.png', import.meta.url));
    let imageBytes = new Uint8Array(await response.arrayBuffer());
    let sprite = await TxSprite.fromIndexedPngBytes(imageBytes);
    await frame.sendMessage(0x20, sprite.pack());

    // send the sprite coordinates to Frame 20 times with random positions on msgCode 0x40
    // then send a message of type TxCode on msgCode 0x50 to draw the sprite

    // Determine max coordinates based on device type
    const isFrame = frame.ble.type === BrilliantDeviceType.FRAME;
    const maxX = isFrame ? 441 : 57;
    const maxY = isFrame ? 201 : 57;

    for (let i = 0; i < 20; i++) {
      const x = Math.floor(Math.random() * maxX) + 1;
      const y = Math.floor(Math.random() * maxY) + 1;
      const coords = new TxSpriteCoords({ code: 0x20, x: x, y: y, offset: 0 });
      await frame.sendMessage(0x40, coords.pack());

      // draw the sprite
      await frame.sendMessage(0x50, new TxCode({}).pack());

      // sleep for 1s to allow the user to see the image
      await new Promise(resolve => setTimeout(resolve, 1000));
    }

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
