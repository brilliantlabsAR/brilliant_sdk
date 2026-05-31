# Halo Emulator

A Python package that emulates the [Brilliant Labs Halo](https://brilliant.xyz/) smart glasses runtime, allowing developers to run and test Lua scripts on a virtual device — no hardware required.

## Overview

Halo glasses run user scripts in an on-device **Lua 5.3 VM** and expose a rich `frame.*` API covering display, Bluetooth, IMU, buttons, file I/O, audio, compression, and system control. The emulator embeds the same Lua 5.3 runtime ([lupa](https://github.com/scoder/lupa)) and replaces all `frame.*` calls with Python stubs, rendering display output to a 256×256 pixel buffer.

Key features:

- **Full Lua 5.3 runtime** — run unmodified Lua scripts
- **Virtual 256×256 display** — all drawing primitives, palette, text, and bitmap ops
- **Event injection** — trigger BLE data, button presses, and IMU taps from Python
- **Test-friendly** — inspect the framebuffer as a PIL Image and capture BLE sends
- **Interactive REPL** — `halo-emulator ./app/` opens a live pygame window and Python REPL
- **Sandboxed filesystem** — `frame.file.*` operations run against a real directory

## Installation

```bash
uv add halo-emulator
```

### Installing from the SDK repo

When working inside the full `brilliant_sdk` repo checkout, install all three
sibling packages as editable installs so the examples always use the local
`brilliant_msg` and `brilliant_ble` rather than whatever version is on PyPI:

```bash
cd python
uv sync --all-packages
```

The workspace configuration in `python/pyproject.toml` ensures `brilliant-ble` and
`brilliant-msg` resolve to the local packages rather than PyPI.

Dependencies: `lupa`, `numpy`, `pillow`, `lz4`, `pygame`

## Quick Start

### Running a Lua script

```python
from halo_emulator import HaloEmulator

emu = HaloEmulator(sandbox_dir='./my_app')
emu.load_directory('./my_app')   # copies .lua files into the sandbox
emu.start('main.lua')            # runs in a background thread

# ... do stuff ...

emu.stop()
```

### Using as a context manager

```python
with HaloEmulator(sandbox_dir='./my_app') as emu:
    emu.load_directory('./my_app')
    emu.start('main.lua')
    emu.wait(timeout=5.0)
    img = emu.get_framebuffer()
    img.save('output.png')
```

### Interactive REPL

```bash
halo-emulator ./my_app/
```

Opens a 512×512 pygame window (2× scaled) and drops into a Python REPL with `emulator` in scope. Keyboard shortcuts in the window:

| Key | Action |
|-----|--------|
| `Space` | Button single click |
| `D` | Button double click |
| `L` | Button long press |
| `T` | IMU tap |

```bash
halo-emulator ./my_app/ --script frame_app.lua   # specify entry point
halo-emulator ./my_app/ --headless               # REPL only, no window
halo-emulator --sandbox /tmp/sandbox             # explicit sandbox dir
```

## API Reference

### `HaloEmulator(sandbox_dir=None, *, print_handler=print)`

| Parameter | Description |
|-----------|-------------|
| `sandbox_dir` | Directory used as the Lua filesystem root. Created automatically if `None`. |
| `print_handler` | Called with each Lua `print()` line. Pass `None` to suppress output. |

### Lifecycle

```python
emu.load_file('frame_app.lua')      # copy a single file into the sandbox
emu.load_directory('./lua/')        # copy all .lua files from a directory
emu.start(script_name='main.lua')   # start Lua VM in background thread
emu.wait(timeout=5.0)               # block until script exits (raises on Lua error)
emu.stop()                          # signal VM to stop, join thread
emu.is_running()                    # → bool
emu.get_error()                     # → Exception | None
```

`HaloEmulator` also supports `__enter__`/`__exit__` for use as a context manager.

### Event Injection

These methods are thread-safe and can be called from any Python thread:

```python
emu.inject_bluetooth_data(b'\x0a\x00\x05Hello')  # triggers frame.bluetooth.receive_callback
emu.inject_button_single()                         # triggers frame.button.single callback
emu.inject_button_double()                         # triggers frame.button.double callback
emu.inject_button_long()                           # triggers frame.button.long callback
emu.inject_imu_tap()                               # triggers frame.imu.tap_callback
```

Events are dispatched from within the Lua thread (inside `frame.sleep()`), so Lua callbacks fire safely.

### Configuration

```python
emu.set_battery_level(42)                          # frame.battery_level() → 42
emu.set_battery_charging(True)                     # frame.battery_charging() → True
emu.set_imu_direction(pitch=15.0, roll=-5.0, heading=0.0)  # frame.imu.direction()
emu.set_imu_raw(compass=(10, 20, 30), accel=(0, 0, 1000))  # frame.imu.raw()
```

### Observation

```python
img = emu.get_framebuffer()          # → PIL.Image.Image (256×256 RGBA)
img.save('frame.png')

sent = emu.get_bluetooth_sent()      # → list[bytes] (all frame.bluetooth.send() calls)
emu.clear_bluetooth_sent()           # reset the captured list
```

## Writing Tests

```python
import time
import pytest
from halo_emulator import HaloEmulator

@pytest.fixture
def emulator(tmp_path):
    emu = HaloEmulator(sandbox_dir=tmp_path, print_handler=None)
    yield emu
    if emu.is_running():
        emu.stop()

def test_display_shows_text(emulator, tmp_path):
    (tmp_path / 'main.lua').write_text("""
        frame.display.clear(0)
        frame.display.text('Hello', 10, 10, 0xFFFFFF)
    """)
    emulator.start()
    emulator.wait(timeout=3.0)

    img = emulator.get_framebuffer()
    pixels = list(img.getdata())
    bright = sum(1 for r, g, b, a in pixels if r + g + b > 30)
    assert bright > 0

def test_ble_receive_triggers_callback(emulator, tmp_path):
    (tmp_path / 'main.lua').write_text("""
        frame.bluetooth.receive_callback(function(data)
            frame.bluetooth.send(data)  -- echo back
        end)
        frame.sleep(5.0)
    """)
    emulator.start()
    time.sleep(0.1)                              # let Lua register the callback

    emulator.inject_bluetooth_data(b'\x42\x01')
    time.sleep(0.3)

    assert b'\x42\x01' in emulator.get_bluetooth_sent()

def test_button_press_fires_callback(emulator, tmp_path):
    (tmp_path / 'main.lua').write_text("""
        frame.button.single(function()
            frame.bluetooth.send('\x01')
        end)
        frame.sleep(5.0)
    """)
    emulator.start()
    time.sleep(0.1)
    emulator.inject_button_single()
    time.sleep(0.2)
    assert b'\x01' in emulator.get_bluetooth_sent()
```

## Running Tests

Both `halo_emulator` and `brilliant_msg` have automated tests that run without hardware.

```bash
cd python

# Install all test dependencies
uv sync --all-packages --all-extras

# Run brilliant_msg tests (message packing/parsing, WAV conversion, handler dispatch)
uv run pytest packages/brilliant_msg/tests/

# Run halo_emulator tests (Lua VM, display, events)
uv run pytest packages/halo_emulator/tests/

# Run both together
uv run pytest packages/brilliant_msg/tests/ packages/halo_emulator/tests/
```

The `brilliant_ble` package has hardware integration tests that require a connected Frame device:

```bash
# Requires a connected Frame device over BLE
uv run pytest packages/brilliant_ble/tests/test_ble.py

# Standalone hardware scripts (not pytest):
uv run python packages/brilliant_ble/tests/test_display.py
```

## Supported `frame.*` API

### System
`sleep`, `light_sleep`, `standby`, `yield`, `on_wakeup`, `stay_awake`, `reboot`, `battery_level`, `battery_voltage`, `battery_charging`, `wakeup_source`, `get_eui`

Constants: `HARDWARE_VERSION` (`"EMULATOR"`), `FIRMWARE_VERSION`, `GIT_TAG`, `SE_REVISION`

### Time — `frame.time.*`
`utc`, `zone`, `date`

### File — `frame.file.*`
`open`, `remove`, `remove_all`, `rename`, `listdir`, `mkdir`

File operations are sandboxed to the `sandbox_dir`. `require()` is overridden to load modules from the sandbox directory.

### Button — `frame.button.*`
`single(func)`, `double(func)`, `long(func)` — register/clear callbacks

### Bluetooth — `frame.bluetooth.*`
`is_connected`, `address`, `max_length`, `send`, `receive_callback`

### IMU — `frame.imu.*`
`tap_callback(func)`, `direction()`, `raw()`, `config(options)`

### Compression — `frame.compression.*`
`process_function(func)`, `decompress(data, block_size)` — LZ4 decompression

### Display — `frame.display.*`

| Function | Description |
|----------|-------------|
| `assign_color(index, r, g, b)` | Set palette entry (index 1-16 or name) |
| `assign_color_ycbcr(index, y, cb, cr)` | Set palette entry via YCbCr |
| `text(text, x, y, color)` | Draw text at position (1-based, 0xRRGGBB) |
| `char(codepoint, x, y, color)` | Draw a single Unicode character |
| `set_font(font_id, size, scale)` | Set current font |
| `get_font_list()` | List available fonts |
| `set_pixel(x, y, color)` | Set a single pixel |
| `line(x0, y0, x1, y1, color)` | Draw a line |
| `rect(x, y, w, h, color, filled)` | Draw a rectangle |
| `circle(cx, cy, r, color, filled)` | Draw a circle |
| `polygon(points, color)` | Draw a polygon |
| `bitmap(x, y, width, format, offset, data, [opts])` | Draw indexed/RGB bitmap |
| `clear(color)` | Fill display with color |
| `show([enable])` | No-op — Halo draws directly to display memory (no buffer flip) |
| `width()` / `height()` | Returns 256 |
| `brightness([value])` | Get/set brightness (0-100) |
| `set_brightness(v)` / `get_brightness()` | Brightness -2..2 |
| `set_pan(x, y)` / `get_pan()` | Pan offset (-50..50) |
| `power_save(enable)` | No-op in emulator |

Palette color names: `VOID`, `WHITE`, `GREY`, `RED`, `PINK`, `DARKBROWN`, `BROWN`, `ORANGE`, `YELLOW`, `DARKGREEN`, `GREEN`, `LIGHTGREEN`, `NIGHTBLUE`, `SEABLUE`, `SKYBLUE`, `CLOUDBLUE`

### Speaker — `frame.speaker.*` *(no-op)*
`start`, `play`, `volume`, `stop` — accepted but produce no audio output.

### Microphone — `frame.microphone.*` *(no-op)*
`start`, `read`, `gain`, `stop`, `aad_callback` — accepted; `read()` returns `nil`.

## Architecture Notes

The Lua VM runs in a dedicated `threading.Thread`. Python never calls into lupa from another thread. Instead:

1. Python writes `Event` objects to a thread-safe `queue.Queue`
2. The Lua stub for `frame.sleep(n)` polls the queue in a 1 ms loop for `n` seconds
3. Any queued events are dispatched (Lua callbacks fired) from within the Lua thread

This means Lua callback dispatch is always safe, and Python injection calls (`inject_*`) return immediately.

`frame.yield()` performs a single queue drain without sleeping.

`emulator.stop()` sets a `threading.Event` that `frame.sleep()` checks, then raises an internal exception that propagates through lupa and terminates the Lua loop cleanly.

### Binary string encoding

The lupa runtime is configured with `encoding="latin-1"`. Lua strings are byte sequences; latin-1 is the only 1:1 encoding between bytes 0x00-0xFF and Python `str`. This is critical for BLE payloads that contain arbitrary bytes.
