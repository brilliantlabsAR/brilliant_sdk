import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart';

import 'lc3_bindings.dart';
import 'pcm_segment_buffer.dart';

final _log = Logger("lc3_encoder");

/// Configuration passed from the UI isolate to the encoder isolate.
class _IsolateConfig {
  final SendPort uiSendPort;
  final int sampleRateHz;
  final int channels;
  final int frameDurationUs;
  final int targetBitrate;

  _IsolateConfig({
    required this.uiSendPort,
    required this.sampleRateHz,
    required this.channels,
    required this.frameDurationUs,
    required this.targetBitrate,
  });
}

///
/// Manages the LC3 encoding isolate.
///
/// This is the "UI-side" class. You create an instance of this,
/// call init(), send it PCM data, and listen to its outputStream.
///
class Lc3EncoderService {
  Isolate? _isolate;
  final ReceivePort _uiReceivePort = ReceivePort();
  SendPort? _isolateSendPort;
  final Completer<void> _isolateReadyCompleter = Completer<void>();
  // user can provide a callback when they send final PCM data
  // to find out when all the corresponding LC3 data has been sent back
  Function? _doneCallback;

  // This stream emits encoded LC3 frames as Uint8List
  final StreamController<Uint8List> _outputStreamController =
      StreamController.broadcast();
  Stream<Uint8List> get outputStream => _outputStreamController.stream;

  /// Spawns the encoder isolate and sets up communication.
  Future<void> init({
    int sampleRateHz = 8000,
    int channels = 1,
    int frameDurationUs = 10000, // 10ms
    int targetBitrate = 32000, // 32 kbps
  }) async {
    final config = _IsolateConfig(
      uiSendPort: _uiReceivePort.sendPort,
      sampleRateHz: sampleRateHz,
      channels: channels,
      frameDurationUs: frameDurationUs,
      targetBitrate: targetBitrate,
    );

    _uiReceivePort.listen(_handleIsolateMessage);
    _isolate = await Isolate.spawn(_lc3EncoderIsolate, config);

    // Wait for the isolate to confirm it's ready and has sent its SendPort
    return _isolateReadyCompleter.future;
  }

  void _handleIsolateMessage(dynamic message) {
    if (message is SendPort) {
      _isolateSendPort = message;
      // Isolate is ready!
      _isolateReadyCompleter.complete();
    } else if (message is TransferableTypedData) {
      // This is an encoded LC3 frame. Materialize it back into a Uint8List.
      // This is a fast operation, not a full copy.
      // print the contents of the message as hex bytes
      final lc3Frame = message.materialize().asUint8List();
      _log.finest(() => "LC3 Frame: ${lc3Frame.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ')}");
      _outputStreamController.add(lc3Frame);
    } else if (message == "DONE") {
      _log.info("LC3 Encoder Isolate reported DONE, calling doneCallback");
      _doneCallback?.call();
    } else if (message is String) {
      // Log errors or status messages from the isolate
      _log.info(message);
    }
  }

