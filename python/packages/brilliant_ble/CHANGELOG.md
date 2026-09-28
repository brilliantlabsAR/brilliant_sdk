## 3.3.0

* New `NotConnectedError`, raised when an operation needs a connected device but the link is down (never connected, or dropped). `send_lua()`, `send_data()`, `send_audio()`, `send_message()`, `send_reset_signal()`, `send_break_signal()`, `send_remove_signal()`, `max_lua_payload()` and `max_data_payload()` now raise it instead of `AttributeError: 'NoneType' object has no attribute 'mtu_size'`. It subclasses both `ConnectionError` and `ValueError`, so existing `except ValueError` around `send_message()` still catches it. Teardown code that may run after a drop can catch it deliberately: `except NotConnectedError: pass`
* `max_lua_payload()` and `max_data_payload()` raise `NotConnectedError` when disconnected rather than silently returning `0`
* A disconnect no longer resets the whole `BrilliantBle` object: only connection state (client, characteristics, `name`, `type`) is cleared, and the handlers passed to `connect()` are kept. Previously the disconnect handler wiped itself as it fired
* The user `disconnect_handler` is called once per disconnect; `disconnect()` no longer runs the internal handler a second time, and a late callback from an earlier connection is ignored
* A `send_lua(await_print=True)` or `send_data(await_data=True)` waiting when the link drops now raises `NotConnectedError` straight away instead of waiting out its timeout and raising "device didn't respond". `drain_print_channel()` returns straight away

## 3.2.0

* New `drain_print_channel(quiet=0.25, max_total=1.5)` — discards unsolicited print output already arriving on the channel (such as the `interrupted`/reboot banner produced by a break or reset) so the next `send_lua(await_print=True)` receives a clean response rather than the stray banner. Bounded so it never hangs: returns after `quiet` seconds of silence, or `max_total` at the latest
* New `name` property returning the connected device's name

Both were added to the source during the Halo firmware 0.8.8 work but shipped without a version bump. `brilliant-msg` 7.1.0 calls `drain_print_channel()` while still allowing `brilliant-ble >= 3.0.0`, so a fresh install could resolve 3.1.1 and fail with `AttributeError` on `connect()`. Use `brilliant-msg` 7.1.1 or later, which requires this release.

## 3.1.1

* Fixed `upload_file_from_string()` failing on Lua files containing non-ASCII characters (e.g. `°`): chunks are now sized by UTF-8 byte length rather than string length, so multi-byte characters can no longer push a packet over the MTU. Multi-byte characters and escape sequences are never split across chunks
* New `chunk_lua_string()` module-level function exposing the byte-accurate chunking

## 3.1.0

* New `ota_flash_firmware()` — flashes signed app firmware (`zephyr.signed.bin`) to a Halo device over the BLE SMP (MCUmgr) OTA service. By default the uploaded image is confirmed and the device rebooted in one call; pass `confirm=False` to mark the image for a one-shot test boot instead (MCUboot reverts to the previous firmware on the next reboot unless confirmed). Optional `progress_handler(bytes_sent, total_bytes)` callback (sync or async) reports upload progress; `reboot` and `chunk_size` parameters. Halo only
* New `ota_confirm()` — confirms the currently running firmware image, completing a `confirm=False` test flash after reboot and reconnection. Halo only
* New `OtaError` exception raised by the OTA methods
* New `examples/ota_flash.py` demonstrating OTA flashing. Note that first-time flashing and bootloader flashing still require the Alif wired tools

## 3.0.0

* First release of `brilliant-ble`, renamed from `frame-ble`; replace `uv add frame-ble` with `uv add brilliant-ble`
* `FrameBle` renamed to `BrilliantBle`; update imports from `frame_ble` to `brilliant_ble`
* Adds support for Brilliant Labs Halo in addition to Brilliant Labs Frame

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