import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:brilliant_msg/tx/code.dart';

void main() {
  test('check pack', () {
    final code = TxCode(value: 42);

    final packed = Uint8List(1);
    packed[0] = 42;
    expect(code.pack(), packed);
  });
}