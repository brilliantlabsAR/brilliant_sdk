# Migration Guide — WebBluetooth SDK

This guide covers migrating from the `frame-ble` / `frame-msg` npm packages to `brilliant-ble` / `brilliant-msg`.

---

## 1. Package renames

```bash
# Remove old packages
npm uninstall frame-ble frame-msg

# Install new packages
npm install brilliant-ble brilliant-msg

# Or install the meta-package (installs both)
npm install brilliant-sdk
```

| Old package | New package | New version |
|-------------|-------------|-------------|
| `frame-ble` | `brilliant-ble` | 1.0.0 |
| `frame-msg` | `brilliant-msg` | 2.0.0 |
| — | `brilliant-sdk` (new meta-package) | 1.0.0 |

---

## 2. Import and class renames

`FrameBle` is now `BrilliantBle` and `FrameMsg` is now `BrilliantMsg`.

```js
// Before
import { FrameBle } from 'frame-ble';
import { FrameMsg, StdLua, RxPhoto, TxCaptureSettings } from 'frame-msg';

// After
import { BrilliantBle, BrilliantDeviceType } from 'brilliant-ble';
import { BrilliantMsg, StdLua, RxPhoto, TxCaptureSettings } from 'brilliant-msg';

// Or import everything from the meta-package
import { BrilliantBle, BrilliantMsg, BrilliantDeviceType, StdLua } from 'brilliant-sdk';
```

All other class names (`TxSprite`, `RxPhoto`, `RxIMU`, `TxPlainText`, etc.) are unchanged.

---

## 3. Breaking change — Lua frameside event loop

This is the most significant change. Every existing `frame_app.lua` must be updated.

### What changed

The old `data.lua` used a **keyed table** (`data.app_data`) populated automatically by registered parsers. The new `data.lua` uses an **ordered queue**: `process_raw_items()` now returns a list of `(flag, raw_bytes)` pairs in arrival order, and the caller is responsible for dispatching and parsing each one.

The old `data.parsers`, `data.app_data`, and `data.app_data_block` tables no longer exist.

### Before

```lua
local data = require('data.min')
local camera = require('camera.min')

CAPTURE_SETTINGS_MSG = 0x0d

-- Register parser globally
data.parsers[CAPTURE_SETTINGS_MSG] = camera.parse_capture_settings

function app_loop()
    print('Frame app is running')
    while true do
        rc, err = pcall(function()
            local items_ready = data.process_raw_items()  -- returns count

            if items_ready > 0 then
                if data.app_data[CAPTURE_SETTINGS_MSG] ~= nil then
                    camera.capture_and_send(data.app_data[CAPTURE_SETTINGS_MSG])
                    data.app_data[CAPTURE_SETTINGS_MSG] = nil  -- clear after use
                end
            end

            frame.sleep(0.1)
        end)
        if rc == false then print(err); break end
    end
end

app_loop()
```

### After

```lua
local data = require('data.min')
local camera = require('camera.min')

CAPTURE_SETTINGS_MSG = 0x0d

-- No parser registration

function app_loop()
    print('Frame app is running')
    while true do
        rc, err = pcall(function()
            local items = data.process_raw_items()  -- returns list of {flag, raw} pairs

            for i = 1, #items do
                local flag = items[i][1]
                local raw  = items[i][2]

                if flag == CAPTURE_SETTINGS_MSG then
                    camera.capture_and_send(camera.parse_capture_settings(raw))
                end
            end

            frame.sleep(0.1)
        end)
        if rc == false then print(err); break end
    end
end

app_loop()
```

### Key points

- `data.parsers`, `data.app_data`, and `data.app_data_block` are **removed** — any reference to them will error at runtime.
- Messages are processed in **arrival order**, which is now guaranteed.
- After each message is enqueued, an ACK is sent back to the host (`\x01\x00\x00` success / `\x01\x00\x01` error). If you use `sendData({ awaitData: true })` on the host side, the call will now wait for this ACK before returning, enabling receiver-paced flow control.

---

## 4. Breaking change — IMU data type

`RxIMU`, `IMUData`, `IMURawData`, and `SensorBuffer` now use `float32` instead of `int16`.

The Lua library `imu.lua` now packs 6 × `float32` (was 6 × `int16`). If you read IMU bytes directly, update the unpacking. If you use `RxIMU` from `brilliant-msg`, the updated library handles this automatically.

---

## 5. Breaking change — `TxTextSpriteBlock`

The `text` argument has been removed from the constructor. Use `createTextSprites(text)` instead, which returns an array of `TxSprite` that you send individually.

```js
// Before
const block = new TxTextSpriteBlock({ text: 'Hello world', ... });
await frame.sendMessage(0x0a, block.pack());

// After
const block = new TxTextSpriteBlock({ ... });
const sprites = block.createTextSprites('Hello world');
for (const sprite of sprites) {
  await frame.sendMessage(0x0a, sprite.pack());
}
```

`maxDisplayRows` has been renamed to `maxDisplayLines`.

---

## 6. Breaking change — `TxSprite` wire format

A `compressed` flag byte (`0x00` = uncompressed) is now inserted at header offset 5, shifting `bpp` to offset 6 and `num_colors` to offset 7.

**This is a wire-format change.** The host-side `TxSprite` and the device-side `sprite.lua` / `image_sprite_block.lua` must be updated together. If you use the bundled Lua libraries from `brilliant-msg`, they are already updated — just ensure you re-upload them to the device. If you have copied or customised the Lua libraries, update them to match the new format.

---

## 7. New — `BrilliantDeviceType`

Device type is now detected automatically at connection time by probing for the Halo audio characteristic.

```js
import { BrilliantBle, BrilliantDeviceType } from 'brilliant-ble';

const ble = new BrilliantBle();
await ble.connect();

if (ble.type === BrilliantDeviceType.HALO) {
  console.log('Connected to Halo');
} else if (ble.type === BrilliantDeviceType.FRAME) {
  console.log('Connected to Frame');
}
```

---

## 8. New — Halo-only methods on `BrilliantBle`

```js
// Send audio data (LC3 or PCM) to the Halo audio characteristic
await ble.sendAudio(data: Uint8Array);

// Remove main.lua from Halo and reset the Lua VM
await ble.sendRemoveSignal();
```

---

## 9. New — `CircularTextLayout` and `RxClick`

```js
import { TxTextPage, CircularTextLayout, RectangularTextLayout } from 'brilliant-msg';

// For Halo's circular display
const layout = new CircularTextLayout({ width: 256, height: 256, fontSize: 24 });

// For Frame's rectangular display
// const layout = new RectangularTextLayout({ width: 640, height: 400, fontSize: 36 });

const page = new TxTextPage({ layout, text: 'Hello from Halo!' });
```

```js
import { RxClick, ClickType } from 'brilliant-msg';

const rxClick = new RxClick();
const clickQueue = await rxClick.attach(frame);

const click = await clickQueue.get();
if (click === ClickType.SINGLE) console.log('single click');
if (click === ClickType.DOUBLE) console.log('double click');
if (click === ClickType.LONG)   console.log('long press');

rxClick.detach(frame);
```

---

## 10. New - Device behavior

Halo starts with its display in `power_save` mode to conserve power, unlike Frame which started with the display enabled. Programs that use Halo's display should call `frame.display.power_save(false)`. Draw calls won't fail if the display is in power-save mode, but they won't be shown.