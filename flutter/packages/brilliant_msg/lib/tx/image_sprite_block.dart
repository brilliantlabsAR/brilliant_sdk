import 'dart:typed_data';

import 'package:image/image.dart' as img;
import '../tx_msg.dart';
import 'sprite.dart';

/// Represents an image of a specified size sliced into a number of "sprite lines" of the full width of the image, and the specified height,
/// and possibly a final sprite line of a different height.
/// When sending TxImageSpriteBlock to Frame, the sendMessage() will send the header with block dimensions and sprite line height,
/// and the user then sends each line[] as a TxSprite message with the same msgCode as the Block, and the frame app will use the line height
/// to place each line. By sending each line separately we can display them as they arrive, as well as reducing overall memory
/// requirement (each concat() call is smaller).
/// Sending an ImageSpriteBlock with no lines is not intended usage.
class TxImageSpriteBlock extends TxMsg {
  final TxSprite _image;
  int get width => _image.width;
  int get height => _image.height;
  final int _spriteLineHeight;
  int get spriteLineHeight => _spriteLineHeight;

  final List<TxSprite> _spriteLines = [];
  List<TxSprite> get spriteLines => _spriteLines;

  /// intent for the Lua side to render the sprite lines as they are received,
  /// or wait until the whole image can be drawn
  final bool _progressiveRender;

  /// whether subsequent sprite lines after the first set can be sent to override the corresponding
  /// sprite lines from the original image, resulting in an updatable, dynamic image
  /// (whether progressively rendered, or not)
  /// As long as a new block header is not sent
  final bool _updatable;

  /// After construction, an ImageSpriteBlock should be tested that it has a non-zero number of
  /// sprite lines to send, otherwise it should not be sent
  bool get isEmpty => _spriteLines.isEmpty;

  /// After construction, an ImageSpriteBlock should be tested that it has a non-zero number of
  /// sprite lines to send, otherwise it should not be sent
  bool get isNotEmpty => _spriteLines.isNotEmpty;

  TxImageSpriteBlock({
    required TxSprite image,
    required int spriteLineHeight,
    bool progressiveRender = true,
    bool updatable = true
    }) : _image = image,
         _spriteLineHeight = spriteLineHeight,
         _progressiveRender = progressiveRender,
         _updatable = updatable {
    // process the full-sized sprite lines
    for (int i = 0; i < image.height ~/ spriteLineHeight; i++) {
      _spriteLines.add(
        TxSprite(
          width: image.width,
          height: spriteLineHeight,
          numColors: image.numColors,
          paletteData: image.paletteData,
          pixelData: image.pixelData.buffer.asUint8List(i * spriteLineHeight * image.width, spriteLineHeight * image.width)));
    }

    // if there is some final, shorter sprite line, process it too
    int finalHeight  = image.height % spriteLineHeight;
    if (finalHeight > 0) {
      _spriteLines.add(
        TxSprite(
          width: image.width,
          height: finalHeight,
          numColors: image.numColors,
          paletteData: image.paletteData,
          pixelData: image.pixelData.buffer.asUint8List(_spriteLines.length * spriteLineHeight * image.width, finalHeight * image.width)));
    }
  }

  /// Convert TxImageSpriteBlock back to a single image for testing/verification
  /// startLine and endLine are inclusive
  Future<Uint8List> toPngBytes() async {
    if (_spriteLines.isEmpty) {
      throw Exception('_spriteLines is empty: no image to convert toPngBytes()');
    }

    // create an image for the whole block
    var preview = img.Image(width: width, height: height);

    // copy in each of the sprites
    for (int i = 0; i <= _spriteLines.length; i++) {
      img.compositeImage(preview, _spriteLines[i].toImage(),
          dstY: (i * spriteLineHeight).toInt());
    }

    return img.encodePng(preview);
  }

  /// Corresponding parser should be called from frame_app data handler
  @override
  Uint8List pack() {
    if (_spriteLines.isEmpty) {
      throw Exception('_spriteLines is empty: no image to pack()');
    }

    // pack the width and height of the image (Uint16 each)
    int widthMsb = width >> 8;
    int widthLsb = width & 0xFF;
    int heightMsb = height >> 8;
    int heightLsb = height & 0xFF;

    // store the spriteLineHeight (Uint16)
    int spriteLineHeightMsb = spriteLineHeight >> 8;
    int spriteLineHeightLsb = spriteLineHeight & 0xFF;

    // special marker for Block header 0xFF, width and height of the block, spriteLineHeight, progressive rendering flag, updatable flag
    return Uint8List.fromList([
      0xFF,
      widthMsb,
      widthLsb,
      heightMsb,
      heightLsb,
      spriteLineHeightMsb,
      spriteLineHeightLsb,
      _progressiveRender ? 1 : 0,
      _updatable ? 1 : 0,
    ]);
  }
}
