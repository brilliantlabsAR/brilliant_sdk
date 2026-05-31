import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter/services.dart';
import 'package:brilliant_ble/brilliant_bluetooth_exception.dart';
import 'package:brilliant_ble/brilliant_connection_state.dart';
import 'package:logging/logging.dart';

final _log = Logger("Bluetooth");

class BrilliantDfuDevice {
  BluetoothDevice device;
  BrilliantConnectionState state;
  int? maxStringLength;
  int? maxDataLength;
  BluetoothCharacteristic? _dfuControl;
  BluetoothCharacteristic? _dfuPacket;

  BrilliantDfuDevice({
    required this.state,
    required this.device,
    this.maxStringLength,
    this.maxDataLength,
  });

  Stream<BrilliantDfuDevice> get connectionState {
    return FlutterBluePlus.events.onConnectionStateChanged
        .where((event) =>
            event.connectionState == BluetoothConnectionState.connected ||
            (event.connectionState == BluetoothConnectionState.disconnected &&
                event.device.disconnectReason != null &&
                event.device.disconnectReason!.code != 23789258))
        .asyncMap((event) async {
      if (event.connectionState == BluetoothConnectionState.connected) {
        _log.info("Connection state stream: Connected");
        try {
          return await _enableServices();
        } catch (error) {
          _log.warning("Connection state stream: Invalid due to $error");
          return Future.error(BrilliantBluetoothException(error.toString()));
        }
      }
      _log.info(
          "Connection state stream: Disconnected due to ${event.device.disconnectReason!.description}");
      if (Platform.isAndroid) {
        event.device.connect(timeout: const Duration(days: 365));
      }
      return BrilliantDfuDevice(
        state: BrilliantConnectionState.disconnected,
        device: event.device,
      );
    });
  }


  Future<void> disconnect() async {
    _log.info("Disconnecting");
    try {
      await device.disconnect();
    } catch (_) {}
  }

   Future<BrilliantDfuDevice> connect(
    ) async {
    try {
      _log.info("Connecting");

      await FlutterBluePlus.stopScan();

      await device.connect(
        autoConnect: Platform.isIOS ? true : false,
        mtu: null,
      );

      final connectionState = await device.connectionState
          .firstWhere((event) => event == BluetoothConnectionState.connected)
          .timeout(const Duration(seconds: 3));

      if (connectionState == BluetoothConnectionState.connected) {
        return await _enableServices();
      }

      throw ("${device.disconnectReason?.description}");
    } catch (error) {
      await device.disconnect();
      _log.warning("Couldn't connect. $error");
      return Future.error(BrilliantBluetoothException(error.toString()));
    }
  }
  Stream<double> updateFirmware(String filePath) async* {
    try {
      yield 0;

      _log.info("Starting firmware update");

      if (_dfuControl == null || _dfuPacket == null) {
        throw ("Device is not in DFU mode");
      }

      final updateZipFile = await rootBundle.load(filePath);
      final zip = ZipDecoder().decodeBytes(updateZipFile.buffer.asUint8List());

      final initFile = zip.firstWhere((file) => file.name.endsWith(".dat"));
      final imageFile = zip.firstWhere((file) => file.name.endsWith(".bin"));

      await for (var _ in _transferDfuFile(initFile.content, true)) {}
      await Future.delayed(const Duration(milliseconds: 500));
      await for (var value in _transferDfuFile(imageFile.content, false)) {
        yield value;
      }

      _log.info("Firmware update completed");
    } catch (error) {
      _log.warning("Couldn't complete firmware update. $error");
      yield* Stream.error(BrilliantBluetoothException(error.toString()));
    }
  }

