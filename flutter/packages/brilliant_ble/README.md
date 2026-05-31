# `brilliant-ble`

Low level BLE communication for [Brilliant Labs](https://brilliant.xyz/) Halo and Frame devices using [Flutter Blue Plus](https://pub.dev/packages/flutter_blue_plus).

[Brilliant SDK documentation](https://docs.brilliant.xyz/frame/frame-sdk/).

## Features

* Finds and connects to Frame and Halo
* sends Lua command strings to device
* sends data to frameside data receive handler for processing
* uploads Lua files to run on device
* subscribes to data streams from device
* performs over-the-air (OTA) Device Firmware Update (DFU)

## See Also

* [`brilliant_msg`](https://pub.dev/packages/brilliant_msg): Application-level library for passing rich objects between a host program and Frame/Halo, such as images, streamed audio, IMU data and rasterized text.
* [`simple_brilliant_app`](https://pub.dev/packages/simple_brilliant_app) and its many example applications in [GitHub](https://github.com/brilliantLabsAR/brilliant_sdk) for demonstrations of [`brilliant_msg`](https://pub.dev/packages/brilliant_msg) being used by that framework.
