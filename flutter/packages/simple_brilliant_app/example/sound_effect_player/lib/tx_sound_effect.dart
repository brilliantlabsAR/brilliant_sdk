import 'dart:convert';
import 'dart:typed_data';

import 'package:brilliant_msg/tx_msg.dart';

/// A message directing the frameside app to play one of the firmware's
/// built-in sfxr sound effect presets (pickup, laser, explosion, powerup,
/// hit, jump, blip) via frame.sound.play().
class TxSoundEffect extends TxMsg {
  /// firmware sound preset name, e.g. 'jump'
  final String effect;

  /// 32-bit seed for the sound generator: the same effect and seed
  /// always reproduce the same sound
  final int seed;

  TxSoundEffect({required this.effect, required this.seed})
      : assert(seed >= 0 && seed <= 0xFFFFFFFF);

  @override
  Uint8List pack() {
    final effectBytes = utf8.encode(effect);
    final bytes = Uint8List(4 + effectBytes.length);
    ByteData.sublistView(bytes).setUint32(0, seed); // big-endian
    bytes.setAll(4, effectBytes);
    return bytes;
  }
}
