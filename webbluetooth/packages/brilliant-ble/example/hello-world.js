import { BrilliantBle, BrilliantDeviceType } from 'brilliant-ble';

export async function run() {
  console.log("Instantiating BrilliantBle...");
  const ble = new BrilliantBle();

  // Web Bluetooth API requires a user gesture to initiate the connection
  // This is usually a button click or similar event
  console.log("Connecting to Frame...");
  const deviceId = await ble.connect();
  console.log('Connected to:', deviceId);

  // Configure print response handler to show device output
  const printHandler = (data) => {
    console.log("Frame response:", data);
  };
  ble.setPrintResponseHandler(printHandler);

  // Send a break signal to the device in case it is in a loop
  console.log("Sending break signal to device...");
  await ble.sendBreakSignal({showMe: true});
  console.log("Break signal sent.");

  // wake up the display
  await ble.sendLua("frame.display.power_save(false);print(0)", {showMe: true, awaitPrint: true});

  if (ble.type === BrilliantDeviceType.HALO) {
    await ble.sendLua("frame.display.clear();print(0)", {showMe: true, awaitPrint: true});
  }

  // Send Lua command to the device
  console.log("Sending Lua command to device...");
  var luaCommand = "frame.display.text('Hello, '..frame.HARDWARE_VERSION..'!', 80, 100)frame.display.show()print('Response from device!')";
  await ble.sendLua(luaCommand, {showMe: true, awaitPrint: true});
  console.log("Lua command sent.");

  // Wait for a couple of seconds to allow the command to execute and text to be displayed
  await new Promise(resolve => setTimeout(resolve, 2000));

  if (ble.type === BrilliantDeviceType.HALO) {
    await ble.sendLua("frame.display.clear();print(0)", {showMe: true, awaitPrint: true});
  }

  // Send Lua command to the device
  console.log("Sending Lua command to device...");
  luaCommand = "frame.display.text('Goodbye, '..frame.HARDWARE_VERSION..'!', 80, 100)frame.display.show()print('Response from device!')";
  await ble.sendLua(luaCommand, {showMe: true, awaitPrint: true});
  console.log("Lua command sent.");

  // Wait for a couple of seconds to allow the command to execute and text to be displayed
  await new Promise(resolve => setTimeout(resolve, 2000));

  console.log("Disconnecting from device...");
  await ble.disconnect();
  console.log("Disconnected from device.");
};
