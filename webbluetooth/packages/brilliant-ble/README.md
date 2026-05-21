# frame-ble

Low-level library for Bluetooth LE connection to [Brilliant Labs Frame and Halo](https://brilliant.xyz/) devices via WebBluetooth.

[Frame SDK documentation](https://docs.brilliant.xyz/frame/frame-sdk/) | [GitHub Repo](https://github.com/CitizenOneX/frame-ble-webbluetooth/) | [API Docs](https://citizenonex.github.io/frame-ble-webbluetooth/api) | [Live Examples](https://citizenonex.github.io/frame-ble-webbluetooth/)

## Installation

```bash
npm install frame-ble
```

## Usage

```javascript
import { FrameBle, BrilliantDeviceType } from 'frame-ble';

export async function run() {
  const frameBle = new FrameBle();

  const deviceName = await frameBle.connect();
  console.log(`Connected to ${deviceName} (${frameBle.type})`);

  frameBle.setPrintResponseHandler(console.log);

  // Send a break signal to stop any running Lua app
  await frameBle.sendBreakSignal();

  // Send Lua command — Frame and Halo share the same Lua API
  const luaCommand = "frame.display.text('Hello!', 1, 1)frame.display.show()print('done')";
  await frameBle.sendLua(luaCommand, { awaitPrint: true });

  await new Promise(resolve => setTimeout(resolve, 2000));

  // Halo-specific: remove main.lua from the device
  if (frameBle.type === BrilliantDeviceType.HALO) {
    await frameBle.sendRemoveSignal();
  }

  await frameBle.disconnect();
};
```

## Device type detection

After `connect()` resolves, `frameBle.type` is set to a `BrilliantDeviceType` value:

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
