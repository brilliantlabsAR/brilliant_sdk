import 'dart:typed_data';

import '../tx_msg.dart';

/// A message containing a collection of camera settings suitable for requesting
/// the frameside app enable manual exposure and gain with the specified settings
class TxManualExpSettings extends TxMsg {
  final int _manualShutter;
  final int _manualAnalogGain;
  final int _manualRedGain;
  final int _manualGreenGain;
  final int _manualBlueGain;

  TxManualExpSettings({
      int manualShutter = 4096, // 4 <= val <= 16383
      int manualAnalogGain = 1, // 0 <= val <= 248
      int manualRedGain = 121, // 0 <= val <= 1023
      int manualGreenGain = 64, // 0 <= val <= 1023
      int manualBlueGain = 140, // 0 <= val <= 1023
      })
      : _manualShutter = manualShutter,
        _manualAnalogGain = manualAnalogGain,
        _manualRedGain = manualRedGain,
        _manualGreenGain = manualGreenGain,
        _manualBlueGain = manualBlueGain;

  @override
  Uint8List pack() {
    // manual shutter has a range 4..16384 so just map it to a Uint16 over 2 bytes
    int intManShutterMsb = (_manualShutter >> 8) & 0xFF;
    int intManShutterLsb = _manualShutter & 0xFF;

    // manual color gains have a range 0..1023 so just map them to a Uint16 over 2 bytes
    int intManRedGainMsb = (_manualRedGain >> 8) & 0x03;
    int intManRedGainLsb = _manualRedGain & 0xFF;
    int intManGreenGainMsb = (_manualGreenGain >> 8) & 0x03;
    int intManGreenGainLsb = _manualGreenGain & 0xFF;
    int intManBlueGainMsb = (_manualBlueGain >> 8) & 0x03;
    int intManBlueGainLsb = _manualBlueGain & 0xFF;

    // 9 bytes of manual exposure settings. sendMessage will prepend the data byte & msgCode to each packet
    // and the Uint16 payload length to the first packet
    return Uint8List.fromList([
      intManShutterMsb,
      intManShutterLsb,
      _manualAnalogGain & 0xFF,
      intManRedGainMsb,
      intManRedGainLsb,
      intManGreenGainMsb,
      intManGreenGainLsb,
      intManBlueGainMsb,
      intManBlueGainLsb,
    ]);
  }
}
