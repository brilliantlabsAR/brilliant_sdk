## 7.1.0

* Updated `frame_ble` to `3.0.0`. While v3.0.0 additionally supports OTA device firmware updates, `SimpleFrameApp` and `FrameVisionApp` don't provide any built-in mechanism to do firmware updates, but users of the framework could make use of it.

## 7.0.0

* Updated `frame_msg` to `2.0.0`, removing redundant msgCode provided in `TxMsg` constructor - pass the msgCode separately to FrameBle when sending the message, as this transport-level detail doesn't need to be coupled to the rich message contents.

## 6.0.3

* Updated `frame_msg` to `1.0.1` to get the new default autoexposure and white balance limits and initial values

## 6.0.2

* Updated `frame_ble` to `1.0.1` to add wait for the bluetooth adapter to be on, particularly for iOS since bluetooth startup can be a bit slower

## 6.0.1

* Changed image metadata widget text style to 10pt Helvetica to work better across Android and iOS

## 6.0.0

* NOTE: requires updated firmware with `rgb_gain_limit` for auto exposure and white balance algorithm
* Updated `FrameVisionApp` to allow for `rgb_gain_limit` to be set to cap the per-channel gains that were amplifying sensor noise.
* Updated to `frame_msg 1.0.0` for the Tx settings classes associated with the `rgb_gain_limit` parameter and updated auto and manual exposure defualts.

## 5.0.0

* **Migration Step**: Add `frame_msg: ^0.0.1` package dependency for message classes to `pubspec.yaml` alongside `simple_frame_app`
* **Migration Step**: Standard Frame messages e.g. `TxSprite` are imported through the `frame_msg` package, so in `pubspec.yaml` reference the assets like `packages/frame_msg/lua/sprite.min.lua` instead of `packages/simple_frame_app/lua/sprite.min.lua`. In `main.dart` instead of e.g. `import 'package:simple_frame_app/tx/sprite.dart';` use `import 'package:frame_msg/tx/sprite.dart';`
* **Migration Step**: `frame_ble` package that handles bluetooth connectivity to Frame no longer has a dependency on the `TxMsg` abstract class, so the `sendMessage(TxMsg)` function has changed to `sendMessage(int msgCode, Uint8List payload)` and can be called like so: `frame.sendMessage(msg.msgCode, msg.pack())` if you have constructed a `TxMsg`.
* **Migration Step**: if you previously had an `ImageMetadata` widget in your widget tree (either a `ManualExpImageMetadata` or an `AutoExpImageMetadata`), these are now plain (non-widget) classes, so wrap it in a `ImageMetadataWidget` to put in the widget tree if required
* Refactored Brilliant Bluetooth code into new package `frame_ble` and added dependency
* Refactored Frame Rx and Tx messages into new package `frame_msg` and added dependency
* Apps wanting the `simple_frame_app` and `frame_vision_app` scaffolding should continue to use this package, but simpler apps requiring only a bluetooth connection to Frame to run simple Lua commands, or apps doing custom messages but outside the `simple_frame_app` structure might wish to use `frame_ble` or (`frame_ble` plus `frame_msg`) respectively.

## 4.0.2

* Bugfix: add guard against completing bluetooth connection Future twice
* Bugfix: the updated jpeg quality parameter had an incorrect name and was not being set correctly

## 4.0.1

* Modified `camera.lua` to split lines that were affected by a bug in the lua minifier. Resolution and Pan values were being affected.

## 4.0.0

* Updated Frame camera API to match firmware version v25.008.1013 (multiple resolutions, pan, changed quality levels)
* The default Camera settings Drawer gives resolution options from 256-720 rather than 100-720 because low resolutions appeared to cause issues with autoexposure.

## 3.2.0

* Made `batteryLevel` available from `simple_frame_app` to implementing apps

## 3.1.0

* Removed 50ms delay that was introduced between packet sends to verify reliability, uploads should be faster

## 3.0.0

* Changed RxPhoto to rotate back to upright by default. Specify `upright: false` in the constructor to save a few cycles if you don't need it

## 2.0.3

* Changed default invalid plain_text color VOID/0, changed to WHITE/1

## 2.0.2

* Removed unusable quality 100 from camera settings drawer

## 2.0.1

