import 'dart:typed_data';

import '../tx_msg.dart';

/// A message containing only a single optional byte
/// suitable for signalling the frameside app to take some action
/// (e.g. toggle streaming, take a photo with default parameters etc.)
class TxCode extends TxMsg {
  int value;

  TxCode({this.value = 0});

  @override
  Uint8List pack() {
    return Uint8List.fromList([value & 0xFF]);
  }
}
