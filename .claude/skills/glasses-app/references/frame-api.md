# On-device `frame.*` Lua API — condensed reference

The glasses run Lua 5.4; your device-side app uses the `frame.*` API. This is
the working subset — full references:
https://docs.brilliant.xyz/halo/halo-sdk-lua/ (Halo, includes a
Halo-vs-Frame differences table) and
https://docs.brilliant.xyz/frame/frame-sdk-lua/ (Frame). The most complete
in-repo source is `python/packages/halo_emulator/README.md`.

Identify the device: `frame.HARDWARE_VERSION` → `'Frame'`, `'halo'`, or
`'EMULATOR'`. Also: `FIRMWARE_VERSION`, `GIT_TAG`, `frame.battery_level()`.

## System & power
`frame.sleep(s)` (no arg = deep sleep), `frame.standby([s])` (Halo: resumes in
place), `frame.light_sleep([s])` (Halo: VM restarts on wake — check
`frame.wakeup_source()` at script top), `frame.stay_awake(bool)`,
`frame.reboot()`, `frame.yield()`.

## Display — `frame.display.*`

Frame: 640×400, **buffered** — nothing appears until `frame.display.show()`.
Halo: 256×256 round, draws **immediately**; call
`frame.display.power_save(false)` at app start; `show()` is a no-op.

Common: `text(str, x, y, [color])` (1-based coords),
`clear([color])` (Halo), `bitmap(x, y, width, format, offset, data)`
(format = 2/4/16 colors; Halo also 0 = RGB888), `assign_color(idx, r, g, b)`
(16-entry palette), `width()`, `height()`.

Halo extras: `set_pixel`, `line`, `rect`, `circle`, `polygon`,
`set_font(id, size, scale)` (0 = Dogica, 1 = DogicaBold, size multiple of 8),
`char`, `brightness`, `set_pan`. Halo palette names: `VOID WHITE GREY RED
PINK DARKBROWN BROWN ORANGE YELLOW DARKGREEN GREEN LIGHTGREEN NIGHTBLUE
SEABLUE SKYBLUE CLOUDBLUE`.

## Bluetooth — `frame.bluetooth.*`
`send(data)` (host receives on the data channel; ≤ `max_length()` bytes),
`receive_callback(fn)`, `is_connected()`, `address()`. The `data` std lib
wraps this for chunked message accumulation — use it rather than raw
callbacks in apps.

## Input
- Both: `frame.imu.tap_callback(fn)` — on Halo the callback receives
  `'single'` / `'double'` / `'triple'`; `frame.imu.tap_config([opts])` tunes
  detection (Halo).
- Halo button: `frame.button.single(fn)` / `.double(fn)` / `.long(fn)`.

## IMU — `frame.imu.*`
`direction()` → `{pitch, roll, heading}` (heading is computed host-side —
`0.0` on device; use the SDK calibration/heading helpers),
`raw()` → raw accel/compass, `config(opts)`.

## Camera — `frame.camera.*`
Capture is normally driven from the host via `TxCaptureSettings` + the
`camera` std lib, which handles exposure/metering options and streams the
JPEG back: `camera.capture_and_send(settings)` blocks until the image is sent;
`camera.start_capture(settings)` then `camera.send_pending(n)` each loop pass
(until it returns false) sends it without blocking, so other traffic such as
mic audio keeps flowing (see the `audio_video` examples). Manual use:
`frame.camera.capture{...}` / `read(n)` — see the docs-site reference. Halo
adds libmpix image-processing pipelines (docs site).

## Audio (Halo)
- `frame.sound.play(preset, [opts])` — sfxr presets `pickup laser explosion
  powerup hit jump blip`; `play_async`, `stop`, `is_playing`.
- `frame.speaker.*` — LC3 playback: `start`, `play(frames)`, `volume`, `stop`.
- `frame.microphone.*` — `start{sample_rate=…, bit_depth=…}`, non-blocking
  `read(n)` (`nil` stopped / `''` no data), `stop`, `gain`, `aec`, `voice`,
  `aad_callback` (audio activity detection wake).

## Files & misc
`frame.file.open(name, mode)` / `remove` / `rename` / `listdir` / `mkdir`;
`require('lib.min')` loads uploaded libs. `frame.compression.decompress(data,
block_size)` (LZ4). `frame.time.utc()`, `frame.time.date()`.

## App-loop conventions

- Wrap the loop body in `pcall`; `print(err)` on failure — the host's print
  handler is the only visibility into device errors. The host's break signal
  surfaces as an error here: exit the loop on it.
- `frame.sleep(0.1)` in the loop; `collectgarbage('collect')` after big
  messages (~30 KB heap).
- Signal readiness with a `print()` once the loop is about to start —
  `start_frame_app()` waits for it.
