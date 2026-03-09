import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:frame_msg/tx/text_sprite_block.dart';

void main() {
  // necessary to initialize Dart UI for paragraph/Canvas use
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sprites have pixelData length matching width*height', () async {
    final tsb = TxTextSpriteBlock(width: 100, lineHeight: 20, fontSize: 16);

    // two very short lines guarantees there will be at least two sprites
    final sprites = await tsb.createTextSprites('foo\nbar');
    expect(sprites, isNotEmpty);

    for (var s in sprites) {
      expect(s.height, equals(tsb.lineHeight));
      expect(s.pixelData.length, equals(s.width * s.height),
          reason: 'pixelData should be padded to match the declared sprite height');
    }
  });

  test('no sprite begins with last row of previous sprite', () async {
    final tsb = TxTextSpriteBlock(width: 100, lineHeight: 20, fontSize: 16);
    final sprites = await tsb.createTextSprites('first\nsecond\nthird');
    expect(sprites.length, greaterThanOrEqualTo(2));

    for (int k = 1; k < sprites.length; k++) {
      final prev = sprites[k - 1];
      final curr = sprites[k];
      final int w = curr.width;
      final int lastRowStart = (prev.height - 1) * w;
      final int firstRowStart = 0;

      final prevLast = prev.pixelData.sublist(lastRowStart, lastRowStart + w);
      final currFirst = curr.pixelData.sublist(firstRowStart, firstRowStart + w);

      // if the previous last row is completely blank we can't make a meaningful
      // assertion, so only check when there's at least one non-zero pixel.
      if (prevLast.any((b) => b != 0)) {
        expect(currFirst, isNot(equals(prevLast)),
            reason: 'first row of sprite $k should not equal last row of sprite ${k - 1}');
      }
    }
  });
}
