import { BrilliantBle } from 'brilliant-ble';

export async function run() {
  const ble = new BrilliantBle();

  // Connect to Frame
  const deviceId = await ble.connect();

  // Configure print response handler to show Frame output
  const printHandler = (data) => {
    console.log("Frame response:", data);
  };
  ble.setPrintResponseHandler(printHandler);

  // Send a break signal to Frame in case it is in a loop/main.lua
  await ble.sendBreakSignal({showMe: true});

  // Clear the Frame display
  var luaCommand = "frame.display.text('', 1, 1);frame.display.show();print(0)";
  await ble.sendLua(luaCommand, {showMe: true, awaitPrint: true});

  // Wait for a couple of seconds
  await new Promise(resolve => setTimeout(resolve, 2000));

  // Disconnect from Frame
  await ble.disconnect();
};
