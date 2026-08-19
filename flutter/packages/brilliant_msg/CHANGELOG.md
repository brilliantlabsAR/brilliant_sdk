## 4.1.0

True-up against Halo firmware 0.8.8.

* Added the missing `tap.lua`/`tap.min.lua` and `sprite_coords.lua`/`sprite_coords.min.lua` device libraries (present in the Python and webbluetooth SDKs)
* `tap.lua` forwards Halo's native tap kind (`'single'`/`'double'`/`'triple'`) as a payload byte (1/2/3); on Frame the bare flag byte is still sent per tap
* `RxTap` emits the native kind directly when present (Halo 0.8.8 fires one callback per gesture, so timing aggregation would have under-counted); timing aggregation remains the Frame fallback
* `plain_text.lua` synced with the Halo-aware version: on Halo the palette offset maps to the firmware default palette's RGB value (Halo's `frame.display.text` takes an RGB color)
* Sprite wire-format comments corrected to include the `compressed` byte

## 4.0.0

* First release of `brilliant_msg`, renamed from `frame_msg`; replace `frame_msg` with `brilliant_msg` in `pubspec.yaml` and update imports from `package:frame_msg/` to `package:brilliant_msg/`
* Adds support for Brilliant Labs Halo in addition to Brilliant Labs Frame

## 3.0.0

* Added Halo device support across all message types and Lua libraries

### Breaking changes

* **`TxSprite` wire format**: a `compressed` flag byte (`0x00` = uncompressed) is now inserted at header offset 5, shifting `bpp` to offset 6 and `num_colors` to offset 7. The corresponding `sprite.lua`, `image_sprite_block.lua`, and `text_sprite_block.lua` Lua libraries have been updated to match. This is a wire-format breaking change — host and device Lua must both be updated together.
* **`TxTextSpriteBlock`**: `text` removed from constructor. Call `createTextSprites(text)` to obtain a `List<TxSprite>` — callers decide how many lines to send and when. `pack()` now emits a 6-byte header (`width` uint16, `lineHeight` uint16, `maxDisplayLines` uint8) — the previous header encoded per-line x/y offsets. `maxDisplayRows` renamed to `maxDisplayLines`.
* **`RxIMU`**: `IMUData`, `IMURawData`, and `SensorBuffer` all use `double` (was `int`). The Lua library now packs 6 × `float32` (was 6 × `int16`); the Dart decoder reads them via `ByteData.getFloat32` starting at offset 2.
* **`data.lua` — queue-based message ordering**: `process_raw_items()` now returns an ordered list of `(flag, raw_block)` pairs, guaranteeing messages are processed in arrival order. The `app_data_block`, `app_data`, and `parsers` tables have been removed. ACK bytes (`\x01\x00\x00` success / `\x01\x00\x01` error) are now sent back to the host after each message is enqueued, enabling receiver-paced flow control in `FrameBle.sendData(awaitData: true)`. Existing `frame_app.lua` files that dispatched via `data.app_data` or registered `data.parsers` must be updated.
* **`imu.lua`**: 6 × `float32` instead of 6 × `int16`; hardware-version-specific axis scaling and mapping for Frame vs Halo.

### New additions

* New `TxTextPage` with `TextLayout` hierarchy:
  * `RectangularTextLayout` — standard rectangular text area for Frame
  * `CircularTextLayout` — text constrained within a circle inscribed in the canvas, ideal for Halo's round 256×256 display; chord-width calculation positions each line within the circle boundary
  * Supports multi-page text, configurable font/size/alignment
* New `RxClick` class and `ClickType` enum (`single`, `double`, `long`) for Halo button click events (msg code `0x0B`)
* Fixed: `rx/click.dart` and `tx/text_sprite_block.dart` were accidentally missing from `frame_msg.dart` barrel — both are now exported
* `sprite.lua` / `image_sprite_block.lua`: palette assignment uses integer indices (0–15) on Halo and color-name strings on Frame, selected via `frame.HARDWARE_VERSION`
* `text_sprite_block.lua`: `lineHeight` uint16 in header replaces per-sprite x/y offsets; simplified scrolling via `table.remove`
* `audio.lua`: `MTU` reduced by 1 byte to reserve space for the leading flag byte
* `RxAudio`: relaxed audio chunk length validation from a hard `assert` to a warning log entry

## 2.0.0

* Removed redundant `msgCode` from TxMsg types. `msgCode` is a transport detail provided to FrameBle at the time of message sending, and does not need to be coupled to the rich message object.

## 1.0.2

* README updates for package homepage

## 1.0.1

* Tweaked auto exposure and white balance settings / manual exposure settings / camera stdlua values further

## 1.0.0

* Updated auto exposure and white balance settings / manual exposure settings / camera stdlua to support `rgb_gain_limit` parameter in updated firmware.

## 0.0.3

* Rethrow errors caught in the data handler. Errors are printed to stdout but still rethrown, which is particularly important to make sure we don't swallow the break signal - the running Lua code needs to terminate. Other errors can still be handled by the main application loop if desired.

## 0.0.2

* Wrapped data handler processing in protected calls to report errors e.g. out-of-memory back on stdout

## 0.0.1

* Initial release, split from `simple_frame_app 4.0.2`.
