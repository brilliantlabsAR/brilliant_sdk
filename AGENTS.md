# Brilliant SDK — agent guide

Host-side SDK for **Brilliant Labs smart glasses (Halo and Frame)** in three
parallel implementations: `python/` (PyPI: `brilliant-ble` / `brilliant-msg` /
`brilliant-sdk`), `flutter/` (pub.dev: `brilliant_ble` / `brilliant_msg` /
`brilliant_sdk` / `simple_brilliant_app`) and `webbluetooth/` (npm:
`brilliant-ble` / `brilliant-msg` / `brilliant-sdk`). The glasses run user apps
in an on-device **Lua 5.4 VM** exposing a `frame.*` API; the SDK provides the
BLE transport (`*_ble`), the message protocol (`*_msg`), and meta-packages
(`*_sdk`). Start with `README.md` for the architecture diagram.

The whole tree is ~55k lines — do not read broadly. Use the reading paths and
indexes below.

## How an app works (the pattern behind everything)

Every non-trivial app is **two programs**: a host program (Python/Dart/TS) and
a device-side Lua app, coupled by single-byte message codes that must match on
both sides. The canonical lifecycle, identical in all three SDKs (camelCase in
Dart/TS):

```
connect() → upload_stdlua_libs([...]) → upload_frame_app(...) →
start_frame_app() → send_message(code, packed) / attach rx handlers → stop
```

- Host side packs typed messages (`TxSprite`, `TxPlainText`, `RxPhoto`, …).
- Device side: each message type has a paired Lua library in the `*_msg`
  package (`data.lua` + one per type) that reassembles and renders.
- Examples follow the naming convention `<name>.py` + `lua/<name>_frame_app.lua`.

For quick one-off device control you can skip all of this and send raw Lua
strings to the REPL with `*_ble` alone (see
`python/packages/brilliant_ble/examples/hello_world.py`).

## Minimal reading paths

"Show text on the glasses" (Python): `README.md` →
`python/packages/brilliant_msg/README.md` (annotated sprite example = the
canonical lifecycle) → `python/packages/brilliant_msg/examples/plain_text.py`
+ `examples/lua/plain_text_frame_app.lua`. That's ~300 lines total; the same
path exists in each SDK.

Per-area entry points:

| Task | Read |
|---|---|
| Pick an example to copy | `python/packages/brilliant_msg/examples/EXAMPLES.md`, `python/packages/brilliant_ble/examples/EXAMPLES.md`, `flutter/packages/simple_brilliant_app/example/EXAMPLES.md`, `webbluetooth/packages/brilliant-msg/example/EXAMPLES.md` |
| On-device `frame.*` Lua API | `python/packages/halo_emulator/README.md` (Halo, condensed) → full refs on docs.brilliant.xyz (below) |
| Full Flutter apps | `flutter/packages/simple_brilliant_app/` (`SimpleFrameApp` wraps the lifecycle) |
| BLE wire protocol (no SDK) | https://docs.brilliant.xyz/halo/halo-sdk-bluetooth-specs/ |
| Old `frame_*`/`FrameBle` names in the wild | `python/MIGRATION.md` (also `flutter/`, `webbluetooth/`) — most pre-2026 community code and model priors use the old names |

## Verify without hardware

`halo-emulator` (PyPI, source in `python/packages/halo_emulator/`) is a
firmware-faithful Halo emulator — Lua 5.4, real fonts, palette, IMU/tap/mic
event injection. It is the write→run→observe loop when no glasses are
attached, **including for Flutter/WebBluetooth work**: device-side Lua is
identical across SDKs, so validate the Lua half there regardless of host
language. Its README documents the REPL, test-writing API, and the supported
`frame.*` surface.

## Testing

- **Python** (`cd python`): `uv sync --all-packages --all-extras` then
  `uv run pytest` — hardware-free by design (~240 tests: msg pack/parse,
  emulator, ble unit tests). Device-marked tests are skipped unless
  `BRILLIANT_DEVICE=1`. Most `test_*.py` under `brilliant_ble/tests/` are
  standalone device scripts (`python <file> --name Halo`), not pytest tests.
- **Flutter** (`cd flutter`): `melos bootstrap` then `melos test` (no hardware).
- **WebBluetooth**: no test suite; `npm run build` per package must pass.

## Cross-SDK parity rules

1. **Features land in all three SDKs.** A fix or message-type change in one
   implementation is incomplete until ported to the other two (check git log:
   parity commits are the norm). If you can only do one, say so explicitly.
2. **Device-side Lua is triplicated byte-for-byte** in
   `python/packages/brilliant_msg/src/brilliant_msg/lua/`,
   `flutter/packages/brilliant_msg/lib/lua/` and
   `webbluetooth/packages/brilliant-msg/src/lua/` (both `.lua` and
   hand-minified `.min.lua`). Any edit must be applied to all three; run
   `python3 tools/check_lua_parity.py` (CI enforces it).
3. **Same class names, per-language file naming**: `TxPlainText` lives in
   `tx_plain_text.py` / `tx/plain_text.dart` / `tx/plain-text.ts`. Example
   names differ slightly between SDKs; match by message classes used, not
   filename.

### Known API asymmetries (do not hallucinate parity)

| API | Python | Flutter | WebBluetooth |
|---|---|---|---|
| `TxSpriteCoords` | ✓ | — | ✓ |
| Mag calibration / heading helpers | ✓ (`brilliant_msg.calibration`, `.heading`) | in `imu_compass` example only | ✓ (`mag-calibration.ts`, `compass-heading.ts`) |
| `halo_emulator` | ✓ | — | — |

## Halo vs Frame

Both devices are auto-detected after connect (`BrilliantBle.type` /
`BrilliantDeviceType` on the host, `frame.HARDWARE_VERSION` in Lua). They
differ in display size/geometry, draw model (Frame needs
`frame.display.show()` after drawing; Halo draws immediately), palette
handling, input (Frame tap vs Halo button+tap), and audio (Halo adds a
speaker). See the "Key differences from Frame" table at
https://docs.brilliant.xyz/halo/halo-sdk-lua/ before writing device-side Lua,
and `python/packages/brilliant_ble/examples/hello_world.py` for the classic
branch-per-device example.

## External references

- Device docs (clean markdown, fetch raw for token efficiency):
  rendered at https://docs.brilliant.xyz/ , sources at
  `https://raw.githubusercontent.com/brilliantlabsAR/docs/main/<page>.md` —
  key pages: `halo/halo-sdk-lua.md`, `frame/frame-sdk-lua.md`,
  `halo/halo-sdk-bluetooth-specs.md`, `halo/hardware.md`, `frame/hardware.md`.
- Python API reference: https://brilliant-ble.readthedocs.io/ and
  https://brilliant-msg.readthedocs.io/
- WebBluetooth examples + TypeDoc: https://brilliantlabsar.github.io/brilliant_sdk/
- Halo firmware (authoritative device behavior):
  https://github.com/brilliantlabsAR/halo-firmware — BLE/SMP protocol in
  `applications/halo/PROTOCOL.md`, display/palette in
  `modules/halo/src/lua_display.c`.
- Frame firmware: https://github.com/brilliantlabsAR/frame-codebase

## Per-ecosystem guides and skills

Each SDK directory has a `CLAUDE.md` with its workspace commands (uv / Melos /
npm). Claude Code skills in `.claude/skills/`: `glasses-app` (building an app
against this SDK — start there for any new-app task) and `release`
(maintainers: publishing to PyPI/npm/pub.dev).
