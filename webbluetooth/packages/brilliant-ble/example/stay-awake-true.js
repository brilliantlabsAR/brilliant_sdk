import { BrilliantBle } from 'brilliant-ble';

export async function run() {
  const ble = new BrilliantBle();

  // Connect to Frame
  const deviceId = await ble.connect();

  // Send a break signal to Frame in case it is in a loop/main.lua
  await ble.sendBreakSignal();

  // Keep Frame awake even in charging cradle (for development)
  await ble.sendLua("frame.stay_awake(true);print(0)", {awaitPrint: true})

  // Disconnect from Frame
  await ble.disconnect();
};
