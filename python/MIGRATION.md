# Migration Guide — Python SDK

This guide covers migrating from the `frame-ble` / `frame-msg` packages to `brilliant-ble` / `brilliant-msg`.

---

## 1. Package renames

| Old package | New package | New version |
|-------------|-------------|-------------|
| `frame-ble` | `brilliant-ble` | 3.0.0 |
| `frame-msg` | `brilliant-msg` | 7.0.0 |

```bash
# Remove old packages
uv remove frame-ble frame-msg

# Install new packages
uv add brilliant-ble brilliant-msg

# Or install the meta-package (installs both)
uv add brilliant-sdk
```

---

## 2. Import and class renames

`FrameBle` is now `BrilliantBle` and `FrameMsg` is now `BrilliantMsg`.

```python
# Before
from frame_ble import FrameBle
from frame_msg import FrameMsg, TxSprite, RxPhoto, StdLua

# After
from brilliant_ble import BrilliantBle, BrilliantDeviceType
from brilliant_msg import BrilliantMsg, TxSprite, RxPhoto, StdLua
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
- After each message is enqueued, an ACK is sent back to the host (`\x01\x00\x00` success / `\x01\x00\x01` error). If you use `send_data(await_data=True)` on the host side, the call will now wait for this ACK before returning, enabling receiver-paced flow control.

---

## 4. Breaking change — IMU data type

`RxIMU`, `IMUData`, `IMURawData`, and `SensorBuffer` now use `float` instead of `int`.

The Lua library `imu.lua` now packs 6 × `float32` (was 6 × `int16`). If you unpack IMU bytes directly in your own code:

```python
# Before
ax, ay, az, gx, gy, gz = struct.unpack('<6h', raw_bytes[2:14])

# After
ax, ay, az, gx, gy, gz = struct.unpack('<6f', raw_bytes[2:26])
```

If you use `RxIMU` from `brilliant-msg`, the updated library handles this automatically.

---

## 5. Breaking change — `TxTextSpriteBlock`

The `text` argument has been removed from the constructor. Use `create_text_sprites(text)` instead, which returns a `list[TxSprite]` that you send individually.

```python
# Before
block = TxTextSpriteBlock(text="Hello world", ...)
await frame.send_message(0x0a, block.pack())

# After
block = TxTextSpriteBlock(...)
sprites = block.create_text_sprites("Hello world")
for sprite in sprites:
    await frame.send_message(0x0a, sprite.pack())
```

`max_display_rows` has been renamed to `max_display_lines`.

---

## 6. Breaking change — `TxSprite` wire format

A `compressed` flag byte (`0x00` = uncompressed) is now inserted at header offset 5, shifting `bpp` to offset 6 and `num_colors` to offset 7.

**This is a wire-format change.** The host-side `TxSprite` and the device-side `sprite.lua` / `image_sprite_block.lua` must be updated together. If you use the bundled Lua libraries from `brilliant-msg`, they are already updated — just ensure you re-upload them to the device. If you have copied or customised the Lua libraries, update them to match the new format.

---

## 7. New — `BrilliantDeviceType`

Device type is now detected automatically at connection time by probing for the Halo audio characteristic.

```python
from brilliant_ble import BrilliantBle, BrilliantDeviceType

ble = BrilliantBle()
await ble.connect()

if ble.type == BrilliantDeviceType.HALO:
    print("Connected to Halo")
elif ble.type == BrilliantDeviceType.FRAME:
    print("Connected to Frame")
```

---

## 8. New — Halo-only methods

```python
# Send audio data (LC3 or PCM) to the Halo audio characteristic
await ble.send_audio(data: bytearray)

# Remove main.lua from Halo and reset the Lua VM
await ble.send_remove_signal()
```