  /// Sends a chunk of PCM data to the encoder isolate.
  /// This uses [TransferableTypedData] for a zero-copy transfer.
  void sendPcmChunk(Uint8List pcmChunk, {Function? onDone}) {
    if (_isolateSendPort == null) {
      _log.severe('Error: Isolate not ready. Call init() and wait.');
      return;
    }

    // Create a TransferableTypedData to send the chunk without copying.
    // The UI isolate will lose access to this pcmChunk's buffer.
    try {
      final transferablePcm = TransferableTypedData.fromList([pcmChunk]);
      _isolateSendPort!.send(transferablePcm);
    } catch (e) {
      // This can happen if the pcmChunk is not a "standard" Uint8List
      // (e.g., it's a view from a larger buffer).
      // As a fallback, we copy it.
      _log.severe('Could not transfer PCM chunk, falling back to copy. $e');
      final pcmCopy = Uint8List.fromList(pcmChunk);
      final transferablePcm = TransferableTypedData.fromList([pcmCopy]);
      _isolateSendPort!.send(transferablePcm);
    }

    if (onDone != null) {
      _doneCallback = onDone;
      _isolateSendPort!.send("REPORT_WHEN_DONE");
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
// --- ENCODER ISOLATE ENTRY POINT ---
// This function runs on the separate isolate.
// -----------------------------------------------------------------------------

Future<void> _lc3EncoderIsolate(_IsolateConfig config) async {
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
  // Assuming 16-bit PCM (2 bytes per sample)
  const int bytesPerSample = 2;
  const int pcmFormat = LC3_PCM_FORMAT_S16;

  final int samplesPerFrame =
      (config.sampleRateHz * config.frameDurationUs) ~/ 1000000;
  final int pcmFrameSizeBytes =
      samplesPerFrame * config.channels * bytesPerSample;

  // Calculate target LC3 frame size from bitrate
  // (bitrate / 8 bits) * (duration_sec)
  final int lc3FrameSizeBytes =
      (config.targetBitrate / 8 * (config.frameDurationUs / 1000000)).ceil();

  _log.info("LC3 Frame Size: $lc3FrameSizeBytes bytes for "
      "${config.frameDurationUs}us at ${config.targetBitrate}bps");

  // --- Allocate native memory ---
  Pointer<Void> encoderMem;
  Pointer<Void> encoder;
  Pointer<Uint8> pcmInPtr;
  Pointer<Uint8> lc3OutPtr;

  try {
    // Allocate memory for the encoder struct itself
    final int encoderStructSize =
        bindings.lc3_encoder_size(config.frameDurationUs, config.sampleRateHz);

    if (encoderStructSize <= 0) {
      uiSendPort.send('Error: lc3_encoder_size returned $encoderStructSize');
      return; // Stop execution
    }

    encoderMem = calloc<Uint8>(encoderStructSize).cast<Void>();

    // Setup the encoder
    encoder = bindings.lc3_setup_encoder(
      config.frameDurationUs,
      config.sampleRateHz,
      config.sampleRateHz, //0, // no downsampling of PCM
      encoderMem,
    );

    if (encoder == nullptr) {
      uiSendPort.send('Error: Failed to setup LC3 encoder.');
      calloc.free(encoderMem);
      return;
    }

    // Allocate persistent native buffers for input and output
    pcmInPtr = calloc<Uint8>(pcmFrameSizeBytes);
    lc3OutPtr = calloc<Uint8>(lc3FrameSizeBytes);
    
    _log.info("LC3 Frame Size: $lc3FrameSizeBytes bytes for "
        "${config.frameDurationUs}us at ${config.targetBitrate}bps - PCM Frame Size: $pcmFrameSizeBytes bytes");

  } catch (e) {
    uiSendPort.send('Error: Failed to set up encoder: $e');
    return;
  }

  // Segmented buffer: maintain a list of Uint8List segments with a head
  // offset to avoid reallocations/copies when appending large incoming
  // chunks. We keep pcmBufferedBytes to know when a full frame is
  // available. When consuming a frame we copy directly from segments into
  // the native input buffer (pcmInPtr) without creating a combined buffer.
  // Use the segmented buffer helper that provides append + readInto
  // semantics without reallocations on append.
  final PcmSegmentBuffer pcmBuffer = PcmSegmentBuffer();
  
  uiSendPort.send('Isolate initialized and ready.');
  //bool reportWhenDone = false;

  // --- Isolate Message Loop ---
  // This loop listens for incoming data and 'CLOSE' messages.
  await for (final dynamic message in isolateReceivePort) {
    if (message is TransferableTypedData) {
      // 1. Materialize the PCM chunk (zero-copy)
      final pcmChunk = message.materialize().asUint8List();

      // 2. Append it to our segmented buffer without reallocating existing
      // segments. We just push the new chunk as a segment.
      pcmBuffer.append(pcmChunk);

      // 3. Process as many full frames as we can right now
      // Check if we have at least one full frame in our segmented buffer
      while (pcmBuffer.bufferedBytes >= pcmFrameSizeBytes) {
        // Copy exactly pcmFrameSizeBytes from the segmented buffer into native
        // memory in one go (the helper will advance internal offsets).
        processSingleFrame(pcmInPtr, pcmFrameSizeBytes, pcmBuffer, bindings, encoder, pcmFormat, config.channels, lc3FrameSizeBytes, lc3OutPtr, uiSendPort);
      } 
    } else if (message == 'REPORT_WHEN_DONE') {
      // if we're done but there's not a whole frame of PCM, pad out this last frame
      // otherwise just wait for more data
      if (pcmBuffer.bufferedBytes > 0) {
        // Not enough data available for this tick. If we've been told to stop after
        // the buffer is drained, report it now.
        final int bytesNeeded = pcmFrameSizeBytes - pcmBuffer.bufferedBytes;
        final padding = Uint8List(bytesNeeded); // zeros
        pcmBuffer.append(padding);
        // Now we have enough for one last frame
        processSingleFrame(pcmInPtr, pcmFrameSizeBytes, pcmBuffer, bindings, encoder, pcmFormat, config.channels, lc3FrameSizeBytes, lc3OutPtr, uiSendPort);
      }
      uiSendPort.send("DONE");
    } else if (message == 'CLOSE') {
      break; // Exit the loop
    }
  }

  // --- Cleanup ---
  calloc.free(encoderMem);
  calloc.free(pcmInPtr);
  calloc.free(lc3OutPtr);  
  isolateReceivePort.close();
  uiSendPort.send('Isolate shutting down.');
}

/// Processes a single LC3 frame from the segmented PCM buffer, and returns
/// the encoded frame via the uiSendPort.
void processSingleFrame(Pointer<Uint8> pcmInPtr, int pcmFrameSizeBytes, PcmSegmentBuffer pcmBuffer, Lc3Bindings bindings, Pointer<Void> encoder, int pcmFormat, int channels, int lc3FrameSizeBytes, Pointer<Uint8> lc3OutPtr, SendPort uiSendPort) {
  // Copy exactly pcmFrameSizeBytes from the segmented buffer into native
  // memory in one go (the helper will advance internal offsets).
  final dst = pcmInPtr.asTypedList(pcmFrameSizeBytes);
  final ok = pcmBuffer.readInto(dst, pcmFrameSizeBytes);
  if (!ok) return; // should not happen because we checked bufferedBytes
  
  // Encode
  final int result = bindings.lc3_encode(
    encoder,
    pcmFormat,
    pcmInPtr.cast<Void>(),
    channels, // stride, in 16-bit mono samples (would be 2 if interleaved stereo)
    lc3FrameSizeBytes, // nbytes_out (maximum expected output)
    lc3OutPtr.cast<Void>(),
  );
  
  if (result >= 0) {
    final int outBytes = (result > 0) ? result : lc3FrameSizeBytes;
    final outputView = lc3OutPtr.asTypedList(outBytes);
    final transferableOutput = TransferableTypedData.fromList([outputView]);
    uiSendPort.send(transferableOutput);
  } else {
    uiSendPort.send('Error: lc3_encode failed with code $result');
  }
}