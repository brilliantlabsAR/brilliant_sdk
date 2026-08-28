## 2.1.0

True-up against Halo firmware 0.8.9 (`frame.FIRMWARE_VERSION` now reports
`"0.8.9-emulator"`).

### Changed

* `frame.speaker` is no longer a pure no-op: `start()` validates its config
  as firmware 0.8.9 does — sample rate 8000/16000, channels 1/2, bit depth
  16 only, LC3 duration 750/1000 and bitrate a multiple of 8000 up to 96000,
  volume 0-100, and the per-stream `gain` (0-12) and `budget` (10-100)
  loudness fields added in 0.8.9. `play()` errors when the speaker is not
  started, `volume(v)` errors when not started or out of range (it clamped
  before), and `stop()` stays a no-op when already stopped. Still no audio
  output

## 2.0.1

### Fixed

* `print_handler` now always receives a `str`, as documented. Lua `print()` is
  emulated faithfully: each argument is passed through `tostring` and the
  results are tab-joined — previously the handler was installed as Lua's
  `print` directly and could receive raw values (numbers, tables, or the
  Python stop exception caught by an app's `pcall`)
* Installs on Python 3.14: the `pygame` dependency (no CPython 3.14 wheels)
  is replaced by the drop-in `pygame-ce` fork on Python >= 3.14 via
  environment markers; environments on Python <= 3.13 are unchanged

## 2.0.0

True-up against Halo firmware 0.8.8 (`frame.FIRMWARE_VERSION` now reports
`"0.8.8-emulator"`). Breaking where the firmware itself changed.

### Breaking

* Lua runtime upgraded from 5.3 to **Lua 5.4** (`lupa.lua54`), matching the firmware's vendored Lua 5.4.6
* `frame.on_wakeup()` removed (removed from firmware in 0.8.8). `standby()` resumes in place; `light_sleep()` restarts the Lua VM and re-runs the entry script from the top on wake
* `frame.sleep()` with no argument (or 0) now deep-sleeps: the emulator stops, matching the firmware's shutdown behavior
* `frame.imu.tap_callback` handlers now receive the gesture kind (`'single'`/`'double'`/`'triple'`); `inject_imu_tap()` takes an optional kind and fires one callback per gesture
* Default display palette replaced with the firmware's RGB defaults (the previous values were Frame-era approximations)
* `frame.display.assign_color`/`assign_color_ycbcr` integer indices are 0-based (0–15) as on firmware; they were treated as 1-based before
* `frame.display.bitmap` `palette_offset` no longer wraps: source index 0 is transparent, offset indices past 15 are dropped; `color_format` must be 0, 2, 4 or 16; the offset also applies to custom `palette_data`
* `frame.display.set_font` validates like firmware: font ids 0 (Dogica) / 1 (DogicaBold), size a positive multiple of 8; `get_font_list()` returns `{[0]="Dogica", [1]="DogicaBold"}`
* `frame.microphone.start` validates its config (sample rate 8000/16000, bit depth 8/16, LC3 duration 750/1000) and `read()` follows firmware semantics: `nil` when stopped, `""` when no data, partial even-sized reads, 4096-byte cap
* `frame.time.zone` validates and normalises offsets, applies the sign to minutes, and the setter returns the stored zone; `frame.time.date()` applies the zone offset to UTC (host timezone no longer leaks in) and gains `"day of year"` and `"is daylight saving"` keys (weekday is 0=Sunday)
* `require()` follows standard Lua semantics as on firmware: modules cached in `package.loaded`, the module's own value returned (`true` when it returns nothing)

### Added

* Text rendering with the firmware's Dogica/DogicaBold 8 px pixel fonts, converted from the firmware sources — pixel-accurate output including the top-of-cap-box `y` anchor
* `frame.sound.*`: `play`, `play_async`, `stop`, `is_playing` with the firmware's sfxr presets, option validation and timing (no audio synthesized)
* `frame.imu.tap_config([options])` with the firmware's defaults and validation
* `frame.microphone.status()`, `aec()`, `voice()`, `diag()`; `HaloEmulator.inject_microphone_data()` to feed `read()`
* `frame.display.power_save()` no-arg getter (returns `true` when suspended)
* `frame.time.utc(ts)` setter echoes the timestamp back, as firmware does
* `frame.bluetooth.send('')` transmits nothing (still succeeds), as firmware does
* `HaloEmulator.set_wakeup_source()`; CLI keys `2`/`3` inject double/triple taps

### Fixed

* Brightness getters now mirror firmware quirks: `get_brightness()` returns 0 for any percent that is not exactly 10/25/50/75/100
* Coordinates are low-clamped to 1 (no high clamp), matching the firmware's clipping
* Note: the 1.0.0 notes referred to the adapter as `EmulatorFrameMsg` and claimed sprite support; the class is `EmulatorBrilliantMsg`, and sprites render via `frame.display.bitmap()` (there is no separate sprite API on Halo)

## 1.0.0

* Initial release of the `halo_emulator` package — a Lua 5.3 emulator for [Brilliant Labs Halo](https://brilliant.xyz/) smart glasses
* Full Lua 5.3 runtime via [lupa](https://github.com/scoder/lupa); run unmodified Halo Lua scripts without hardware
* Virtual 256×256 pixel display with all `frame.display.*` primitives: text, bitmap, sprites, palette assignment, brightness, power save, and clear
* `frame.*` API stubs covering: display, Bluetooth, IMU, buttons (`frame.imu.tap_callback`), file I/O (`frame.file.*`), audio (`frame.microphone.*`, `frame.speaker.*`), LZ4 compression, and system control (`frame.sleep`, `frame.HARDWARE_VERSION`, `frame.FIRMWARE_VERSION`, etc.)
* `HaloEmulator` class: programmatic control of the virtual device — inject BLE data, trigger button presses and IMU taps, inspect the framebuffer as a PIL `Image`, and capture outbound BLE sends
* `EmulatorFrameMsg` adapter: drop-in replacement for `FrameMsg` for testing `frame_msg`-based host apps against the emulator without any BLE connection
* `VideoRecorder`: captures emulator display output as a video file
* Interactive REPL mode: `halo-emulator ./app/` opens a live pygame window and Python prompt
* Sandboxed filesystem: `frame.file.*` operations run against a real directory on disk
* Test-friendly design: inspect framebuffer state, assert on BLE sends, inject events from pytest
* CLI entry point: `halo-emulator`
* Dependencies: `lupa`, `numpy`, `pillow`, `lz4`, `pygame`
