## 2.0.0

* Added Halo device support
* New `BrilliantDeviceType` enum (`FRAME`, `HALO`, `UNKNOWN`) — detected automatically at connection time by probing for the Halo audio TX characteristic (UUID `7a230005-5475-a6a4-654c-8431f6ad49c4`)
* New `FrameBle.type` property returns the detected `BrilliantDeviceType`
* New `send_audio(data, await_bt_response=False)` — writes LC3 or PCM audio data to the Halo audio characteristic; silently drops packets that exceed a single MTU payload
* New `send_remove_signal()` — sends `0x05` signal byte to remove `main.lua` from Halo and reset the Lua VM
* Breaking: `connect()` now returns the device **name** rather than the device **address**
* Breaking: `send_data(await_data=True)` now resolves when it receives an ACK byte (`\x01\x00\x00` for success, `\x01\x00\x01` for error) from the updated `data.lua` running on the device, rather than waiting for the next data event. Requires the updated `data.lua` from `frame-msg 6.0.0`.
* `send_data()` — new `await_bt_response` parameter (default `True`) controls BLE write-with/without-response; new `timeout` parameter (default `5` seconds)
* `send_lua()` — new `timeout` parameter (default `5` seconds) for the `await_print` wait
* Project migrated from pip to `uv` workspace; use `uv add frame-ble` to install

## 1.1.1

* Updated docs - added ReadTheDocs, updated README

## 1.1.0

* Corrected `pyproject.toml` to include existing `bleak` dependency

## 1.0.5

* Allowed calls to frame.is_connected() to return False without error even if Frame was never connected

## 1.0.4

* Allow calls to frame.disconnect() even when connect() did not succeed (e.g. in a finally block)
* Added small delays (200ms) after break signal and reset signal to wait for Frame to be ready

## 1.0.3

* Added workaround for BlueZ backend for Bleak on Linux to force MTU negotiation

## 1.0.2

* Fixed bug in handling escape sequences in file uploads, improved the algorithm for not splitting a chunk in the middle of an escape sequence. Also handles tab sequences

## 1.0.1

* Fixed missing escape sequence for bare backslashes in uploaded files

## 1.0.0

* First PyPI packge published

## 0.1.1

* Updated README.md

## 0.1.0

* Initial version adapted from frame-utilities-for-python