import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:logging/logging.dart';

final _log = Logger("RxAudio");

class RxAudio {

  // Frame to Phone flags
  final int nonFinalChunkFlag;
  final int finalChunkFlag;
  final bool streaming;
  StreamController<Uint8List>? _controller;

  RxAudio({
    this.nonFinalChunkFlag = 0x05,
    this.finalChunkFlag = 0x06,
    this.streaming = false
  });

  /// Attach this RxAudio to the Frame's dataResponse characteristic stream.
  /// If this RxAudio was created with `streaming: true` then the returned
  /// broadcast Stream will produce elements continuously, otherwise it will
  /// be a single subscription stream that produces a single Uint8List element
  /// containing the entire audio clip received.
  /// Both types of Stream are Done when the finalChunkFlag is received from
  /// Frame indicating the end of the audio feed
  Stream<Uint8List> attach(Stream<List<int>> dataResponse) {
    // TODO check for illegal state - attach() already called on this RxAudio etc?
    // might be possible though after a clean close(), do I want to prevent it?
    return streaming ?
      _audioDataStreamResponse(dataResponse) :
      _audioDataResponse(dataResponse);
  }

  /// Audio data stream with a single element of a raw audio clip
  Stream<Uint8List> _audioDataResponse(Stream<List<int>> dataResponse) {

    // the audio data as a list of bytes that accumulates with each packet
    BytesBuilder audioData = BytesBuilder(copy: false);
    int rawOffset = 0;

    // the subscription to the underlying data stream
    StreamSubscription<List<int>>? dataResponseSubs;

    // Our stream controller that transforms/accumulates the raw data into audio (as bytes)
    _controller = StreamController();

    _controller!.onListen = () {
      _log.fine('stream subscribed');
      dataResponseSubs = dataResponse
          .where(
              (data) => data[0] == nonFinalChunkFlag || data[0] == finalChunkFlag)
          .listen((data) {
        if (data[0] == nonFinalChunkFlag) {
          _log.finer(() => 'Non-final: ${data.length}');
          audioData.add(UnmodifiableListView(data.skip(1)));
          rawOffset += data.length - 1;
        }
        // the last chunk has a first byte of 8 so stop after this
        else if (data[0] == finalChunkFlag) {
          _log.finer(() => 'Final: ${data.length}');
          audioData.add(UnmodifiableListView(data.skip(1)));
          rawOffset += data.length - 1;

          // When full audio data is received, emit it and clear the buffer
          _controller!.add(audioData.takeBytes());
          rawOffset = 0;

          // and close the stream
          _controller!.close();
        }
        _log.finer(() => 'Chunk size: ${data.length - 1}, rawOffset: $rawOffset');
      }, onDone: _controller!.close, onError: _controller!.addError);
    };

    _controller!.onCancel = () {
      _log.fine('stream unsubscribed');
      dataResponseSubs?.cancel();
      _controller!.close();
    };

    return _controller!.stream;
  }

  /// Real-time Audio data stream
  /// A listener can subscribe and unsubscribe and resubscribe to the returned broadcast Stream
  /// multiple times. The Stream only is Done when the final chunk message code is sent
  /// from Frame
  Stream<Uint8List> _audioDataStreamResponse(Stream<List<int>> dataResponse) {

    // the subscription to the underlying data stream
    StreamSubscription<List<int>>? dataResponseSubs;

    // Our stream controller that transforms/accumulates the raw data into audio (as bytes)
    // It needs to be a broadcast stream so users can subscribe, unsubscribe, then resubscribe
    // to the same stream
    _controller = StreamController.broadcast();

    _controller!.onListen = () {
      _log.fine('stream subscribed');
      dataResponseSubs?.cancel();
      dataResponseSubs = dataResponse
        .where(
            (data) => data[0] == nonFinalChunkFlag || data[0] == finalChunkFlag)
        .listen((data) {
          // start or middle of an audio stream
          if (data[0] == nonFinalChunkFlag) {
            _log.finer(() => 'Non-final: ${data.length}');
            if (data.length % 2 != 1) {
              _log.severe('Unexpected odd length audio data payload chunk received: ${data.length - 1}');
            }
            _controller!.add(Uint8List.fromList(data.skip(1).toList()));
          }
          // the last chunk has a first byte of finalChunkFlag so stop after this
          else if (data[0] == finalChunkFlag) {

            _log.finer(() => 'Final: ${data.length}');

            if (data.length > 1) {
              _controller!.add(Uint8List.fromList(data.skip(1).toList()));
            }

            // upstream is done so close the downstream
            _log.fine('About to close stream');
            _controller!.close();
            _log.fine('stream closed');
          }
          // close or pass on errors if the upstream dataResponse closes/errors
        }, onDone: _controller!.close, onError: _controller!.addError);
    };

    _controller!.onCancel = () {
      _log.fine('stream unsubscribed');
      // unsubscribe from upstream dataResponse
      dataResponseSubs?.cancel();

      // don't close the controller, if the client re-listens to the returned Stream
      // then we re-subscribe to dataResponse in onListen and continue sending data
    };

    return _controller!.stream;
  }

  /// Detaches the RxAudio from the Frame dataResponse Stream permanently.
  /// For `streaming==false` RxAudios, this has no effect because the controller
  /// of the Stream closes when the single clip is completely received.
  /// For `streaming==true` RxAudios, after the RxAudio has been attached to
  /// dataResponse, the client can call listen() and cancel() many times and
  /// the controller for the stream will not be closed. But when finished, it
  /// can be closed with detach and cannot be listened to again.
  void detach() {
    _controller?.close();
  }

  /// Create the contents of a WAV files corresponding to the provided pcmData
  static Uint8List toWavBytes({required Uint8List pcmData, int sampleRate = 8000, int bitsPerSample = 16, int channels = 1}) {
    int byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    int dataSize = pcmData.length;
    int fileSize = 36 + dataSize;

    // WAV Header
    List<int> header = [
      // "RIFF" chunk descriptor
      0x52, 0x49, 0x46, 0x46, // "RIFF" in ASCII
      fileSize & 0xff, (fileSize >> 8) & 0xff, (fileSize >> 16) & 0xff, (fileSize >> 24) & 0xff, // Chunk size
      0x57, 0x41, 0x56, 0x45, // "WAVE" in ASCII

      // "fmt " sub-chunk
      0x66, 0x6d, 0x74, 0x20, // "fmt " in ASCII
      16, 0x00, 0x00, 0x00,   // Subchunk1Size (16 for PCM)
      0x01, 0x00,             // AudioFormat (1 for PCM)
      channels & 0xff, 0x00,   // NumChannels
      sampleRate & 0xff, (sampleRate >> 8) & 0xff, (sampleRate >> 16) & 0xff, (sampleRate >> 24) & 0xff, // SampleRate
      byteRate & 0xff, (byteRate >> 8) & 0xff, (byteRate >> 16) & 0xff, (byteRate >> 24) & 0xff, // ByteRate
      (channels * bitsPerSample ~/ 8) & 0xff, 0x00, // BlockAlign
      bitsPerSample & 0xff, 0x00, // BitsPerSample

      // "data" sub-chunk
      0x64, 0x61, 0x74, 0x61, // "data" in ASCII
      dataSize & 0xff, (dataSize >> 8) & 0xff, (dataSize >> 16) & 0xff, (dataSize >> 24) & 0xff, // Subchunk2Size
    ];

    // Combine header and PCM data
    return Uint8List.fromList(header + pcmData);
  }

}