import 'dart:typed_data';

import '../tx_msg.dart';

/// A message containing a collection of camera settings suitable for requesting
/// the frameside app to take a photo with the specified settings
class TxCaptureSettings extends TxMsg {
  final int _resolution;
  final int _qualityIndex;
  final int _pan;
  final bool _raw;

  TxCaptureSettings({
      int resolution = 512, // any even number between 100 and 720
      int qualityIndex = 4, // zero-based index into [VERY_LOW, LOW, MEDIUM, HIGH, VERY_HIGH]
      int pan = 0, // any number between -140 and 140, where 0 represents a centered image
      bool raw = false,
      })
      : _resolution = resolution,
        _qualityIndex = qualityIndex,
        _pan = pan,
        _raw = raw;

  @override
  Uint8List pack() {
    // resolution has a range 100..720 and must be even so just map resolution~/2 to a Uint16 over 2 bytes
    int halfRes = _resolution ~/ 2;
    int intHalfResolutionMsb = (halfRes >> 8) & 0xFF;
    int intHalfResolutionLsb = halfRes & 0xFF;

    // pan has a range -140..140 so add 140 and map it to a Uint16 over 2 bytes 0..280
    int panShifted = _pan + 140;
    int intPanShiftedMsb = (panShifted >> 8) & 0xFF;
    int intPanShiftedLsb = panShifted & 0xFF;

    // 6 bytes of camera capture settings. sendMessage will prepend the data byte, msgCode to each packet
    // and the Uint16 payload length to the first packet
    return Uint8List.fromList([
      _qualityIndex & 0xFF,
      intHalfResolutionMsb,
      intHalfResolutionLsb,
      intPanShiftedMsb,
      intPanShiftedLsb,
      _raw ? 0x01 : 0x00,
    ]);
  }
}
