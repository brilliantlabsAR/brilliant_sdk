import 'dart:typed_data';

import '../tx_msg.dart';

/// A message containing a collection of camera settings suitable for requesting
/// the frameside app enable auto exposure and gain with the specified settings
class TxAutoExpSettings extends TxMsg {
  final int _meteringIndex;
  final double _exposure;
  final double _exposureSpeed;
  final int _shutterLimit;
  final int _analogGainLimit;
  final double _whiteBalanceSpeed;
  final int _rgbGainLimit;

  TxAutoExpSettings({
      int meteringIndex = 1, // ['SPOT', 'CENTER_WEIGHTED', 'AVERAGE'];
      double exposure = 0.1, // 0.0 <= val <= 1.0
      double exposureSpeed = 0.45, // 0.0 <= val <= 1.0
      int shutterLimit = 16383, // 4 <= val <= 16383
      int analogGainLimit = 16, // 0 <= val <= 248
      double whiteBalanceSpeed = 0.5, // 0.0 <= val <= 1.0
      int rgbGainLimit = 287, // 0 <= val <= 1023
      })
      : _meteringIndex = meteringIndex,
        _exposure = exposure,
        _exposureSpeed = exposureSpeed,
        _shutterLimit = shutterLimit,
        _analogGainLimit = analogGainLimit,
        _whiteBalanceSpeed = whiteBalanceSpeed,
        _rgbGainLimit = rgbGainLimit;

  @override
  Uint8List pack() {
    // several doubles in the range 0 to 1, so map that to an unsigned byte 0..255
    // by multiplying by 255 and rounding
    int intExp = (_exposure * 255).round() & 0xFF;
    int intExpSpeed = (_exposureSpeed * 255).round() & 0xFF;
    int intWhiteBalanceSpeed = (_whiteBalanceSpeed * 255).round() & 0xFF;

    // shutter limit has a range 4..16384 so just map it to a Uint16 over 2 bytes
    int intShutLimMsb = (_shutterLimit >> 8) & 0xFF;
    int intShutLimLsb = _shutterLimit & 0xFF;

    // RGB gain limit has a range 0..1023 so just map it to a Uint16 over 2 bytes
    int intRgbGainLimMsb = (_rgbGainLimit >> 8) & 0xFF;
    int intRgbGainLimLsb = _rgbGainLimit & 0xFF;

    // 9 bytes of auto exposure settings. sendMessage will prepend the data byte & msgCode to each packet
    // and the Uint16 payload length to the first packet
    return Uint8List.fromList([
      _meteringIndex & 0xFF,
      intExp,
      intExpSpeed,
      intShutLimMsb,
      intShutLimLsb,
      _analogGainLimit & 0xFF,
      intWhiteBalanceSpeed,
      intRgbGainLimMsb,
      intRgbGainLimLsb,
    ]);
  }
}
