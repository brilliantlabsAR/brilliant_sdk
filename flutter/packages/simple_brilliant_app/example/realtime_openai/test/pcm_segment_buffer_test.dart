import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:realtime_openai/pcm_segment_buffer.dart';

void main() {
  test('append and read single segment', () {
    final buf = PcmSegmentBuffer();
    final seg = Uint8List.fromList([1, 2, 3, 4, 5]);
    buf.append(seg);
    expect(buf.bufferedBytes, equals(5));

    final dst = Uint8List(3);
    expect(buf.readInto(dst, 3), isTrue);
    expect(dst, equals([1, 2, 3]));
    expect(buf.bufferedBytes, equals(2));

    final dst2 = Uint8List(2);
    expect(buf.readInto(dst2, 2), isTrue);
    expect(dst2, equals([4, 5]));
    expect(buf.isEmpty, isTrue);
  });

  test('read across segments', () {
    final buf = PcmSegmentBuffer();
    buf.append(Uint8List.fromList([1, 2]));
    buf.append(Uint8List.fromList([3, 4, 5]));
    expect(buf.bufferedBytes, equals(5));

    final dst = Uint8List(4);
    expect(buf.readInto(dst, 4), isTrue);
    expect(dst, equals([1, 2, 3, 4]));
    expect(buf.bufferedBytes, equals(1));

    final dst2 = Uint8List(1);
    expect(buf.readInto(dst2, 1), isTrue);
    expect(dst2, equals([5]));
    expect(buf.isEmpty, isTrue);
  });

  test('insufficient data returns false and leaves buffer intact', () {
    final buf = PcmSegmentBuffer();
    buf.append(Uint8List.fromList([1, 2, 3]));
    final dst = Uint8List(5);
    expect(buf.readInto(dst, 5), isFalse);
    expect(buf.bufferedBytes, equals(3));
  });

  test('clear empties the buffer', () {
    final buf = PcmSegmentBuffer();
    buf.append(Uint8List.fromList([1, 2, 3]));
    buf.clear();
    expect(buf.isEmpty, isTrue);
    expect(buf.bufferedBytes, equals(0));
  });
}
