import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart';

import 'lc3_bindings.dart';
import 'pcm_segment_buffer.dart';

final _log = Logger("lc3_decoder");

/// Configuration passed from the UI isolate to the decoder isolate.
class _IsolateConfig {
  final SendPort uiSendPort;
  final int sampleRateHz;

  /// PCM output sample rate. When higher than [sampleRateHz], liblc3 upsamples
  /// the decoded PCM on the fly (e.g. decode 16kHz LC3 -> 24kHz PCM). Must be
  /// >= [sampleRateHz]; equal to it means no resampling.
  final int pcmSampleRateHz;
  final int channels;
  final int frameDurationUs;
  final int bitrate;

  _IsolateConfig({
    required this.uiSendPort,
    required this.sampleRateHz,
    required this.pcmSampleRateHz,
    required this.channels,
    required this.frameDurationUs,
    required this.bitrate,
  });
}

///
/// Manages the LC3 decoding isolate.
///
/// This is the "UI-side" class. You create an instance of this,
/// call init(), send it LC3-encoded bytes (any chunking - frame alignment
/// is handled internally), and listen to its outputStream of PCM16 frames.
///
class Lc3DecoderService {
  Isolate? _isolate;
  final ReceivePort _uiReceivePort = ReceivePort();
  SendPort? _isolateSendPort;
  final Completer<void> _isolateReadyCompleter = Completer<void>();

  // This stream emits decoded PCM16 frames as Uint8List
  final StreamController<Uint8List> _outputStreamController =
      StreamController.broadcast();
  Stream<Uint8List> get outputStream => _outputStreamController.stream;

  /// Spawns the decoder isolate and sets up communication.
  Future<void> init({
    int sampleRateHz = 16000,
    int? pcmSampleRateHz, // defaults to sampleRateHz (no resampling)
    int channels = 1,
    int frameDurationUs = 10000, // 10ms
    int bitrate = 32000, // 32 kbps
  }) async {
    final config = _IsolateConfig(
      uiSendPort: _uiReceivePort.sendPort,
      sampleRateHz: sampleRateHz,
      pcmSampleRateHz: pcmSampleRateHz ?? sampleRateHz,
      channels: channels,
      frameDurationUs: frameDurationUs,
      bitrate: bitrate,
    );

    _uiReceivePort.listen(_handleIsolateMessage);
    _isolate = await Isolate.spawn(_lc3DecoderIsolate, config);

    // Wait for the isolate to confirm it's ready and has sent its SendPort
    return _isolateReadyCompleter.future;
  }

  void _handleIsolateMessage(dynamic message) {
    if (message is SendPort) {
      _isolateSendPort = message;
      // Isolate is ready!
      _isolateReadyCompleter.complete();
    } else if (message is TransferableTypedData) {
      // This is a decoded PCM frame. Materialize it back into a Uint8List.
      final pcmFrame = message.materialize().asUint8List();
      _outputStreamController.add(pcmFrame);
    } else if (message is String) {
      // Log errors or status messages from the isolate
      _log.info(message);
    }
  }

  /// Sends a chunk of LC3-encoded bytes to the decoder isolate.
  /// This uses [TransferableTypedData] for a zero-copy transfer.
  void sendLc3Chunk(Uint8List lc3Chunk) {
    if (_isolateSendPort == null) {
      _log.severe('Error: Isolate not ready. Call init() and wait.');
      return;
    }

    try {
      final transferable = TransferableTypedData.fromList([lc3Chunk]);
      _isolateSendPort!.send(transferable);
    } catch (e) {
      // Fallback copy if the chunk is a view over a larger buffer.
      _log.severe('Could not transfer LC3 chunk, falling back to copy. $e');
      final copy = Uint8List.fromList(lc3Chunk);
      final transferable = TransferableTypedData.fromList([copy]);
      _isolateSendPort!.send(transferable);
    }
  }

  /// Shuts down the isolate and cleans up resources.
  void dispose() {
    _isolateSendPort?.send('CLOSE');
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _uiReceivePort.close();
    _outputStreamController.close();
  }
}

// -----------------------------------------------------------------------------
// --- DECODER ISOLATE ENTRY POINT ---
// This function runs on the separate isolate.
// -----------------------------------------------------------------------------

