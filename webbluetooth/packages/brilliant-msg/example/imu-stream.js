import { BrilliantMsg, StdLua, TxCode, RxIMU, MagCalibration, CompassHeading } from 'brilliant-msg';
import frameApp from './lua/imu_stream_frame_app.lua?raw';

/**
 * Demonstrates streaming Inertial Measurement Unit (IMU) data from a Frame device.
 * This example involves:
 * - Sending `TxCode` messages to start and stop the IMU data stream on the Frame device.
 * - Using `RxIMU` to receive IMU data, which includes compass and accelerometer readings.
 * - Calculating pitch and roll from the accelerometer data.
 * - Displaying the raw compass, accelerometer, and calculated pitch/roll values on the webpage.
 * - Printing the received IMU data objects to the console.
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
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.IMUMin, StdLua.CodeMin]);

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

    // hook up the RxIMU receiver
    const rxIMU = new RxIMU({smoothingSamples: 5});
    const imuQueue = await rxIMU.attach(frame);

    // A default (uncalibrated) MagCalibration ships the Halo mag->accel alignment
    // matrix, so the tilt-compensated heading below is usable on a worn Halo
    // before any per-unit calibration. To go further, load a mag_calibration.json
    // produced by the Python tool: MagCalibration.fromJsonString(jsonText).
    const cal = new MagCalibration();

    // Start the IMU updates
    console.log("Starting IMU stream...");
    await frame.sendMessage(0x40, new TxCode({ value: 1 }).pack());

    // find the element to display the IMU data
    const imuDataDiv = document.getElementById('text1');
    if (imuDataDiv) {
      // Clear any existing content in the div
      while (imuDataDiv.firstChild) {
        imuDataDiv.removeChild(imuDataDiv.firstChild);
      }
    }

    // loop 100 times - await for the IMU data to be received then print it to the console
    for (let i = 0; i < 100; i++) {
      const imuData = await imuQueue.get();
      console.log("IMU Data:", imuData);

      // Tilt-compensated magnetic heading from the smoothed host-frame samples,
      // via the default (or a loaded) MagCalibration. This is a *magnetic*
      // heading; add your location's declination for true North.
      const [mx, my, mz] = imuData.compass;
      const [ax, ay, az] = imuData.accel;
      const heading = cal.heading(mx, my, mz, ax, ay, az);
      const cardinal = CompassHeading.degreesToCardinal(heading);

      // Update the display element with the IMU data
      // breaking out the smoothed compass and accel arrays of 3 ints
      // and also the pitch and roll angles
      imuDataDiv.innerHTML = `
        <div>IMU Data:</div>
        <div>Compass: ${imuData.compass.join(', ')}</div>
        <div>Accelerometer: ${imuData.accel.join(', ')}</div>
        <div>Pitch: ${imuData.pitch.toFixed(2)}</div>
        <div>Roll: ${imuData.roll.toFixed(2)}</div>
        <div>Heading: ${heading.toFixed(1)} (${cardinal})</div>
      `;
    }

    console.log("Stopping IMU stream...");
    await frame.sendMessage(0x40, new TxCode({ value: 0 }).pack());

    // stop the listener and clean up its resources
    rxIMU.detach(frame);

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
