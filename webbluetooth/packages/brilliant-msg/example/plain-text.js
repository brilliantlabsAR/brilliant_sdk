import { BrilliantMsg, StdLua, TxPlainText } from 'brilliant-msg';
import frameApp from './lua/plain_text_frame_app.lua?raw';

/**
 * Demonstrates sending a sequence of plain text messages to a Frame device for display.
 * This example involves:
 * - Iteratively creating `TxPlainText` messages with varying text content and palette offsets (for different colors).
 * - Sending these messages to the Frame device, where a corresponding Lua application is expected to handle
 *   their display on the screen.
 * - Includes a delay between messages to allow each text to be visible.
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
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.PlainTextMin]);

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

    // Send the text for display on Frame
    // Note that the frameside app is expecting a message of type TxPlainText on msgCode 0x0a
    const displayStrings = ["white", "gray", "red", "pink", "dark\nbrown", "brown", "orange", "yellow", "dark\ngreen", "green", "light\ngreen", "night\nblue", "sea\nblue", "sky\nblue", "cloud\nblue"];
    for (let i = 0; i < displayStrings.length; i++) {
      await frame.sendMessage(0x0a, new TxPlainText({ text: displayStrings[i], x: 150, y: 50, paletteOffset: i+1 }).pack());
      await new Promise(resolve => setTimeout(resolve, 1000)); // 1 second delay
    }
    // clear the display
    await frame.sendMessage(0x0a, new TxPlainText({ text: " " }).pack());

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
