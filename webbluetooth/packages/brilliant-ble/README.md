# brilliant-ble

Low-level library for Bluetooth LE connection to [Brilliant Labs Frame and Halo](https://brilliant.xyz/) devices via WebBluetooth.

[Frame SDK documentation](https://docs.brilliant.xyz/frame/frame-sdk/) | [GitHub Repo](https://github.com/brilliantlabsAR/brilliant_sdk/tree/main/webbluetooth/packages/brilliant-ble) | [API Docs](https://brilliantlabsAR.github.io/brilliant_sdk/brilliant-ble/api) | [Live Examples](https://brilliantlabsAR.github.io/brilliant_sdk/brilliant-ble/)

## Installation

```bash
npm install brilliant-ble
```

## Usage

```javascript
import { BrilliantBle, BrilliantDeviceType } from 'brilliant-ble';

export async function run() {
  const ble = new BrilliantBle();

  const deviceName = await ble.connect();
  console.log(`Connected to ${deviceName} (${ble.type})`);

  ble.setPrintResponseHandler(console.log);

  // Send a break signal to stop any running Lua app
  await ble.sendBreakSignal();

  // Send Lua command — Frame and Halo share the same Lua API
  const luaCommand = "frame.display.text('Hello!', 1, 1)frame.display.show()print('done')";
  await ble.sendLua(luaCommand, { awaitPrint: true });

  await new Promise(resolve => setTimeout(resolve, 2000));

  // Halo-specific: remove main.lua from the device
  if (ble.type === BrilliantDeviceType.HALO) {
    await ble.sendRemoveSignal();
  }

  await ble.disconnect();
};
```

## Device type detection

After `connect()` resolves, `ble.type` is set to a `BrilliantDeviceType` value:

| Value | Meaning |
|---|---|
| `BrilliantDeviceType.FRAME` | Connected to a Frame device |
| `BrilliantDeviceType.HALO` | Connected to a Halo device |
| `BrilliantDeviceType.UNKNOWN` | Not yet connected |

Halo is detected automatically by the presence of its audio TX characteristic (UUID `7a230005-...`).

## Halo-specific APIs

| Method | Description |
|---|---|
| `sendAudio(data, awaitBtResponse?)` | Send audio data to the Halo audio characteristic (write-without-response by default) |
| `sendRemoveSignal()` | Remove `main.lua` from Halo (sends `0x05` signal byte) |
