# WebBluetooth (TypeScript) quickstart

```bash
npm install brilliant-sdk        # or brilliant-ble / brilliant-msg separately
```

Browser-only (Chrome/Edge; WebBluetooth needs a user gesture to connect —
call `connect()` from a click handler). Vite serves Lua files as strings via
`?raw` imports.

```typescript
import { BrilliantMsg, StdLua, TxPlainText } from 'brilliant-msg';
import frameApp from './lua/my_frame_app.lua?raw';

const TEXT_MSG = 0x0a;

export async function run() {
  const frame = new BrilliantMsg();
  try {
    await frame.connect();                                  // must be user-initiated
    await frame.uploadStdLuaLibs([StdLua.DataMin, StdLua.PlainTextMin]);
    await frame.uploadFrameApp(frameApp);
    frame.attachPrintResponseHandler(console.log);
    await frame.startFrameApp();

    await frame.sendMessage(TEXT_MSG, new TxPlainText({ text: 'Hello!' }).pack());

    frame.detachPrintResponseHandler();
    await frame.stopFrameApp();
  } finally {
    await frame.disconnect();
  }
}
```

Receivers use attach/queue: `const q = await new RxPhoto({}).attach(frame);
const jpeg = await q.get();` — detach when done.

The device-side Lua is identical to the Python quickstart's — the Lua never
changes between SDKs.

## Read next

- `webbluetooth/packages/brilliant-msg/example/EXAMPLES.md` — all 19 examples
  with host **and** Lua source inline (the fastest single file to learn the
  message pairing from).
- Live demos + TypeDoc: https://brilliantlabsar.github.io/brilliant_sdk/
- TS-only convenience: `AsyncQueue`. `TxTextPage` +
  `CircularTextLayout`/`RectangularTextLayout` and `RxClick`/`ClickType` exist
  in all three SDKs. `MagCalibration`/`CompassHeading` also exist in Python
  (`brilliant_msg.calibration`, `.heading`); Flutter has them only inside the
  `imu_compass` example.
- No test suite here — `npm run build` per package is the check; validate Lua
  with the Python `halo-emulator`.
