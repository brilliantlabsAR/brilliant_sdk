---
name: glasses-app
description: Build an app for Brilliant Labs smart glasses (Halo or Frame) with this SDK, in Python, Flutter or WebBluetooth/TypeScript. Use when writing, extending or debugging a host program + device-side Lua app pair, or when asked to display something on / read sensors from the glasses.
---

# Building a glasses app

Every app is **two programs**: a host program (Python / Dart / TypeScript) and
a device-side **Lua app** running in the glasses' Lua 5.4 VM. They exchange
messages over BLE, identified by a **single-byte message code that must match
on both sides**. Get this pairing right and everything else is bookkeeping.

## Choose the path

- Just poking the device (show text, read battery, run a Lua snippet)?
  Use the `*_ble` layer alone and send raw Lua to the REPL — no Lua app
  needed. See `python/packages/brilliant_ble/examples/hello_world.py`.
- A real app (camera, audio, sprites, IMU, interaction)? Use the `*_msg`
  layer and the lifecycle below.
- Copy an existing example rather than starting blank — indexes:
  `python/packages/brilliant_msg/examples/EXAMPLES.md`,
  `flutter/packages/simple_brilliant_app/example/EXAMPLES.md`,
  `webbluetooth/packages/brilliant-msg/example/EXAMPLES.md`.

Per-SDK minimal working apps with file-by-file explanations:
- [references/python-quickstart.md](references/python-quickstart.md)
- [references/flutter-quickstart.md](references/flutter-quickstart.md)
- [references/webbluetooth-quickstart.md](references/webbluetooth-quickstart.md)

On-device API: [references/frame-api.md](references/frame-api.md) (condensed
`frame.*` reference and Halo/Frame differences).

## The canonical lifecycle (identical in all SDKs; camelCase in Dart/TS)

```
connect()
upload_stdlua_libs(['data', <per-message-type libs>])   # e.g. 'plain_text', 'camera'
upload_frame_app('lua/<name>_frame_app.lua')            # your device-side app
attach_print_response_handler()                         # see device print()/errors
start_frame_app()                                       # runs it; blocks until it prints ready
send_message(code, msg.pack()) / attach Rx receivers    # the app conversation
stop_frame_app(); disconnect()
```

The `data` Lua lib is always needed: it reassembles BLE-chunked messages into
`data.app_data[code]` (or raw items) on the device. Each `Tx*`/`Rx*` message
class has a same-named Lua lib that parses/renders it — upload the ones you
use. While the frame app runs, the REPL is busy: no more raw `send_lua()`
without a break signal.

## Message codes

Single byte, chosen per app (examples use e.g. `0x0a` text, `0x0d` camera,
`0x0e` control codes). Host `send_message(0x0a, TxPlainText(...).pack())` must
match `if flag == 0x0a` (or `data.app_data[0x0a]`) in the Lua app. Small
control signals use `TxCode`; responses stream back via `Rx*` receivers
attached to the data channel.

## Halo vs Frame (both supported, auto-detected)

Branch on `frame.HARDWARE_VERSION` in Lua; `BrilliantDeviceType` on the host.

| | Frame | Halo |
|---|---|---|
| Display | 640×400 rectangular | 256×256 round |
| Draw model | buffered — call `frame.display.show()` | draws immediately — no `show()` |
| App start | — | call `frame.display.power_save(false)` |
| Input | tap | button + tap kinds (`'single'`/`'double'`/`'triple'`), `RxClick` (a ~2 s hold powers Halo off, so long-press is shorter) |
| Audio out | — | speaker + `frame.sound` sfxr presets |
| Text | `TxPlainText`, `TxTextSpriteBlock` | same, plus `TxTextPage` with `CircularTextLayout` |

Full table: https://docs.brilliant.xyz/halo/halo-sdk-lua/

## Verify before hardware

Run the device-side Lua in the emulator first (`pip install halo-emulator`) —
firmware-faithful, works for the Lua half of Flutter/TS apps too since the Lua
is identical across SDKs:

```bash
halo-emulator ./my_app_lua_dir/    # REPL + display window
```

or drive it from a pytest (inject taps/BLE/mic data, assert on
`get_bluetooth_sent()` / display state) — test-writing API in
`python/packages/halo_emulator/README.md`.

## Rules that bite

1. **Parity**: device-side Lua is triplicated across the three SDKs and must
   stay byte-identical (`tools/check_lua_parity.py`); SDK feature changes are
   expected to land in all three implementations (see root `AGENTS.md` for
   known asymmetries before assuming an API exists in your language).
2. **Flutter assets**: every `.lua` file the app uploads must be listed under
   `assets:` in `pubspec.yaml` (including `packages/brilliant_msg/lua/*.min.lua`).
3. **Errors on device**: wrap the Lua app loop in `pcall` and `print(err)` —
   with the print handler attached, that's your only stderr. A break signal
   arrives as an error in that `pcall`.
4. **Memory**: the VM has ~30 KB free; `collectgarbage('collect')` after
   handling large messages, prefer `.min.lua` libs and progressive/sliced
   sprites (`TxImageSpriteBlock`) over big ones.
