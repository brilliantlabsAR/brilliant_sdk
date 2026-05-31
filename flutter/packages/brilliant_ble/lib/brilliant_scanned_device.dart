import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BrilliantScannedDevice {
  BluetoothDevice device;
  int? rssi;

  BrilliantScannedDevice({
    required this.device,
    required this.rssi,
  });
}