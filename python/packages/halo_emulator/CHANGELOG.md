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
