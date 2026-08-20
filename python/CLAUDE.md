# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a **uv workspace** for the Brilliant SDK for Python, providing integration with Brilliant Labs AR devices (Frame and Halo smart glasses). It contains 4 packages under `packages/`.

## Commands

Requires [uv](https://docs.astral.sh/uv/).

```bash
uv sync --all-packages          # install all packages and dependencies
uv sync --all-packages --extra tests  # include test dependencies
uv run pytest packages/brilliant_msg/tests/  # run tests for a single package
uv build --package brilliant-ble  # build a specific package
```

Publishing to PyPI (publish in dependency order):
```bash
uv publish --token <token> dist/brilliant_ble-*
uv publish --token <token> dist/brilliant_msg-*
uv publish --token <token> dist/brilliant_sdk-*
```

## Architecture

The SDK is organized in layers:

**`brilliant_ble`** — Low-level BLE communication layer. Handles device scanning, connection, MTU-aware packet splitting, and characteristic I/O. Uses `bleak`. Exposes `BrilliantBle` and `BrilliantDeviceType`.

**`brilliant_msg`** — Application-level messaging protocol. Defines TX (host → device) and RX (device → host) message types. TX messages implement `pack()` → `bytes` for BLE transmission. RX messages are parsed from incoming byte streams. Each message type has a corresponding Lua script in `src/brilliant_msg/lua/` that runs on the device. Both full and `.min.lua` versions are included.

**`brilliant_sdk`** — Meta-package that installs both `brilliant_ble` and `brilliant_msg` as a single dependency.

**`halo_emulator`** — Lua 5.4 emulator (via `lupa`) for testing Halo apps without hardware. Not published to PyPI.

## Key Design Patterns

- **Message protocol**: Each TX message type has a unique message code (e.g. `0x0d`). `pack()` serializes to `bytes`. The BLE layer handles chunking based on negotiated MTU. Lua scripts on the device reassemble and render.
- **Async**: All device interaction uses `asyncio` / `async`/`await` throughout.
- **Lua pairing**: Every message type in `brilliant_msg` has a corresponding `.lua` and `.min.lua` file. When adding new message types, both the Python class and the Lua script must be updated together.

## Tests

Tests live in `packages/brilliant_msg/tests/` and `packages/brilliant_ble/tests/`. No hardware is required for `brilliant_msg` tests. Run from the workspace root:

```bash
uv sync --all-packages --extra tests
uv run pytest packages/brilliant_msg/tests/
```
