import { BrilliantBle } from 'brilliant-ble';

export async function run() {
  const ble = new BrilliantBle();

  // Connect to Frame
  const deviceId = await ble.connect();

  // Send a reset signal to Frame to reboot it
  await ble.sendResetSignal();

  // Disconnect from Frame
  await ble.disconnect();
};
