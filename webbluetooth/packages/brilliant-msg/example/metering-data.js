import { FrameMsg, StdLua, TxCode, RxMeteringData } from 'frame-msg';
import { BrilliantDeviceType } from 'frame-ble';
import frameApp from './lua/metering_data_frame_app.lua?raw';

/**
 * Demonstrates requesting and displaying a sequence of light metering updates from Frame's camera.
 * This example involves:
 * - Sending `TxCode` messages to the Frame device to trigger light metering updates.
 * - Using `RxMeteringData` to receive the metering data, which includes spot and matrix RGB values.
 * - Displaying the received metering data (spot R,G,B and matrix R,G,B) on the webpage.
 * - Printing the raw metering data objects to the console.
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

      // hook up the RxMeteringData receiver
      const rxMeteringData = new RxMeteringData();
      const meteringDataQueue = await rxMeteringData.attach(frame);

      // find the element to display the metering data
      const meteringDataDiv = document.getElementById('text1');
      if (meteringDataDiv) {
        // Clear any existing content in the div
        while (meteringDataDiv.firstChild) {
          meteringDataDiv.removeChild(meteringDataDiv.firstChild);
        }
      }

      // loop 60 times - await for the metering data to be received then print it to the console
      for (let i = 0; i < 60; i++) {
        await frame.sendMessage(0x12, new TxCode({ value: 1 }).pack());
        const data = await meteringDataQueue.get();
        console.log("Metering Data:", data);

        // Update the display element with the metering data
        meteringDataDiv.innerHTML = `
          Spot: R=${data.spot_r}, G=${data.spot_g}, B=${data.spot_b}<br>
          Matrix: R=${data.matrix_r}, G=${data.matrix_g}, B=${data.matrix_b}
        `;
      }

      // stop the listener and clean up its resources
      rxMeteringData.detach(frame);

      // unhook the print handler
      frame.detachPrintResponseHandler()

      // break out of the frame app loop and reboot Frame
      await frame.stopFrameApp()

    } else {
      console.log("Metering data is only available on Frame devices, not Halo. Disconnecting...");
    }
  } catch (error) {
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
