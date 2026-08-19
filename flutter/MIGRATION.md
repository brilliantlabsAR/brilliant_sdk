# Migration Guide — Flutter SDK

This guide covers migrating from the `frame_ble` / `frame_msg` / `simple_frame_app` packages to `brilliant_ble` / `brilliant_msg` / `simple_brilliant_app`.

---

## 1. Package renames

Update your `pubspec.yaml` dependencies:

| Old package | New package | New version |
|-------------|-------------|-------------|
| `frame_ble` | `brilliant_ble` | 5.0.0 |
| `frame_msg` | `brilliant_msg` | 4.0.0 |
| `simple_frame_app` | `simple_brilliant_app` | 9.0.0 |
| `brilliant_sdk` | `brilliant_sdk` (updated deps) | 2.0.0 |

```yaml
# Before
dependencies:
  frame_ble: ^3.0.0
  frame_msg: ^2.0.0
  simple_frame_app: ^8.0.0

# After
dependencies:
  brilliant_ble: ^5.0.0
  brilliant_msg: ^4.0.0
  simple_brilliant_app: ^9.0.0
```

Then run `flutter pub get`.

If your `pubspec.yaml` declares Lua library assets from `brilliant_msg`, update the package path:

```yaml
# Before
flutter:
  assets:
    - packages/frame_msg/lua/data.min.lua
    - packages/frame_msg/lua/sprite.min.lua
    - packages/frame_msg/lua/plain_text.min.lua
    - packages/frame_msg/lua/camera.min.lua
    - packages/frame_msg/lua/audio.min.lua
    - packages/frame_msg/lua/imu.min.lua

# After
flutter:
  assets:
    - packages/brilliant_msg/lua/data.min.lua
    - packages/brilliant_msg/lua/sprite.min.lua
    - packages/brilliant_msg/lua/plain_text.min.lua
    - packages/brilliant_msg/lua/camera.min.lua
    - packages/brilliant_msg/lua/audio.min.lua
    - packages/brilliant_msg/lua/imu.min.lua
```

---

## 2. Import changes

```dart
// Before
import 'package:frame_ble/brilliant_bluetooth.dart';
import 'package:frame_msg/frame_msg.dart';

// After
import 'package:brilliant_ble/brilliant_bluetooth.dart';
import 'package:brilliant_msg/brilliant_msg.dart';
```

> **Note:** Unlike the Python and WebBluetooth SDKs, the `brilliant_ble` package already used `Brilliant`-prefixed class names (`BrilliantBluetooth`, `BrilliantDevice`, `BrilliantConnectionState`, etc.) in the previous release. **No class renames are required** — only the package name in the import path changes.

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
- After each message is enqueued, an ACK is sent back to the host (`\x01\x00\x00` success / `\x01\x00\x01` error). If you use `sendData(awaitData: true)` on the host side, the call will now wait for this ACK before returning, enabling receiver-paced flow control.

---

## 4. Breaking change — `RxIMU` data type

`IMUData`, `IMURawData`, and `SensorBuffer` now use `double` instead of `int`.

The Lua library `imu.lua` now packs 6 × `float32` (was 6 × `int16`). If you read the Dart `IMUData` fields, update any code that assumed integer values:

```dart
// Before
int ax = imuData.accelerometerX;

// After
double ax = imuData.accelerometerX;
```

If you use `RxIMU` from `brilliant_msg`, the updated library handles decoding automatically.

---

## 5. Breaking change — `TxTextSpriteBlock`

The `text` argument has been removed from the constructor. Use `createTextSprites(text)` instead, which returns a `List<TxSprite>` that you send individually.

```dart
// Before
final block = TxTextSpriteBlock(text: 'Hello world', ...);
await frame.sendMessage(0x0a, block.pack());

// After
final block = TxTextSpriteBlock(...);
final sprites = block.createTextSprites('Hello world');
for (final sprite in sprites) {
  await frame.sendMessage(0x0a, sprite.pack());
}
```

`maxDisplayRows` has been renamed to `maxDisplayLines`.

---

## 6. Breaking change — `TxSprite` wire format

A `compressed` flag byte (`0x00` = uncompressed) is now inserted at header offset 5, shifting `bpp` to offset 6 and `num_colors` to offset 7.

**This is a wire-format change.** The host-side `TxSprite` and the device-side `sprite.lua` / `image_sprite_block.lua` must be updated together. If you use the bundled Lua libraries from `brilliant_msg`, they are already updated — just ensure you re-upload them to the device. If you have copied or customised the Lua libraries, update them to match the new format.

---

## 7. New — `BrilliantDeviceType`

Device type is now detected automatically at connection time by probing for the Halo audio characteristic.

```dart
import 'package:brilliant_ble/brilliant_bluetooth.dart';

final device = await BrilliantBluetooth.connect(scannedDevice);

if (device.type == BrilliantDeviceType.halo) {
  print('Connected to Halo');
} else if (device.type == BrilliantDeviceType.frame) {
  print('Connected to Frame');
}
```

---

## 8. New — `TxTextPage` with layout support

`TxTextPage` replaces manual sprite layout for text rendering and supports both display shapes:

```dart
import 'package:brilliant_msg/brilliant_msg.dart';

// For Frame's rectangular display
final layout = RectangularTextLayout(width: 640, height: 400, fontSize: 36);

// For Halo's circular display
final layout = CircularTextLayout(width: 256, height: 256, fontSize: 24);

final page = TxTextPage(layout: layout, text: 'Hello from Halo!');
final pageData = await page.rasterizeNextPage();
if (pageData != null) {
  await frame.sendMessage(0x0a, pageData.pack());
  for (final sprite in pageData.rasterizedSprites) {
    await frame.sendMessage(0x0a, sprite.pack());
  }
}
```

---

## 9. New — `RxClick` for Halo button events

Halo sends single, double, and long-press click events:

```dart
import 'package:brilliant_msg/brilliant_msg.dart';

final rxClick = RxClick();
final clickQueue = await rxClick.attach(frame);

final click = await clickQueue.get();
if (click == ClickType.single) print('single click');
if (click == ClickType.double_) print('double click');
if (click == ClickType.long) print('long press');

rxClick.detach(frame);
```

---

## 10. New - Device behavior

Halo starts with its display in `power_save` mode to conserve power, unlike Frame which started with the display enabled. Programs that use Halo's display should call `frame.display.power_save(false)`. Draw calls won't fail if the display is in power-save mode, but they won't be shown.