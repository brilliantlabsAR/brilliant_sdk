import 'dart:convert';
import 'dart:typed_data';

import '../tx_msg.dart';

/// A message containing a String of plain text,
/// plus optional top-left corner position coordinates for the
/// text to be printed in the Frame display (Lua/1-based, i.e. [1,1] to [640,400])
/// plus an optional palette offset (1..15, 0/'VOID' is invalid), plus optional character spacing
class TxPlainText extends TxMsg {
  final String _text;
  final int _x, _y;
  final int _paletteOffset;
  final int _spacing;

  TxPlainText({required String text, int x = 1, int y = 1, int paletteOffset = 1, int spacing = 4}) : _text = text, _x = x, _y = y, _paletteOffset = paletteOffset, _spacing = spacing;

  @override
  Uint8List pack() {
    final stringBytes = utf8.encode(_text);
    final strlen = stringBytes.length;

    Uint8List bytes = Uint8List(6 + strlen);
    bytes[0] = _x >> 8;   // x msb
    bytes[1] = _x & 0xFF; // x lsb
    bytes[2] = _y >> 8;   // y msb
    bytes[3] = _y & 0xFF; // y lsb
    bytes[4] = _paletteOffset & 0x0F; // 1..15
    bytes[5] = _spacing & 0xFF;
    bytes.setRange(6, strlen + 6, stringBytes);

    return bytes;
  }
}
