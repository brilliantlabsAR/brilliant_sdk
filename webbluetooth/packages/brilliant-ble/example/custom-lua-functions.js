import { BrilliantBle } from 'brilliant-ble';
import fibonacciLua from './lua/fibonacci.lua?raw';

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
  await ble.sendBreakSignal();

  // Send a lua script to Frame and "require" it to run it
  await ble.uploadFileFromString(fibonacciLua, "fibonacci.lua");
  await ble.sendLua("require('fibonacci');print(0)", {awaitPrint: true})

  // we can call the function(s) loaded from the file
  const myFibNum = 20
  const response = await ble.sendLua(`print(fibonacci(${myFibNum}))`, {awaitPrint: true})
  console.log(`Answer was: ${response}`)

  // Disconnect from Frame
  await ble.disconnect();
};
