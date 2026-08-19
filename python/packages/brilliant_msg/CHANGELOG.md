## 7.1.0

True-up against Halo firmware 0.8.8.

* `tap.lua` forwards Halo's native tap kind (`'single'`/`'double'`/`'triple'`) as a payload byte (1/2/3); on Frame the bare flag byte is still sent per tap
* `RxTap` emits the native kind directly when present (Halo 0.8.8 fires one callback per gesture, so timing aggregation would have under-counted); timing aggregation remains the Frame fallback
* `plain_text.lua` synced with the Halo-aware version: on Halo the palette offset maps to the firmware default palette's RGB value (Halo's `frame.display.text` takes an RGB color)
* Sprite wire-format comments corrected to include the `compressed` byte
* `openai_realtime` example wraps text for Halo's Dogica 8px font (30 chars/line, was 21 for the old FreeMono font)

## 7.0.0

* First release of `brilliant-msg`, renamed from `frame-msg`; replace `uv add frame-msg` with `uv add brilliant-msg`
* `FrameMsg` renamed to `BrilliantMsg`; update imports from `frame_msg` to `brilliant_msg`
* Adds support for Brilliant Labs Halo in addition to Brilliant Labs Frame

## 6.0.0

* Added Halo device support across all message types, Lua libraries, and examples
* New `halo_emulator` sibling package — a Lua 5.3 emulator for testing Halo apps without hardware

### Breaking changes

* **`data.lua` — queue-based message ordering**: the Frameside main loop now uses an ordered queue instead of a keyed block table, guaranteeing messages are processed in arrival order. `process_raw_items()` now returns a list of `(flag, raw_bytes)` pairs instead of updating `app_data` via registered parsers. The `app_data_block`, `app_data`, and `parsers` tables have been removed. ACK bytes (`\x01\x00\x00` for success, `\x01\x00\x01` for error) are now sent back to the host after each message is enqueued, enabling `send_data(await_data=True)` in `frame-ble 2.0.0` to use receiver-paced flow control. Existing Lua `frame_app.lua` files that called `data.process_raw_items()` and dispatched via `data.app_data` or registered `data.parsers` must be updated.
* **`imu.lua`**: IMU data is now packed as 6 × `float32` (was 6 × `int16`). Frame accelerometer values are divided by 4096 to convert raw 14-bit integers to g-force; Halo uses a different axis mapping and scale factor (÷1000). Any Lua code that reads the packed IMU bytes directly must be updated.
* **`RxIMU`**: `IMUData`, `IMURawData`, and `SensorBuffer` all use `float` (was `int`). `unpack('<6f', ...)` replaces `unpack('<6h', ...)`.
* **`TxTextSpriteBlock`**: `text` has been removed from the constructor (it remains as a deprecated no-op field). Call `create_text_sprites(text)` to obtain a `List[TxSprite]` — callers decide how many lines to send and when. `pack()` now emits a 6-byte header `[0xFF, width_hi, width_lo, line_height_hi, line_height_lo, max_display_lines]` — the previous header included per-sprite x/y offset tables. `max_display_rows` renamed to `max_display_lines`.
* **`TxSprite` wire format**: a `compressed` flag byte (`0x00` = uncompressed) has been inserted at header offset 5, shifting `bpp` to offset 6 and `num_colors` to offset 7. The matching `sprite.lua` and `image_sprite_block.lua` have been updated accordingly.

### Non-breaking changes and additions

* `sprite.lua` / `image_sprite_block.lua`: palette assignment now uses integer indices (0–15) on Halo and color-name strings on Frame, via `frame.HARDWARE_VERSION` detection
* `text_sprite_block.lua`: simplified scrolling using `table.remove`; `line_height` uint16 in header replaces per-sprite x/y offsets
* `audio.lua`: `MTU` reduced by 1 byte to reserve space for the leading flag byte
* `FrameMsg.print_short_text()`: device-aware — uses `frame.display.clear()` + offset text on Halo, `frame.display.text(…,1,1)` on Frame
* `TxSprite.from_indexed_png_bytes()`: improved palette size detection for programmatically-created PNGs where Pillow does not encode `bits` metadata
* New examples: `speaker_lc3.py` (send LC3 audio to Halo speaker), `sound_effects.py` (SFXR sound effects), `audio_stream.py` (real-time audio streaming)
* Project migrated to `uv` workspace; use `uv add frame-msg` to install

## 5.2.1

* Fixed RxAudio.to_wav_bytes() to correctly handle Frame's signed 8-bit samples

## 5.2.0

* Fixed audio.lua to allow caller to specify desired sample rate and bit depth
* Changed default to audio recording to 8kHz, 8-bit (from 8kHz, 16-bit) due to bandwidth requirements

## 5.1.1

* Corrected new defaults for auto exposure algorithm to match firmware v25.080.0838 also in `camera.lua`

## 5.1.0

* Added `TxSpriteCoords` message for indicating the placement of a sprite at specified coordinates using a palette offset.

## 5.0.3

* Fixed Python version dependency issue - numpy 2.2.3 requires Python >= 3.10, updated project Python version minimum from 3.7 to 3.10.

## 5.0.2

* Docs: added ReadTheDocs API Reference and updated README

## 5.0.1

* Corrected new defaults for auto exposure algorithm to match firmware v25.080.0838

## 5.0.0

* Added support for `rgb_gain_limit` parameter to cap maximum per-channel gain for Frame camera

## 4.2.0

* Corrected `pyproject.toml` to include existing dependencies on `lz4`, `numpy`, `pillow`, `frame-ble`

## 4.1.0

* Updated camera exposure defaults. Added Rx classes for subscribing to auto exposure results and metering data.

## 4.0.0

* Allow multiple Rx classes to register for Frame data responses and specify their msg_code filter.

## 3.0.0

* Initial version of `FrameMsg` wrapper for FrameBle with added lifecycle and convenience functions for loading standard Lua helpers
* Reworked receive (Rx) handlers to attach and detach from the data response stream (only one Rx listener supported at the moment)
* Added `RxAudio` and `audio.lua` for handling streaming audio from Frame

## 2.2.0

* Added `RxTap` and the corresponding `tap.lua` library to receive taps and multi-taps from Frame

## 2.1.0

* Added support for lz4 compression of sprites and image sprite blocks
* Modified acknowledgement byte from data handler to return 0 for successful processing and 1 for error
* Set guidance in comments for photo capture resolution to 256-720 - low values for resolution near 100 cause issues with the subsequent photo capture

## 2.0.0

* Breaking: removed redundant `msg_code` attribute from Tx classes - pass the `msg_code` independently to `frame.send_message()`

## 1.0.1

* Fixed bug in image sprite block packing.
  TxSprite, TxImageSpriteBlock, RxPhoto available.

## 1.0.0

* First PyPI package release. TxSprite available, most Tx/Rx types unavailable.

## 0.1.0

* Initial version adapted from [the Flutter implementation](https://pub.dev/packages/frame_msg)
