import { BrilliantBle } from 'brilliant-ble';

export async function run() {
  const ble = new BrilliantBle();

  // Connect to Frame
  const deviceId = await ble.connect();

  // Configure print response handler to show device output
  const printHandler = (data) => {
    console.log("Frame response:", data);
  };
  ble.setPrintResponseHandler(printHandler);

  // Send a break signal to Frame in case it is in a loop/main.lua
  await ble.sendBreakSignal();

  // Set the palette back to the firmware default
  await ble.sendLua("frame.display.assign_color_ycbcr(0, 0, 4, 4);print(0)", {awaitPrint: true}) // VOID
  await ble.sendLua("frame.display.assign_color_ycbcr(1, 15, 4, 4);print(0)", {awaitPrint: true}) // WHITE
  await ble.sendLua("frame.display.assign_color_ycbcr(2, 7, 4, 4);print(0)", {awaitPrint: true}) // GREY
  await ble.sendLua("frame.display.assign_color_ycbcr(3, 5, 3, 6);print(0)", {awaitPrint: true}) // RED
  await ble.sendLua("frame.display.assign_color_ycbcr(4, 9, 3, 5);print(0)", {awaitPrint: true}) // PINK
  await ble.sendLua("frame.display.assign_color_ycbcr(5, 2, 2, 5);print(0)", {awaitPrint: true}) // DARKBROWN
  await ble.sendLua("frame.display.assign_color_ycbcr(6, 4, 2, 5);print(0)", {awaitPrint: true}) // BROWN
  await ble.sendLua("frame.display.assign_color_ycbcr(7, 9, 2, 5);print(0)", {awaitPrint: true}) // ORANGE
  await ble.sendLua("frame.display.assign_color_ycbcr(8, 13, 2, 4);print(0)", {awaitPrint: true}) // YELLOW
  await ble.sendLua("frame.display.assign_color_ycbcr(9, 4, 4, 3);print(0)", {awaitPrint: true}) // DARKGREEN
  await ble.sendLua("frame.display.assign_color_ycbcr(10, 6, 2, 3);print(0)", {awaitPrint: true}) // GREEN
  await ble.sendLua("frame.display.assign_color_ycbcr(11, 10, 1, 3);print(0)", {awaitPrint: true}) // LIGHTGREEN
  await ble.sendLua("frame.display.assign_color_ycbcr(12, 1, 5, 2);print(0)", {awaitPrint: true}) // NIGHTBLUE
  await ble.sendLua("frame.display.assign_color_ycbcr(13, 4, 5, 2);print(0)", {awaitPrint: true}) // SEABLUE
  await ble.sendLua("frame.display.assign_color_ycbcr(14, 8, 5, 2);print(0)", {awaitPrint: true}) // SKYBLUE
  await ble.sendLua("frame.display.assign_color_ycbcr(15, 13, 4, 3);print(0)", {awaitPrint: true}) // CLOUDBLUE

  // Disconnect from Frame
  await ble.disconnect();
};
