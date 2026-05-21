## 0.4.0

* Added Halo device support
* `BrilliantDeviceType` enum (`FRAME`, `HALO`, `UNKNOWN`) exported from package
* `FrameBle.type` getter — device type is detected automatically at connection time by probing for the Halo audio TX characteristic
* `sendAudio(data, awaitBtResponse?)` — writes to the Halo audio characteristic (UUID `7a230005-...`), write-without-response by default, silently drops oversized packets
* `sendRemoveSignal()` — sends `0x05` signal byte to remove `main.lua` from Halo
* `sendData()` and `sendMessage()` — new `awaitBtResponse` option to control BLE write-with/without-response
* `transmit()` internally uses `writeValueWithResponse` or `writeValueWithoutResponse` based on `awaitBtResponse`
* Disconnect and failed connection attempts now reset `audioTxCharacteristic` and `deviceType`

## 0.3.1

* Improved TypeDoc comments for API reference

## 0.3.0

* connect() returns device name in preference to device id
* examples: print console log messages to example web page in addition to console log (helpful for mobile browsers with no dev tools/console)

## 0.2.2

* Republished with dist files generated

## 0.2.1

* Republished with package lock updated

## 0.2.0

* Added retry logic to `connect()` call for specific intermittent connection errors

## 0.1.0

* Initial version ported from Python
