# Flutter quickstart

```bash
flutter pub add simple_brilliant_app    # pulls in brilliant_ble + brilliant_msg
```

Use `simple_brilliant_app` rather than wiring `brilliant_msg` yourself: its
`SimpleFrameApp` mixin handles scanning, connection, uploading the Lua
libs/app on startup and teardown, and gives you `frame` to talk to.

Setup that is easy to miss:

1. Follow the `flutter_blue_plus` platform setup (Android permissions, iOS
   `NSBluetoothAlwaysUsageDescription`); on Android append `|navigation` to
   `android:configChanges` so BLE connects don't restart the activity.
2. **Every Lua file must be a declared asset** in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - packages/brilliant_msg/lua/data.min.lua
    - packages/brilliant_msg/lua/plain_text.min.lua
    - assets/frame_app.lua          # your device-side app
```

3. Copy `template/main.dart` and `template/frame_app.lua` from the
   `simple_brilliant_app` package as the starting scaffold.

Host side, the message API is the same lifecycle as the other SDKs:

```dart
final text = TxPlainText(text: 'Hello!');
await frame!.sendMessage(0x0a, text.pack());

// request a photo and await it
await frame!.sendMessage(0x0d, TxCameraSettings().pack());
Uint8List jpeg = await RxPhoto(qualityLevel: 50).attach(frame!.dataResponse).first;
```

Device side (`assets/frame_app.lua`) is identical to the Python quickstart's
Lua — the Lua never changes between SDKs. Flutter's `data` lib exposes
messages via `data.app_data[code]` (parsed by registered parsers); see the
template `frame_app.lua` for that variant of the app loop.

## Read next

- `flutter/packages/simple_brilliant_app/example/EXAMPLES.md` — 17 complete
  apps; `camera`, `imu_compass`, `realtime_openai` are the meatiest.
- `flutter/packages/simple_brilliant_app/README.md` — features + template
  walkthrough.
- `RxClick` (Halo click kinds) and `TxTextPage` + `CircularTextLayout`
  (round-display text) exist in all three SDKs. `TxSpriteCoords` does NOT
  exist in Dart (Python/TS only).
- Run `melos bootstrap` once after cloning the monorepo; `melos test` needs no
  hardware.
