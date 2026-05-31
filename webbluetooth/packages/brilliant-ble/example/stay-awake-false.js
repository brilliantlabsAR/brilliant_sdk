import { BrilliantBle } from 'brilliant-ble';

export async function run() {
  const ble = new BrilliantBle();

  // Connect to Frame
  const deviceId = await ble.connect();

  // Send a break signal to Frame in case it is in a loop/main.lua
  await ble.sendBreakSignal();

  // Restore normal behavior that Frame turns off when placed in the charging cradle (and puts it to sleep now)
  await ble.sendLua("frame.stay_awake(false);print(0)", {awaitPrint: true})
  await ble.sendLua("frame.sleep()")
  console.log("Frame will switch off when placed in the charging cradle, and will be put to sleep now (tap to wake)")

  // Disconnect from Frame
  await ble.disconnect();
};
