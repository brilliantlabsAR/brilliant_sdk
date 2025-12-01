import 'dart:typed_data';
import 'dart:async';

import 'package:audio_clip_lc3/pcm_segment_buffer.dart';

void main() async {
  // Simulation parameters (matches the example app defaults)
  const sampleRateHz = 8000;
  const channels = 1;
  const frameDurationUs = 10000; // 10ms
  const bytesPerSample = 2;

  final samplesPerFrame = (sampleRateHz * frameDurationUs) ~/ 1000000;
  final frameSizeBytes = samplesPerFrame * channels * bytesPerSample;

  // Create a large first chunk (5 seconds)
  final int fiveSecBytes = sampleRateHz * 5 * bytesPerSample * channels;
  final largeChunk = Uint8List(fiveSecBytes);
  // Fill with a pattern so the buffer isn't all zeros (not necessary)
  for (int i = 0; i < largeChunk.length; i++) {
    largeChunk[i] = i & 0xFF;
  }

  final buffer = PcmSegmentBuffer();
  buffer.append(largeChunk);

  print('Appended large chunk: ${largeChunk.length} bytes. Frame size: $frameSizeBytes');

  final List<int> timestamps = [];
  final stopwatch = Stopwatch()..start();

  // Simulate the timer: try to consume one frame every 10ms until buffer empty
  while (buffer.bufferedBytes >= frameSizeBytes) {
    // Simulate 10ms tick
    await Future.delayed(Duration(milliseconds: 10));

    final dst = Uint8List(frameSizeBytes);
    final ok = buffer.readInto(dst, frameSizeBytes);
    if (!ok) break;

    timestamps.add(stopwatch.elapsedMilliseconds);
    // For a short run, also print every 10th timestamp to stdout
    if (timestamps.length <= 20 || timestamps.length % 50 == 0) {
      print('Frame ${timestamps.length} @ ${timestamps.last} ms');
    }
  }

  stopwatch.stop();
  print('Consumed ${timestamps.length} frames in ${stopwatch.elapsedMilliseconds} ms');

  // Print deltas for the first 50 frames
  print('First 50 inter-frame deltas (ms):');
  for (int i = 1; i < timestamps.length && i < 50; i++) {
    print('${timestamps[i] - timestamps[i - 1]}');
  }
}
