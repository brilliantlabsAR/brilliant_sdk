## 5.2.0

* `BrilliantBluetooth.connect()` takes a new optional `timeout` (default 5 s) limiting how long the BLE link may take to come up. Previously Android and macOS used flutter_blue_plus's default of 35 s, and iOS a fixed 3 s. A link that never comes up almost always means the device refused this host: Halo drops a host it has no bond for unless it is in pairing mode, and iOS/macOS hide that refusal and silently retry. When `connect()` fails, apps can suggest the user puts Halo in pairing mode (hold the button for 5 s) and, if the phone still lists it as paired, forgets it in Bluetooth settings. `reconnect()` is unchanged
* Android: `connect()` no longer fails with "failed to create bond" after Android re-pairs a device by itself. When Android finds its stored keys no longer work (Halo cleared its bonds), it re-pairs after a consent dialog and briefly reports the bond state as none before bonded; `createBond()` saw the transient state and threw although bonding succeeded. A failed `createBond()` now waits up to 2 s for the bonded state before giving up

## 5.1.0

* New `BrilliantDevice.drainPrintChannel()` — discards unsolicited print output already arriving on the channel (such as the `interrupted`/reboot banner produced by a break or reset) so the next `sendString(awaitResponse: true)` receives a clean response rather than the stray banner. Bounded so it never hangs: returns after `quiet` of silence, or `maxTotal` at the latest
* New `BrilliantBluetooth.getSystemConnectedDevices()` — returns all Brilliant devices connected at the system level. Such devices do not advertise, so scanning can never find them; on iOS an ANCS-soliciting Halo is auto-connected by the system, making this the common case rather than the exception. The existing single-device `getSystemConnectedDevice(uuid)` is unchanged
* `scan()` now yields system-connected devices first, then falls back to scanning for advertising ones (system-connected entries have no RSSI reading)

These were added to the source during the Halo firmware 0.8.8 work but shipped without a version bump. `simple_brilliant_app` 9.1.0 calls `drainPrintChannel()` while still allowing `brilliant_ble ^5.0.0`, so a fresh resolve could pick 5.0.1 and fail. Use `simple_brilliant_app` 9.1.1 or later, which requires this release.

## 5.0.1

* Fixed `uploadScript` failing on Lua files containing non-ASCII characters (e.g. `°`): chunks are now sized by UTF-8 byte length rather than string length, so multi-byte characters can no longer push a packet over the MTU (#12). Multi-byte characters and escape sequences are never split across chunks
* `sendString` now validates the payload's UTF-8 byte length against `maxStringLength` instead of its string length
* New `chunkLuaString()` top-level function exposing the byte-accurate chunking

## 5.0.0

* First release of `brilliant_ble`, renamed from `frame_ble`; replace `frame_ble` with `brilliant_ble` in `pubspec.yaml` and update imports from `package:frame_ble/` to `package:brilliant_ble/`
* Adds support for Brilliant Labs Halo in addition to Brilliant Labs Frame

## 4.0.0

* Added Halo device support
* New `BrilliantDeviceType` enum (`frame`, `halo`, `unknown`) — exported from package
* `BrilliantDevice.type` getter — device type is detected automatically at connection time by probing for the Halo audio TX characteristic (UUID `7a230005-5475-a6a4-654c-8431f6ad49c4`)
* `BrilliantDevice.audioTxChannel` — Halo-specific BLE characteristic for audio output (LC3 or PCM)
* `BrilliantDevice.isLuaInReplState()` — utility method that probes the device with a `print(1)` and returns `true` if Lua is in the REPL/break state and `false` if a main loop is running (uses a short timeout)
* `BrilliantBluetooth.getSystemConnectedDevice(uuid)` — public method to check if a device is already connected at the OS level before attempting a new connection
* `reconnect()` — now checks for an existing system-level connection before initiating a fresh BLE connect, avoiding redundant reconnects on iOS/Android
* Android: negotiates MTU 517, requests high connection priority, sets preferred 2M PHY, and creates a bond during `enableServices()`
* Android: fixed spurious automatic reconnect after an intentional user-initiated disconnect — GATT disconnect code `0` (GATT_SUCCESS) is now correctly identified as a local disconnect and no longer triggers the reconnect path
* `checkCharacteristic()` / startup display clear — Halo uses `frame.display.clear()` while Frame uses the bitmap fill approach

## 3.0.0

* Added `BrilliantDfuDevice` class and associated `BrilliantConnectionState` to support OTA device firmware update (DFU)

## 2.0.0

* Breaking: Added reconnect logic. Applications that need to connect to Frame when it becomes visible (e.g. wake on tap) need reconnect logic - the Noa app is an example. `BrilliantDevice.connectionState` changed its signature from `Stream<BrilliantConnectionState>` to `Stream<BrilliantDevice>` as part of this change.
* Logging of available memory on Frame during script uploads was removed

## 1.0.2

* Docs: updated package README

## 1.0.1

* added an await for adapterState to be on before attempting a scan, on iOS bluetooth startup can be a bit slower

## 1.0.0

* modified BrilliantDevice.connectionState to return only the state, not a new BrilliantDevice

## 0.0.1

* Initial release split from `simple_frame_app 4.0.2`