  Stream<double> _transferDfuFile(Uint8List file, bool isInitFile) async* {
    Uint8List response;

    try {
      if (isInitFile) {
        _log.fine("Uploading DFU init file. Size: ${file.length}");
        response = await _dfuSendControlData(Uint8List.fromList([0x06, 0x01]));
      } else {
        _log.fine("Uploading DFU image file. Size: ${file.length}");
        response = await _dfuSendControlData(Uint8List.fromList([0x06, 0x02]));
      }
    } catch (ex) {
      _log.warning("Couldn't send DFU create command. $ex");
      throw ("Couldn't create DFU file on device");
    }

    final maxSize = ByteData.view(response.buffer).getUint32(3, Endian.little);
    var offset = ByteData.view(response.buffer).getUint32(7, Endian.little);
    final crc = ByteData.view(response.buffer).getUint32(11, Endian.little);

    _log.fine("Received allowed size: $maxSize, offset: $offset, CRC: $crc");

    while (offset < file.length) {
      final chunkSize = min(maxSize, file.length - offset);
      final chunkCrc = getCrc32(file.sublist(0, offset + chunkSize));

      // Create command with size
      final chunkSizeAsBytes = [
        chunkSize & 0xFF,
        chunkSize >> 8 & 0xFF,
        chunkSize >> 16 & 0xff,
        chunkSize >> 24 & 0xff
      ];

      try {
        if (isInitFile) {
          await _dfuSendControlData(
              Uint8List.fromList([0x01, 0x01, ...chunkSizeAsBytes]));
        } else {
          await _dfuSendControlData(
              Uint8List.fromList([0x01, 0x02, ...chunkSizeAsBytes]));
        }
      } catch (_) {
        throw ("Couldn't issue DFU create command");
      }

      // Split chunk into packets of MTU size
      final packetSize = device.mtuNow - 3;
      final packets = (chunkSize / packetSize).ceil();

      for (var p = 0; p < packets; p++) {
        final fileStart = offset + p * packetSize;
        var fileEnd = fileStart + packetSize;

        // The last packet could be smaller
        if (fileEnd - offset > maxSize) {
          fileEnd -= fileEnd - offset - maxSize;
        }

        // The last part of the file could also be smaller
        if (fileEnd > file.length) {
          fileEnd = file.length;
        }

        final fileSlice = file.sublist(fileStart, fileEnd);

        final percentDone = (100 / file.length) * offset;
        yield percentDone;

        _log.fine(
            "Sending ${fileSlice.length} bytes of packet data. ${percentDone.toInt()}% Complete");

        await _dfuSendPacketData(fileSlice)
            .onError((_, __) => throw ("Couldn't send DFU data"));
      }

      // Calculate CRC
      try {
        response = await _dfuSendControlData(Uint8List.fromList([0x03]));
      } catch (_) {
        throw ("Couldn't get CRC from device");
      }
      offset = ByteData.view(response.buffer).getUint32(3, Endian.little);
      final returnedCrc =
          ByteData.view(response.buffer).getUint32(7, Endian.little);

      if (returnedCrc != chunkCrc) {
        throw ("CRC mismatch after sending this chunk");
      }

      // Execute command (The last command may disconnect which is normal)
      try {
        response = await _dfuSendControlData(Uint8List.fromList([0x04]));
      } catch (_) {}
    }

    _log.fine("DFU file sent");
  }

  Future<Uint8List> _dfuSendControlData(Uint8List data) async {
    try {
      _log.fine("Sending ${data.length} bytes of DFU control data: $data");

      _dfuControl!.write(data, timeout: 1);

      final response = await _dfuControl!.onValueReceived
          .timeout(const Duration(seconds: 1))
          .first;

      return Uint8List.fromList(response);
    } catch (error) {
      return Future.error(BrilliantBluetoothException(error.toString()));
    }
  }

  Future<void> _dfuSendPacketData(Uint8List data) async {
    await _dfuPacket!.write(data, withoutResponse: true);
  }
   Future<BrilliantDfuDevice> _enableServices() async {
    if (Platform.isAndroid) {
      await device.requestMtu(512);
    }

    List<BluetoothService> services = await device.discoverServices();

    for (var service in services) {

      // If DFU
      if (service.serviceUuid == Guid('fe59')) {
        _log.fine("Found DFU service");
        for (var characteristic in service.characteristics) {
          if (characteristic.characteristicUuid ==
              Guid('8ec90001-f315-4f60-9fb8-838830daea50')) {
            _log.fine("Found DFU control characteristic");
            _dfuControl = characteristic;
            await characteristic.setNotifyValue(true);
            _log.fine("Enabled DFU control notifications");
          }
          if (characteristic.characteristicUuid ==
              Guid('8ec90002-f315-4f60-9fb8-838830daea50')) {
            _log.fine("Found DFU packet characteristic");
            _dfuPacket = characteristic;
          }
        }
      }
    }
    if (_dfuControl != null && _dfuPacket != null) {
      return this;
    }
    throw ("Incomplete set of services found");
   }
}