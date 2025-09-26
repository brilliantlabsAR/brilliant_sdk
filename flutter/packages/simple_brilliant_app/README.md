Flutter and Lua quickstart app scaffolding and standard library functions for Brilliant Frame development on Android/iOS.

## Images
![frameshot1](https://github.com/CitizenOneX/simple_frame_app/raw/main/doc/frameshot1.png)
![frameshot2](https://github.com/CitizenOneX/simple_frame_app/raw/main/doc/frameshot2.png)
![frameshot3](https://github.com/CitizenOneX/simple_frame_app/raw/main/doc/frameshot3.jpg)
![frameshot4](https://github.com/CitizenOneX/simple_frame_app/raw/main/doc/frameshot4.jpg)
![frameshot5](https://github.com/CitizenOneX/simple_frame_app/raw/main/doc/frameshot5.jpg)
![screenshot1](https://github.com/CitizenOneX/simple_frame_app/raw/main/doc/screenshot1.png)
![screenshot2](https://github.com/CitizenOneX/simple_frame_app/raw/main/doc/screenshot2.png)

## Features

* Connect/disconnect via bluetooth (`flutter_blue_plus` package)
* Send and display Sprites on Frame (from both pre-made image assets and also dynamically-sourced)
* Send text for display on Frame (TxPlainText and TxTextSpriteBlock for Unicode/RTL)
* Request and process JPG images from Frame camera (`image` package)
* Request magnetometer and accelerometer stream (IMU)
* Automatically loads custom Lua scripts onto Frame on app startup, deletes them on app exit
* Automatically loads sprite assets into Frame memory on app startup
* Framework for custom typed message sending and receiving (pack/parse standard and custom message types) that automatically handles messages larger than bluetooth MTU size
* Library of standard frameside Lua scripts (for generic accumulation of message data, battery, camera, sprites, text, IMU)
* Conventions for the use of minified Lua scripts
* Template for optional simple single-page phoneside Flutter app
* Template for standard frameside Lua app

## Getting started

* Create a Flutter mobile app
* `flutter pub add simple_frame_app`
* Follow the `flutter_blue_plus` [instructions](https://pub.dev/packages/flutter_blue_plus#getting-started) for modifying configuration files on Android and iOS for Bluetooth LE support
* On Android, also append `|navigation` to the long list in `android:configChanges` to prevent app activity restarts on bluetooth connect/disconnect.
* Copy template files `template/main.dart` and `template/frame_app.lua` to your project's lib/ and assets/ directories respectively (also see [sample projects](https://github.com/CitizenOneX?tab=repositories) for examples of phoneside and frameside apps.)
* Add assets to `pubspec.yaml` under `flutter:` `assets:`, both standard and custom, that you wish to send to Frame on app startup e.g. `- packages/frame_msg/lua/camera.min.lua` for a standard Lua library, or `- assets/sprites/20_mysprite.png` for an app-specific sprite. For the template `frame_app.lua`, add the following:
```
flutter:
  assets:
  - packages/frame_msg/lua/battery.min.lua
  - packages/frame_msg/lua/data.min.lua
  - packages/frame_msg/lua/code.min.lua
  - packages/frame_msg/lua/plain_text.min.lua
  - packages/frame_msg/lua/sprite.min.lua
  - packages/frame_msg/lua/camera.min.lua
  - assets/frame_app.lua
```

## Usage

Phoneside (Flutter/Dart)

```dart
// send some ASCII text to Frame
final text = TxPlainText(text: 'Hello, Frame!');
await frame!.sendMessage(0x12, text.pack());

// asking Frame to take a photo and send it back
var takePhoto = TxCameraSettings();
await frame!.sendMessage(0x0d, takePhoto.pack());

// synchronously await the image response encoded as a jpeg
Uint8List imageData = await RxPhoto(qualityLevel: 50).attach(frame!.dataResponse).first;

// send a custom message and value to the Lua app running on Frame
final code = TxCode(value: 1);
await frame!.sendMessage(0x0e, code.pack());

// send a sprite to Frame with an identifying message code
var sprite = TxSprite.fromPngBytes(pngBytes: bytesFromFileOrWeb);
await frame!.sendMessage(0x2F, sprite.pack());
```

Frameside (Lua)
```lua
-- Phone to Frame message codes
CAMERA_SETTINGS_MSG = 0x0d
HOTDOG_MSG = 0x0e

-- camera_settings message to take a photo
if (data.app_data[CAMERA_SETTINGS_MSG] ~= nil) then
    rc, err = pcall(camera.camera_capture_and_send, data.app_data[CAMERA_SETTINGS_MSG])

    if rc == false then
        print(err)
    end

    -- clear the message
    data.app_data[CAMERA_SETTINGS_MSG] = nil
end

-- hotdog classification 0 or 1
if (data.app_data[HOTDOG_MSG] ~= nil) then

    if (data.app_data[HOTDOG_MSG].value == 1) then

        if (data.app_data[HOTDOG_SPRITE] ~= nil) then
            local spr = data.app_data[HOTDOG_SPRITE]
            frame.display.bitmap(450, 136, spr.width, 2^spr.bpp, 0, spr.pixel_data)
        end
    end

    frame.display.show()

    -- clear the message
    data.app_data[HOTDOG_MSG] = nil
end
```

Numerous example projects can be found [in the CitizenOneX GitHub](https://github.com/CitizenOneX?tab=repositories).

## Additional information

This is a work-in-progress personal project with limited support and frequent breaking changes; fixes and suggestions with PRs welcome.
