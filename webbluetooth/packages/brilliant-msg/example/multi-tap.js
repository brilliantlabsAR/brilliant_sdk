import { BrilliantMsg, StdLua, TxCode, RxTap } from 'brilliant-msg';
import frameApp from './lua/multi_tap_frame_app.lua?raw';

/**
 * Demonstrates detecting and counting multi-tap events from a Frame device.
 * This example involves:
 * - Sending `TxCode` messages to the Frame device to subscribe to and later unsubscribe from tap events.
 * - Using `RxTap` to receive and process tap events, which counts consecutive taps within a defined threshold.
 * - Logging the detected tap counts to the console (e.g., "2-tap received", "3-tap received").
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

    // send the std lua files to Frame
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.CodeMin, StdLua.TapMin]);

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

    // hook up the RxTap receiver
    var rxTap = new RxTap({});
    var tapQueue = await rxTap.attach(frame);

    // Subscribe for tap events
    await frame.sendMessage(0x10, new TxCode({ value: 1 }).pack());

    // iterate 10 times
    for (let i = 0; i < 10; i++) {
      // wait for a multi-tap event
      var tapCount = await tapQueue.get();
      console.log(`${tapCount}-tap received`);
    }

    // unsubscribe from tap events
    await frame.sendMessage(0x10, new TxCode({ value: 0 }).pack());

    // stop the tap listener and clean up its resources
    rxTap.detach(frame);

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
