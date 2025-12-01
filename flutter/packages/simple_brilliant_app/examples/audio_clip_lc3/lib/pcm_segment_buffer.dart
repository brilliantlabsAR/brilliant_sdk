import 'dart:typed_data';

/// A segmented PCM buffer that stores incoming chunks as separate
/// Uint8List segments to avoid reallocations on append. It supports
/// reading out an exact number of bytes into a destination buffer which
/// may span multiple segments. Consumed segments are dropped.
class PcmSegmentBuffer {
  final List<Uint8List> _segments = <Uint8List>[];
  int _headOffset = 0;
  int _buffered = 0;

  /// Append a chunk as a new segment. This does not copy the chunk.
  void append(Uint8List chunk) {
    if (chunk.isEmpty) return;
    _segments.add(chunk);
    _buffered += chunk.length;
  }

  /// Total bytes available in the buffer.
  int get bufferedBytes => _buffered;

  /// Return true if buffer is empty.
  bool get isEmpty => _buffered == 0;

  /// Read exactly [len] bytes into [dst]. Returns true on success, false
  /// if not enough data is available. [dst] must be at least [len]
  /// length. The read operation will advance internal offsets and free
  /// fully-consumed segments.
  bool readInto(Uint8List dst, int len) {
    if (_buffered < len) return false;

    int remaining = len;
    int dstPos = 0;

    while (remaining > 0) {
      final first = _segments.first;
      final available = first.length - _headOffset;
      final toCopy = (available <= remaining) ? available : remaining;

      dst.setRange(dstPos, dstPos + toCopy, first, _headOffset);

      dstPos += toCopy;
      remaining -= toCopy;
      _headOffset += toCopy;
      _buffered -= toCopy;

      if (_headOffset >= first.length) {
        // drop the consumed segment
        _segments.removeAt(0);
        _headOffset = 0;
      }
    }

    return true;
  }

  /// Clear the buffer fully.
  void clear() {
    _segments.clear();
    _headOffset = 0;
    _buffered = 0;
  }
}
