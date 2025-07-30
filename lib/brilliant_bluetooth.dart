import 'dart:async';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

import 'brilliant_bluetooth_exception.dart';
import 'brilliant_connection_state.dart';
import 'brilliant_device.dart';
import 'brilliant_scanned_device.dart';

final _log = Logger("Bluetooth");

class BrilliantBluetooth {

  static Future<void> requestPermission() async {
    try {
      // make sure the adapter is ready (iOS in particular)
      await FlutterBluePlus.adapterState.where((val) => val == BluetoothAdapterState.on).first;
      await FlutterBluePlus.startScan();
      await FlutterBluePlus.stopScan();
    } catch (error) {
      _log.warning("Couldn't obtain Bluetooth permission. $error");
      return Future.error(BrilliantBluetoothException(error.toString()));
    }
  }

  static Stream<BrilliantScannedDevice> scan() async* {
    try {
      // make sure the adapter is ready (iOS in particular)
      await FlutterBluePlus.adapterState.where((val) => val == BluetoothAdapterState.on).first;

      _log.info("Starting to scan for devices");
      await FlutterBluePlus.startScan(
        withServices: [
          Guid('7a230001-5475-a6a4-654c-8431f6ad49c4'),
          Guid('fe59'),
        ],
        // note: adding a shorter scan period to reflect
        // that it might be used for a short period at the
        // beginning of an app but not running in the background
        timeout: const Duration(seconds: 10),
        continuousUpdates: false,
        removeIfGone: null,
      );
    } catch (error) {
      _log.warning("Scanning failed. $error");
      throw BrilliantBluetoothException(error.toString());
    }

    yield* FlutterBluePlus.scanResults
        .where((results) => results.isNotEmpty)
        // TODO filter by name: "Frame"
        .map((results) {
      ScanResult nearestDevice = results[0];
      for (int i = 0; i < results.length; i++) {
        if (results[i].rssi > nearestDevice.rssi) {
          nearestDevice = results[i];
        }
      }

      _log.fine(() =>
          "Found ${nearestDevice.device.advName} rssi: ${nearestDevice.rssi}");

      return BrilliantScannedDevice(
        device: nearestDevice.device,
        rssi: nearestDevice.rssi,
      );
    });
  }

  static Future<void> stopScan() async {
    try {
      _log.info("Stopping scan for devices");
      await FlutterBluePlus.stopScan();
    } catch (error) {
      _log.warning("Couldn't stop scanning. $error");
      return Future.error(BrilliantBluetoothException(error.toString()));
    }
  }

  static Future<BrilliantDevice> connect(BrilliantScannedDevice scanned) async {
    try {
      _log.info("Connecting");

      await FlutterBluePlus.stopScan();

      await scanned.device.connect(
        autoConnect: Platform.isIOS ? true : false,
        mtu: null,
      );

      final connectionState = await scanned.device.connectionState
          .firstWhere((event) => event == BluetoothConnectionState.connected)
          .timeout(const Duration(seconds: 3));

      if (connectionState == BluetoothConnectionState.connected) {
        return await enableServices(scanned.device);
      }

      throw ("${scanned.device.disconnectReason?.description}");
    } catch (error) {
      await scanned.device.disconnect();
      _log.warning("Couldn't connect. $error");
      return Future.error(BrilliantBluetoothException(error.toString()));
    }
  }

  static Future<BrilliantDevice> reconnect(String uuid) async {
    try {
      _log.info(() => "Will re-connect to device: $uuid once found");

      BluetoothDevice device = BluetoothDevice.fromId(uuid);

      await device.connect(
        // note: changed so that sdk users (apps) directly specify reconnect behaviour
        // otherwise there are spurious reconnects even after programmatically disconnecting
        timeout: const Duration(days: 365),
        autoConnect: Platform.isIOS ? true : false,
        mtu: null,
      );

      final connectionState = await device.connectionState.firstWhere((state) =>
          state == BluetoothConnectionState.connected ||
          (state == BluetoothConnectionState.disconnected &&
              device.disconnectReason != null));

      _log.info(() => "Found reconnectable device: $uuid");

      if (connectionState == BluetoothConnectionState.connected) {
        return await enableServices(device);
      }

      throw ("${device.disconnectReason?.description}");
    } catch (error) {
      _log.warning("Couldn't reconnect. $error");
      return Future.error(BrilliantBluetoothException(error.toString()));
    }
  }

  static Future<BrilliantDevice> enableServices(BluetoothDevice device) async {
    if (Platform.isAndroid) {
      await device.requestMtu(512);
    }

    BrilliantDevice finalDevice = BrilliantDevice(
      device: device,
      state: BrilliantConnectionState.disconnected,
    );

    List<BluetoothService> services = await device.discoverServices();

    for (var service in services) {
      // If the device has the Frame service
      if (service.serviceUuid == Guid('7a230001-5475-a6a4-654c-8431f6ad49c4')) {
        _log.fine("Found Service");
        finalDevice.maxStringLength = device.mtuNow - 3;
        finalDevice.maxDataLength = device.mtuNow - 4;
        finalDevice.type = BrilliantDeviceType.frame;

        for (var characteristic in service.characteristics) {
          if (characteristic.characteristicUuid ==
              Guid('7a230002-5475-a6a4-654c-8431f6ad49c4')) {
            _log.fine("Found TX characteristic");
            finalDevice.txChannel = characteristic;
          }
          if (characteristic.characteristicUuid ==
              Guid('7a230003-5475-a6a4-654c-8431f6ad49c4')) {
            _log.fine("Found RX characteristic");
            finalDevice.rxChannel = characteristic;

            await characteristic.setNotifyValue(true);
            _log.fine("Enabled RX notifications");
          }
          if (characteristic.characteristicUuid ==
              Guid('7a230004-5475-a6a4-654c-8431f6ad49c4')) {
            _log.fine("Found Audio TX characteristic");
            finalDevice.audioTxChannel = characteristic;

            finalDevice.type = BrilliantDeviceType.halo;
            _log.fine("Device type: ${finalDevice.type}");

            // TODO Halo seems to report 517 but really might be less
            finalDevice.maxStringLength = finalDevice.maxStringLength! - 2;
            finalDevice.maxDataLength = finalDevice.maxDataLength! - 2;
          }
        }

        _log.fine(() => "Max string length: ${finalDevice.maxStringLength}");
        _log.fine(() => "Max data length: ${finalDevice.maxDataLength}");
      }
      if (service.serviceUuid == Guid('fe59')) {
        _log.fine("Found DFU service");
        finalDevice.state = BrilliantConnectionState.dfuConnected;
        return finalDevice;
      }
    }

    // TODO ugly hack: need to work out what to await here to ensure the Frame is ready
    // Don't let BrilliantBluetooth.connect complete until the Frame is ready
    await Future.delayed(const Duration(milliseconds: 100));

    if (finalDevice.txChannel != null && finalDevice.rxChannel != null) {
      finalDevice.state = BrilliantConnectionState.connected;
      return finalDevice;
    }

    throw ("Incomplete set of services found");
  }
}
