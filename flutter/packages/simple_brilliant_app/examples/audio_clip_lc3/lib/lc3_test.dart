import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'lc3_encoder_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configuration
  const int sampleRate = 16000;
  const int channels = 1;
  const int frameDurationUs = 10000; // 10ms frames
  const int targetBitrate = 32000;
  const double durationSeconds = 3.0; // length of generated tone
  const double toneFreqHz = 1760.0; // A6

  final service = Lc3EncoderService();
  await service.init(
    sampleRateHz: sampleRate,
    channels: channels,
    frameDurationUs: frameDurationUs,
    targetBitrate: targetBitrate,
  );

  final tempDir = await getTemporaryDirectory();
  final lc3TempFile = await File('${tempDir.path}/lc3_${DateTime.now().millisecondsSinceEpoch}.bin').create();  
  final outLc3 = lc3TempFile.openWrite();
  final pcmSamples = _generateSinePcm16(sampleRate, durationSeconds, toneFreqHz);
  // Keep a copy for WAV writing later
  final pcmBytesForWav = _int16ListToBytes(pcmSamples);

  // Listen for encoded frames and append to file
  final lc3WriteCompleter = Completer<void>();
  service.outputStream.listen((Uint8List frame) {
    outLc3.add(frame);
  }, onDone: () => lc3WriteCompleter.complete());

  // Prepare chunking parameters
  final int bytesPerSample = 2;
  final int samplesPerFrame = (sampleRate * frameDurationUs) ~/ 1000000;
  final int pcmFrameSizeBytes = samplesPerFrame * channels * bytesPerSample;

  // Send PCM in frame-sized chunks. Use copies when sending so we retain
  // pcmBytesForWav locally (TransferableTypedData will take ownership).
  final int totalBytes = pcmBytesForWav.length;
  int offset = 0;

  final sendingDone = Completer<void>();
  service.sendPcmChunk(Uint8List(0)); // ensure isolate is awake (no-op)

  // When we want to be notified that isolate drained all frames, pass onDone
  //service._doneCallback; // ignore - just to keep analyzer quiet

  // We'll use the API's onDone mechanism by passing a callback on the last chunk.
  while (offset < totalBytes) {
    final int end = (offset + pcmFrameSizeBytes <= totalBytes)
        ? offset + pcmFrameSizeBytes
        : totalBytes;
    final chunk = Uint8List.fromList(
        pcmBytesForWav.sublist(offset, end)); // copy for transfer safety

    final bool isLast = end >= totalBytes;
    if (isLast) {
      // Provide a callback: the service will send a "DONE" message when encoder
      // has produced all remaining LC3 frames; we use this to finish up.
      final doneCompleter = Completer<void>();
      service.sendPcmChunk(chunk, onDone: () {
        doneCompleter.complete();
      });
      await doneCompleter.future;
    } else {
      service.sendPcmChunk(chunk);
    }

    offset = end;
    // Small delay to avoid flooding the isolate with messages
    await Future.delayed(Duration(milliseconds: 1));
  }

  // Wait briefly for any remaining frames to arrive then close writer.
  // The onDone callback above should ensure we get "DONE" before proceeding.
  await Future.delayed(Duration(milliseconds: 200));
  await outLc3.flush();
  await outLc3.close();

  // Write WAV file for playback of original PCM
  final wavTempFile = await File('${tempDir.path}/sine_16k_mono_${DateTime.now().millisecondsSinceEpoch}.wav').create();  
  await wavTempFile.writeAsBytes(_buildWav(pcmBytesForWav, sampleRate, channels), flush: true);

  // Cleanup
  service.dispose();

  print('Done. Wrote: lc3_output.bin (encoded frames) and sine_16k_mono.wav (PCM).');
}

// Generate Int16List of mono sine wave samples
Int16List _generateSinePcm16(int sampleRate, double seconds, double freqHz) {
  final int totalSamples = (sampleRate * seconds).round();
  final Int16List samples = Int16List(totalSamples);
  final double amp = 0.9 * 0x7FFF; // keep below clipping
  for (int i = 0; i < totalSamples; i++) {
    final double t = i / sampleRate;
    final double v = amp * sin(2 * pi * freqHz * t);
    samples[i] = v.round().clamp(-0x8000, 0x7FFF);
  }
  return samples;
}

Uint8List _int16ListToBytes(Int16List list) {
  final ByteData bd = ByteData(2 * list.length);
  for (int i = 0; i < list.length; i++) {
    bd.setInt16(2 * i, list[i], Endian.little);
  }
  return bd.buffer.asUint8List();
}

// Build a simple 16-bit PCM WAV file bytes (mono or stereo)
List<int> _buildWav(Uint8List pcmBytes, int sampleRate, int channels) {
  final int byteRate = sampleRate * channels * 2;
  final int blockAlign = channels * 2;
  final int subchunk2Size = pcmBytes.length;
  final int chunkSize = 36 + subchunk2Size;
  final builder = BytesBuilder();

  // RIFF header
  builder.add(ascii('RIFF'));
  builder.add(_u32LE(chunkSize));
  builder.add(ascii('WAVE'));

  // fmt subchunk
  builder.add(ascii('fmt '));
  builder.add(_u32LE(16)); // subchunk1Size for PCM
  builder.add(_u16LE(1)); // audio format = PCM
  builder.add(_u16LE(channels));
  builder.add(_u32LE(sampleRate));
  builder.add(_u32LE(byteRate));
  builder.add(_u16LE(blockAlign));
  builder.add(_u16LE(16)); // bits per sample

  // data subchunk
  builder.add(ascii('data'));
  builder.add(_u32LE(subchunk2Size));
  builder.add(pcmBytes);

  return builder.toBytes();
}

// Helpers to build little-endian integers
List<int> _u16LE(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _u32LE(int v) =>
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

List<int> ascii(String s) => s.codeUnits;