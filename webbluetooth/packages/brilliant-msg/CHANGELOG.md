## Unreleased

* Added the device-side `text_page.lua` / `text_page.min.lua` library (`StdLua.TextPageMin`). It renders `TxTextPage` pages at their per-line x/y offsets, so `CircularTextLayout` pages follow Halo's round display; `text_sprite_block.lua` stacks lines by `line_height` and ignores those offsets. Device-side Lua is now identical across the Python, Flutter and WebBluetooth SDKs (`tools/check_lua_parity.py`)

## 3.0.0

* `brilliant-ble` is no longer bundled into this package's output — it is now an
  external dependency resolved from `node_modules` at install time, the same way the
  Python and Dart SDKs resolve theirs. Previously every release snapshotted a copy of
  `brilliant-ble`, which meant fixes to it could not reach users without republishing
  this package, and importing both packages directly produced two separate copies of
  the same classes (so `instanceof` comparisons across the boundary failed)
* Breaking only for consumers loading the UMD build via a plain `<script>` tag: they
  must now load `brilliant-ble` first and expose it as the `brilliantBle` global.
  Bundler and ESM consumers are unaffected — npm installs `brilliant-ble`
  automatically as a declared dependency
* `brilliant-ble` floor raised to `^1.1.0`. This package calls
  `drainPrintChannel()`, which only exists from `brilliant-ble` 1.1.0; while
  `brilliant-ble` was bundled the range was cosmetic, but now that it resolves at
  install time the floor has to be accurate
* TypeScript pinned to an exact version so declaration output cannot shift with a
  minor compiler release

## 2.1.0

True-up against Halo firmware 0.8.8.

* `tap.lua` forwards Halo's native tap kind (`'single'`/`'double'`/`'triple'`) as a payload byte (1/2/3); on Frame the bare flag byte is still sent per tap
* `RxTap` emits the native kind directly when present (Halo 0.8.8 fires one callback per gesture, so timing aggregation would have under-counted); timing aggregation remains the Frame fallback
* `CircularTextLayout` docs use Halo's real display size (256×256, was 640×400)
* Sprite wire-format comments corrected to include the `compressed` byte
* `npm test` now builds the dist bundle it tests (and the linked `brilliant-ble`, if needed) via a `pretest` script — previously the mag-calibration tests failed in a fresh checkout with "MagCalibration is not a constructor"

## 2.0.0

* First release of `brilliant-msg`, renamed from `frame-msg`; update imports accordingly
* Adds support for Brilliant Labs Halo in addition to Brilliant Labs Frame

## 1.1.0

* Added Halo device support
* New `RxClick` class and `ClickType` enum (`SINGLE`, `DOUBLE`, `LONG`) for Halo click events (msg code `0x0B`)
* New `TxTextPage` with `TextLayout` hierarchy — `RectangularTextLayout` for Frame, `CircularTextLayout` for Halo's circular display; supports multi-page text, per-line x/y positioning
* `printShortText()` now uses the correct display command per device type (Halo uses `frame.display.clear()` before rendering text)
* Updated Lua libraries (synced from Flutter SDK):
  * `data.lua` — queue-based message accumulation; ACK bytes changed to `\x01\x00\x00`/`\x01\x00\x01` so `sendData(awaitData:true)` resolves correctly
  * `imu.lua` — packs 6 `float32` values (was `int16`); Frame and Halo use different axis scaling/mapping via `frame.HARDWARE_VERSION`
  * `sprite.lua` / `image_sprite_block.lua` — `compressed` flag byte added to sprite header; Halo uses integer palette indices, Frame uses colour name indices
  * `text_sprite_block.lua` — new header format: `lineHeight` (uint16) replaces per-sprite x/y offsets; simplified sprite accumulation
  * `audio.lua` — `MTU = max_length() - 1` (reserves 1 byte for the flag)
* `RxIMU` now decodes 6 `float32` values (was 6 `int16`); `SensorBuffer` and `IMUData` updated to use `number` (floating-point)
* `TxTextSpriteBlock` — updated API: `text` removed from constructor; `createTextSprites(text)` returns `TxSprite[]` with fixed `lineHeight`; `pack()` emits 6-byte header matching updated Lua
* `frame-ble` dependency updated to local package reference

## 1.0.0

* Breaking: added Options interfaces for all Rx and Tx class constructors for consistency
* Breaking: updated all "flag" references in JS and Lua to msgCode and msg_code for consistency
* Updated frame-ble dependency to 0.3.1
* Example: fixed an off-by-one bug in sprite-move.js
* Cleaned up some comments

## 0.3.1

* Added `toPngBytes()` to `TxSprite` for debugging and visualization of quantized images
* Fixed a bug in `TxSprite.fromImageBytes()` that was not correctly mapping images to the quantized palette
* Example: updated various TxSprite examples to display the source and quantized images

## 0.3.0

* Updated to frame-ble dependency to 0.3.0
* Added workaround to `package.json` for GitHub Pages deployment error after upgrade
* Added `EXAMPLES.md` file and generator script for example agent context
* Examples/Demo:
  * Added log display and capture console output
  * Place image and text outputs from examples in right pane
  * Remove Pixelify Sans font, just use Press Start 2P

## 0.2.3

* Rebuilt with frame-ble 0.2.2 dependency

## 0.2.2

* Rebuilt with frame-ble 0.2.1 dependency

## 0.2.1

* Republished with package lock updated

## 0.2.0

* Improved support for sprites, audio

## 0.1.0

* Initial version ported from Python, partial support for Tx/Rx classes and examples