* Changed camera_capture_and_send() to remove all delays between sends on Frameside, just retry on bluetooth send failure. Overall performance improvement, but retry counts of 10, 50, 100+ occur with some packets suggesting further improvement is possible.

## 2.0.0

* Renamed printInstructions(), tapHandler() to standardized names of onRun(), onTap(), and added onCancel() abstract function to allow implementing app class to perform app-specific initialization and cleanup

## 1.8.0

* Added `frame_vision_app` mixin as a specialized form of simple_frame_app for computer vision applications. Separate templates are now provided in `templates/` for `simple_frame_app` and `frame_vision_app` apps. Frame Vision Apps automatically listen for taps which can be used to capture photos, and provide a hook for a vision processing pipeline when photos are captured. Auto and Manual exposure camera settings are supported and a settings drawer widget is provided.

## 1.7.0

* Fixed scan/connect/reconnect code to be able to be called synchronously, and properly `await`ed.
* Added helper startup method to try scanning, connecting, starting Frame app and optionally running phoneside `run()` method, suitable for use in some apps from `initState()`

## 1.6.1

* Fixed bitmask bug causing analog_gain_limit and manual_analog_gain to be incorrectly parsed in Lua

## 1.6.0

* Added rudimentary support for TxSprite.fromImageBytes() to load arbitrary PNG or JPG files for display on Frame (previously limited to indexed PNG files of 2, 4, or 16 colors only)

## 1.5.1

* Corrected 'GRAY' to 'GRAY' for plain_text display to match firmware

## 1.5.0

* Added simple moving average smoothing option for IMU data

## 1.4.1

* Tweaked Lua source file for image_sprite_block to prevent a bug introduced by the minifier stripping out necessary parentheses

## 1.4.0

* Added RxIMU parser and corresponding frameside sender for streaming magnetometer (compass) and accelerometer data from Frame

## 1.3.0

* Added TxImageSpriteBlock for splitting an image into lines of TxSprite, allowing for progressive/incremental rendering. Also supports in-place updates of sprite lines for continuously updating images.

## 1.2.0

* Updated TxCameraSettings and camera.lua to support both autoexposure and manual exposure/gain photos

## 1.1.1

* removed extra logging statements in `text_sprite_block.lua`

## 1.1.0

* implemented `TxTextSpriteBlock` more fully to support multi-line text, including scrolling frameside when the number of lines sent exceeds maxDisplayRows. The call to `rasterize()` has been updated to require providing indices for lines to rasterize.

## 1.0.1

* fixed `TextUtils` to change `wrapTextSplit` to `wrapText`, i.e. `wrapText` now returns `List<String>`, so `join('\n')` the result if a single string is required

## 1.0.0

* removed deprecated `*DataResponse` functions, use `Rx` classes instead (`RxAudio`, `RxPhoto`, `RxTap`)

## 0.1.0

* Added `Rx` classes in place of `imageDataResponse`, `audioDataResponse`, `tapDataResponse`.
* Deprecated `TextUtils.wrapText(Split)`, going forward use the `wrapText` that returns a List of Strings and join them if you need the single String

## 0.0.9

* Added `audioDataStreamResponse` support for real-time streaming of Frame audio data
* Added `tapDataReponse` as a multi-tap-detection subscription from Frame
* Added `wrapTextSplit` and deprecated `wrapText` in `TextUtils`, returning a `List<String>` instead of a `String` so the caller to quickly select the first, last or a sliding window of Strings to enable scrolling. If a newline-joined single String is desired, it can quickly be assembled with a `join()`
* Performance: modified logging calls with expensive string interpolations to use a closure so they are not evaluated if not logged at the current logging level

## 0.0.8

* Added initial `audioDataResponse` support for Frame audio data as whole audio clips

## 0.0.7

* Updated camera code (lua and dart) with camera parameters from recent firmware updates - exposure_speed, analog_gain_limit, white_balance_speed etc.

## 0.0.6

* Added `TxTextSpriteBlock` message type to send a paragraph of text for display on Frame. Supports Unicode (including right-to-left) script. Rasterization is performed phoneside and text is sent as a series of TxSprites
* Renamed `tx/text.dart` and `lua/text.lua` to `plain_text` to match class names - no interface change, just update imports/assets

## 0.0.1

* Early prototypes
