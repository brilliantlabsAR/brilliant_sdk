import 'dart:async';
import 'dart:typed_data';

import 'package:image/image.dart' as image_lib;
import 'package:logging/logging.dart';

final _log = Logger("RxPhoto");

/// Returns a photo as a JPEG image from Frame.
/// Note: The camera sensor on Frame is rotated 90 degrees clockwise, so raw images are rotated, but by default
/// RxPhoto will correct this by rotating -90 degrees.
/// If you want to save the cost of copyRotate here you can specify upright=false in the constructor
/// since some ML packages allow for specifying the orientation of the image when passing it in.
/// Pairs with frame.camera.read_raw(), that is, jpeg header and footer
/// are not sent from Frame - only the content, using non-final and final message types
/// Jpeg header and footer are added in here on the client, so a quality level
/// must be provided to select the correct header. Returns a Stream with exactly one jpeg as bytes, then is Done
class RxPhoto {

  // Frame to Phone flags
  final int nonFinalChunkFlag;
  final int finalChunkFlag;

  /// Whether a raw image (without 623-byte jpeg header) will be returned from Frame, hence the corresponding header should be added
  /// Note that the first request for an image with a given resolution and quality level MUST be a complete image so the jpeg header can be saved
  /// and used for subsequent raw images of the same resolution and quality level
  final bool isRaw;

  /// The quality level of the jpeg image to be returned ['VERY_LOW', 'LOW', 'MEDIUM', 'HIGH', 'VERY_HIGH']
  final String quality;

  /// The resolution of the (square) raw image to be returned from Frame
  /// Must be an even number between 100 and 720 inclusive
  final int resolution;

  /// Whether to rotate the image 90 degrees counter-clockwise to make it upright before returning it
  final bool upright;

  StreamController<Uint8List>? _controller;

  /// A map of jpeg headers for each quality level which we fill as we receive the first image of each quality level/resolution
  /// Key format is 'quality_resolution' e.g. 'VERY_LOW_512'
  static final Map<String, Uint8List> jpegHeaderMap = {};
  static bool hasJpegHeader(String quality, int resolution) => jpegHeaderMap.containsKey('${quality}_$resolution');

  RxPhoto({
    this.nonFinalChunkFlag = 0x07,
    this.finalChunkFlag = 0x08,
    this.upright = true,
    this.isRaw = false,
    required this.quality,
    required this.resolution,
  });

  /// Attach this RxPhoto to the Frame's dataResponse characteristic stream.
  /// If `isRaw` is true, then quality and resolution must be specified and match the raw image requested from Frame
  /// so that the correct jpeg header can be prepended.
  Stream<Uint8List> attach(Stream<List<int>> dataResponse) {
    // TODO check for illegal state - attach() already called on this RxPhoto etc?
    // might be possible though after a clean close(), do I want to prevent it?

    // the image data as a list of bytes that accumulates with each packet
    List<int> imageData = List.empty(growable: true);
    int rawOffset = 0;

    // if isRaw is true, a jpeg header must be prepended to the raw image data
    if (isRaw) {
      // fetch the jpeg header for this quality level and resolution
      String key = '${quality}_$resolution';

      if (!jpegHeaderMap.containsKey(key)) {
        throw Exception('No jpeg header found for quality level $quality and resolution $resolution - request full jpeg once before requesting raw');
      }

      // add the jpeg header bytes for this quality level (623 bytes)
      imageData.addAll(jpegHeaderMap[key]!);
    }

    // the subscription to the underlying data stream
    StreamSubscription<List<int>>? dataResponseSubs;

    // Our stream controller that transforms/accumulates the raw data into images (as bytes)
    _controller = StreamController();

    _controller!.onListen = () {
      _log.fine('ImageDataResponse stream subscribed');
      dataResponseSubs = dataResponse
          .where(
              (data) => data[0] == nonFinalChunkFlag || data[0] == finalChunkFlag)
          .listen((data) {
        if (data[0] == nonFinalChunkFlag) {
          imageData += data.sublist(1);
          rawOffset += data.length - 1;
        }
        // the last chunk has a first byte of finalChunkFlag so stop after this
        else if (data[0] == finalChunkFlag) {
          imageData += data.sublist(1);
          rawOffset += data.length - 1;

          Uint8List finalImageBytes = Uint8List.fromList(imageData);

          // if this image is a full jpeg, save the jpeg header for this quality level and resolution
          // so that it can be prepended to raw images of the same quality level and resolution
          if (!isRaw) {
            String key = '${quality}_$resolution';
            if (!jpegHeaderMap.containsKey(key)) {
              jpegHeaderMap[key] = finalImageBytes.sublist(0, 623);
            }
          }

          // When full image data is received,
          // rotate the image counter-clockwise 90 degrees to make it upright
          // unless requested otherwise (to save processing)
          if (upright) {
            image_lib.Image? im = image_lib.decodeJpg(finalImageBytes);
            im = image_lib.copyRotate(im!, angle: 270);
            // emit the rotated jpeg bytes
            _controller!.add(image_lib.encodeJpg(im));
          }
          else {
            // emit the original rotation jpeg bytes
            _controller!.add(finalImageBytes);
          }

          // clear the buffer
          imageData.clear();
          rawOffset = 0;

          // and close the stream
          _controller!.close();
        }
        _log.finer(() => 'Chunk size: ${data.length - 1}, rawOffset: $rawOffset');
      }, onDone: _controller!.close, onError: _controller!.addError);
      _log.fine('Controller being listened to');
    };

    _controller!.onCancel = () {
      _log.fine('ImageDataResponse stream unsubscribed');
      dataResponseSubs?.cancel();
      _controller!.close();
    };

    return _controller!.stream;
  }
}