import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:image/image.dart' as img;
import '../tx_msg.dart';
import 'sprite.dart';

/// Represents an (optionally) multi-line block of text of a specified width and number of visible rows at a specified lineHeight
/// If the supplied text string is longer, only the last `displayRows` will be shown rendered and sent to Frame.
/// If the supplied text string has fewer than or equal to `displayRows`, only the number of actual rows will be rendered and sent to Frame
/// If any given line of text is shorter than width, the text Sprite will be set to the actual width required.
/// When sending TxTextSpriteBlock to Frame, the sendMessage() will send the header with block dimensions and line-by-line offsets
/// and the user then sends each line[] as a TxSprite message with the same msgCode as the Block, and the frame app will use the offsets
/// to place each line. By sending each line separately we can display them as they arrive, as well as reducing overall memory
/// requirement (each concat() call is smaller).
/// After calling the constructor, check `isNotEmpty` before calling `rasterize()` and sending the header or the sprites.
/// Sending a TextSpriteBlock with no lines is not intended usage.
/// `text` is trimmed (leading and trailing whitespace) before laying out the paragraph, but any blank lines
/// within the range of displayed rows will be sent as an empty (1px) TxSprite
class TxTextSpriteBlock extends TxMsg {
  final int _width;
  int get width => _width;
  final int _lineHeight;
  int get lineHeight => _lineHeight;
  final int _fontSize;
  int get fontSize => _fontSize;
  final int _maxDisplayLines;
  int get maxDisplayRows => _maxDisplayLines;
  final ui.TextAlign _textAlign;
  ui.TextAlign get textAlign => _textAlign;
  final ui.TextDirection _textDirection;
  ui.TextDirection get textDirection => _textDirection;
  final String? _fontFamily;
  String? get fontFamily => _fontFamily;

  static img.PaletteUint8? monochromePal;

  /// return a 2-color, 3-channel palette (just black then white)
  static img.PaletteUint8 _getPalette() {
    if (monochromePal == null) {
      monochromePal = img.PaletteUint8(2, 3);
      monochromePal!.setRgb(0, 0, 0, 0);
      monochromePal!.setRgb(1, 255, 255, 255);
    }

    return monochromePal!;
  }

  TxTextSpriteBlock({
      int width = 200,
      int lineHeight = 16,
      int fontSize = 12,
      int maxDisplayLines = 3,
      String? fontFamily,
      ui.TextAlign textAlign = ui.TextAlign.left,
      ui.TextDirection textDirection = ui.TextDirection.ltr})
      : _width = width,
        _fontSize = fontSize,
        _maxDisplayLines = maxDisplayLines,
        _fontFamily = fontFamily,
        _textAlign = textAlign,
        _textDirection = textDirection,
        _lineHeight = lineHeight;

