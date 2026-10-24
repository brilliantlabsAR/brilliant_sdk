## 4.3.0

* `camera.lua`, `audio.lua`: photo and audio packets carry at most 240 data bytes (less if the MTU is smaller), so each notification fits one 251-byte Bluetooth link-layer packet, including over the EATT bearers Android uses. They were sized to the MTU (up to 508 bytes), taking two link-layer packets each. From a Halo dev kit at a 15 ms interval, photos arrived faster this way: iPhone 14 48 vs 42 kB/s, Pixel 7 Pro 80 vs 75 kB/s. Sizes are read per call; `audio.lua` read the MTU once when loaded
* `camera.lua`: new non-blocking capture: `start_capture(settings)`, then `send_pending(n)` each loop pass until it returns false (`is_sending()` reports a capture in progress), so the loop can do other work between photo packets. `capture_and_send()` still blocks until the photo is sent
* `RxPhoto` accumulates the image in a `BytesBuilder`; it rebuilt a list of the whole image so far for every packet received

## 4.2.0

* Added the device-side `text_page.lua` / `text_page.min.lua` library. It renders `TxTextPage` pages at their per-line x/y offsets, so `CircularTextLayout` pages follow Halo's round display; `text_sprite_block.lua` stacks lines by `line_height` and ignores those offsets. Add `packages/brilliant_msg/lua/text_page.min.lua` to your app's `assets:` to upload it. Device-side Lua is now identical across the Python, Flutter and WebBluetooth SDKs (`tools/check_lua_parity.py`)
* `TxTextPage`: when not even one line fits the layout, `measureNextPage()` now drops the text so `hasMoreText` turns false; previously it stayed true and a paging loop never ended
* `data.lua`: a message that finished arriving while `process_raw_items()` was running could be lost. The item counter was reset after copying a fixed range, so an item queued by a receive callback during the copy was orphaned. With messages arriving back to back this dropped the last strip of about 1 image in 50. The queue now has a separate head and tail and never drops an item
* `data.lua`: the full `collectgarbage('collect')` after each batch of messages now runs on Frame only. On Halo it cost tens of milliseconds per image; Lua's incremental collector keeps the heap bounded (it peaked at 85 KB streaming 128x128 images, was 62 KB)
* Progressive sprite examples: on Halo, draw only the strip that just arrived. Halo keeps its framebuffer between draws, so redrawing every strip received so far is only needed on Frame

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
