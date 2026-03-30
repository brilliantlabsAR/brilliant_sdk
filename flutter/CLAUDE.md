# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a **Melos monorepo** for the Brilliant SDK for Flutter, providing integration with Brilliant Labs AR devices (Frame and Halo smart glasses). It contains 4 packages under `packages/`.

## Commands

Requires [Melos](https://melos.invertase.dev/) (`dart pub global activate melos`).

```bash
melos bootstrap   # flutter pub get in all packages (run after cloning)
melos analyze     # flutter analyze in all packages
melos format      # dart format . in all packages
melos test        # flutter test in all packages
melos version     # bump versions across packages
```

Run tests for a single package:
```bash
cd packages/frame_msg && flutter test
cd packages/frame_msg && flutter test test/tx/code_test.dart  # single test file
```

Before publishing: replace all `path:` dependencies with semver constraints, then `dart pub publish` from the package folder.

## Architecture

The SDK is organized in layers:

**`frame_ble`** — BLE communication layer. Handles device scanning (`BrilliantBluetooth`), connection state, MTU-aware packet splitting, and Device Firmware Update. Uses `flutter_blue_plus`. This layer is device-type-agnostic.

**`frame_msg`** — Application-level messaging protocol. Defines TX (phone → Frame) and RX (Frame → phone) message types. TX messages implement `pack()` → `Uint8List` for BLE transmission. RX messages are parsed from incoming byte streams. Each message type has a corresponding Lua script in `lib/lua/` that runs on the device to handle parsing/rendering. Both full and `.min.lua` versions are included.

**`brilliant_sdk`** — Meta-package that re-exports `frame_ble` and `frame_msg` as a single import.

**`simple_brilliant_app`** — High-level Flutter app framework (`SimpleFrameApp`, `FrameVisionApp`) for rapid development. Contains 15+ example apps under `examples/`.

## Key Design Patterns

- **Message protocol**: Each TX message type has a unique message code (e.g. `0x0d`). `TxMsg.pack()` serializes to `Uint8List`. The BLE layer handles chunking based on negotiated MTU. Lua scripts on the device reassemble and render.
- **Streams**: BLE connection state and incoming data are exposed as Dart streams. Device interaction is async/await throughout.
- **Lua pairing**: Every message type in `frame_msg` has a corresponding `.lua` and `.min.lua` file. When adding new message types, both the Dart class and the Lua script must be updated together.

## Tests

Tests live in `packages/frame_msg/test/` (4 test files). There are no tests in other packages currently.