  /// Since the Paragraph rasterizing to the Canvas, and the getting of the Image bytes
  /// are async functions, there needs to be an async function not just the constructor.
  /// Plus we want the caller to decide how many lines of a long paragraph to rasterize, and when.
  /// Text lines as TxSprites are returned as a List, and the caller can decide how many to send to Frame, and when.
  Future<List<TxSprite>> createTextSprites(String text) async {
    final List<TxSprite> sprites = [];

    final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: textAlign,
      textDirection: textDirection,
      fontFamily: fontFamily, // gets platform default if null
      fontSize: _fontSize.toDouble(), // Adjust font size as needed
    ));

    paragraphBuilder.addText(text);
    final ui.Paragraph paragraph = paragraphBuilder.build();

    paragraph.layout(ui.ParagraphConstraints(width: width.toDouble()));

    // work out height using metrics after paragraph.layout() call
    List<LineMetrics> lineMetrics= paragraph.computeLineMetrics();

    if (lineMetrics.isEmpty) {
      return sprites;
    }

    final endIndex = lineMetrics.length - 1;

    // Calculate the top and bottom boundaries for the selected lines
    double topBoundary = 0;
    double bottomBoundary = 0;

    // work out a clip rectangle
    topBoundary = lineMetrics[0].baseline - lineMetrics[0].ascent;
    bottomBoundary = lineMetrics[endIndex].baseline + lineMetrics[endIndex].descent;

    // Define the area to clip: a window over the selected lines
    final clipRect = Rect.fromLTWH(
      0, // Start from the left edge of the canvas
      topBoundary, // Start clipping from the top of the startLine
      width.toDouble(), // Full width of the paragraph
      bottomBoundary - topBoundary, // Height of the selected lines
    );

    final pictureRecorder = ui.PictureRecorder();
    final canvas = ui.Canvas(pictureRecorder);
    canvas.clipRect(clipRect);

    canvas.drawParagraph(paragraph, ui.Offset.zero);
    final ui.Picture picture = pictureRecorder.endRecording();

    final int totalHeight = (bottomBoundary - topBoundary).toInt();
    final int topOffset = topBoundary.toInt();

    final ui.Image image = await picture.toImage(_width, totalHeight);

    var byteData =
        (await image.toByteData(format: ui.ImageByteFormat.rawUnmodified))!;

    // loop over each requested line of text in the paragraph and create a TxSprite
    for (var line in lineMetrics) {
      final int tlX = line.left.toInt();
      final int tlY = (line.baseline - line.ascent).toInt();
      final int tlyShifted = tlY - topOffset;
      int lineWidth = line.width.toInt();
      int lineHeight = (line.ascent + line.descent).toInt();

      // check for non-blank lines
      if (lineWidth > 0 && lineHeight > 0) {
        var linePixelData = Uint8List(lineWidth * lineHeight);

        for (int i = 0; i < lineHeight; i++) {
          // take one row of the source image byteData, remembering it's in RGBA so 4 bytes per pixel
          // and remembering the origin of the image is the top of the startLine, so we need to
          // shift all the top-left Ys by that first Y offset.
          var sourceRow = byteData.buffer
              .asUint8List(((tlyShifted + i) * _width + tlX) * 4, lineWidth * 4);

          for (int j = 0; j < lineWidth; j++) {
            // take only every 4th byte because the source buffer is RGBA
            // and map it to palette index 1 if it's 128 or bigger (monochrome palette only, and text rendering will be anti-aliased)
            linePixelData[i * lineWidth + j] = sourceRow[4 * j] >= 128 ? 1 : 0;
          }
        }

        // make a Sprite out of the line and add to the list
        sprites.add(TxSprite(
          width: lineWidth,
          height: lineHeight,
          numColors: 2,
          paletteData: _getPalette().data,
          pixelData: linePixelData
        ));
      }
      else {
        // zero-width line, a blank line in the text block
        // so we make a 1x1 px sprite in the void color
        sprites.add(TxSprite(
          width: 1,
          height: 1,
          numColors: 2,
          paletteData: _getPalette().data,
          pixelData: Uint8List(1)
        ));
      }
    }

    return sprites;
  }

  /// Convert TxTextSpriteBlock back to a single image for testing/verification
  /// startLine and endLine are inclusive
  Future<Uint8List> toPngBytes({required List<TxSprite> rasterizedSprites}) async {
    if (rasterizedSprites.isEmpty) {
      throw Exception('rasterizedSprites is empty');
    }

    // use the heights of the TxSprites to compose the image
    int totalHeight = rasterizedSprites.fold(0, (sum, sprite) => sum + sprite.height);

    // create an image for the whole block
    var preview = img.Image(width: width, height: totalHeight);

    // copy in each of the sprites
    int currentY = 0;
    for (TxSprite sprite in rasterizedSprites) {
      img.compositeImage(preview, sprite.toImage(), dstY: currentY);
      currentY += sprite.height;
    }

    return img.encodePng(preview);
  }

  /// Corresponding parser should be called from frame_app data handler
  @override
  Uint8List pack() {
    int widthMsb = _width >> 8;
    int widthLsb = _width & 0xFF;
    int lineHeightMsb = _lineHeight >> 8;
    int lineHeightLsb = _lineHeight & 0xFF;

    // special marker for Block header 0xFF, width of the block, max display rows, num lines, offsets within block for each line
    return Uint8List.fromList([
      0xFF,
      widthMsb,
      widthLsb,
      lineHeightMsb,
      lineHeightLsb,
      _maxDisplayLines & 0xFF
    ]);
  }
}