Future<void> _lc3DecoderIsolate(_IsolateConfig config) async {
  final uiSendPort = config.uiSendPort;
  final isolateReceivePort = ReceivePort();

  // Send our SendPort back to the UI isolate so it can talk to us
  uiSendPort.send(isolateReceivePort.sendPort);

  // --- Initialize liblc3 ---
  final Lc3Bindings bindings;
  try {
    bindings = Lc3Bindings();
  } catch (e) {
    uiSendPort.send('Error: Could not load liblc3. $e');
    return;
  }

  // --- Calculate frame sizes ---
  // 16-bit PCM (2 bytes per sample)
  const int bytesPerSample = 2;
  const int pcmFormat = LC3_PCM_FORMAT_S16;

  // PCM output frame is sized by the (possibly upsampled) PCM output rate
  final int samplesPerFrame =
      (config.pcmSampleRateHz * config.frameDurationUs) ~/ 1000000;
  final int pcmFrameSizeBytes =
      samplesPerFrame * config.channels * bytesPerSample;

  // LC3 frame size from bitrate: (bitrate / 8 bits) * duration_sec
  final int lc3FrameSizeBytes =
      (config.bitrate / 8 * (config.frameDurationUs / 1000000)).ceil();

  // --- Allocate native memory ---
  Pointer<Void> decoderMem;
  Pointer<Void> decoder;
  Pointer<Uint8> lc3InPtr;
  Pointer<Uint8> pcmOutPtr;

  try {
    // decoder size is keyed on the PCM (output) sample rate, per lc3.h
    final int decoderStructSize = bindings.lc3_decoder_size(
        config.frameDurationUs, config.pcmSampleRateHz);

    if (decoderStructSize <= 0) {
      uiSendPort.send('Error: lc3_decoder_size returned $decoderStructSize');
      return;
    }

    decoderMem = calloc<Uint8>(decoderStructSize).cast<Void>();

    decoder = bindings.lc3_setup_decoder(
      config.frameDurationUs,
      config.sampleRateHz, // coded stream rate
      config.pcmSampleRateHz, // PCM output rate (>= sampleRateHz upsamples)
      decoderMem,
    );

    if (decoder == nullptr) {
      uiSendPort.send('Error: Failed to setup LC3 decoder.');
      calloc.free(decoderMem);
      return;
    }

    lc3InPtr = calloc<Uint8>(lc3FrameSizeBytes);
    pcmOutPtr = calloc<Uint8>(pcmFrameSizeBytes);

    _log.info("LC3 Decoder: $lc3FrameSizeBytes byte LC3 frames "
        "(${config.sampleRateHz}Hz) -> $pcmFrameSizeBytes byte PCM frames "
        "(${config.frameDurationUs}us at ${config.pcmSampleRateHz}Hz)");
  } catch (e) {
    uiSendPort.send('Error: Failed to set up decoder: $e');
    return;
  }

  // Incoming LC3 bytes may arrive in arbitrary-sized BLE chunks; buffer them
  // and consume exactly one LC3 frame at a time to keep frame alignment.
  final PcmSegmentBuffer lc3Buffer = PcmSegmentBuffer();

  uiSendPort.send('Isolate initialized and ready.');

  // --- Isolate Message Loop ---
  await for (final dynamic message in isolateReceivePort) {
    if (message is TransferableTypedData) {
      final lc3Chunk = message.materialize().asUint8List();
      lc3Buffer.append(lc3Chunk);

      while (lc3Buffer.bufferedBytes >= lc3FrameSizeBytes) {
        final dst = lc3InPtr.asTypedList(lc3FrameSizeBytes);
        final ok = lc3Buffer.readInto(dst, lc3FrameSizeBytes);
        if (!ok) break; // should not happen because we checked bufferedBytes

        // Decode (returns 0 on success, 1 if packet loss concealment applied)
        final int result = bindings.lc3_decode(
          decoder,
          lc3InPtr.cast<Void>(),
          lc3FrameSizeBytes,
          pcmFormat,
          pcmOutPtr.cast<Void>(),
          config.channels, // stride, in 16-bit mono samples
        );

        if (result >= 0) {
          final outputView = pcmOutPtr.asTypedList(pcmFrameSizeBytes);
          final transferableOutput = TransferableTypedData.fromList([outputView]);
          uiSendPort.send(transferableOutput);
        } else {
          uiSendPort.send('Error: lc3_decode failed with code $result');
        }
      }
    } else if (message == 'CLOSE') {
      break; // Exit the loop
    }
  }

  // --- Cleanup ---
  calloc.free(decoderMem);
  calloc.free(lc3InPtr);
  calloc.free(pcmOutPtr);
  isolateReceivePort.close();
  uiSendPort.send('Isolate shutting down.');
}
