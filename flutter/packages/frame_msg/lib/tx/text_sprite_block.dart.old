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
  final int _fontSize;
  int get fontSize => _fontSize;
  final int _maxDisplayRows;
  int get maxDisplayRows => _maxDisplayRows;
  final List<TxSprite> _sprites = [];
  List<TxSprite> get rasterizedSprites => _sprites;

  late final ui.Paragraph _paragraph;
  late final List<ui.LineMetrics> _lineMetrics;
  int get numLines => _lineMetrics.length;

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

  /// After construction, a TextSpriteBlock should be tested that it has a non-zero number of
  /// sprite lines to send, otherwise it should not be rasterized nor sent
  bool get isEmpty => _lineMetrics.isEmpty;

  /// After construction, a TextSpriteBlock should be tested that it has a non-zero number of
  /// sprite lines to send, otherwise it should not be rasterized nor sent
  bool get isNotEmpty => _lineMetrics.isNotEmpty;

  TxTextSpriteBlock({
      required int width,
      required int fontSize,
      required int maxDisplayRows,
      String? fontFamily,
      ui.TextAlign textAlign = ui.TextAlign.left,
      ui.TextDirection textDirection = ui.TextDirection.ltr,
      required String text})
      : _width = width,
        _fontSize = fontSize,
        _maxDisplayRows = maxDisplayRows {
    final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: textAlign,
      textDirection: textDirection,
      fontFamily: fontFamily, // gets platform default if null
      fontSize: _fontSize.toDouble(), // Adjust font size as needed
    ));

    paragraphBuilder.addText(text);
    _paragraph = paragraphBuilder.build();

    _paragraph.layout(ui.ParagraphConstraints(width: width.toDouble()));

    // work out height using metrics after paragraph.layout() call
    _lineMetrics = _paragraph.computeLineMetrics();
  }

  /// Since the Paragraph rasterizing to the Canvas, and the getting of the Image bytes
  /// are async functions, there needs to be an async function not just the constructor.
  /// Plus we want the caller to decide how many lines of a long paragraph to rasterize, and when.
  /// Text lines as TxSprites are accumulated in this object.
  /// startLine and endLine are inclusive
  Future<void> rasterize({required int startLine, required int endLine}) async {
    if (isNotEmpty) {

      if (startLine < 0 || startLine > _lineMetrics.length - 1) throw Exception('startLine must be > 0 and < ${_lineMetrics.length}');
      if (endLine < startLine || endLine > _lineMetrics.length - 1) throw Exception('endLine must be >= startLine and < ${_lineMetrics.length}');

      // Calculate the top and bottom boundaries for the selected lines
      double topBoundary = 0;
      double bottomBoundary = 0;

      // work out a clip rectangle so we only draw the lines between startLine and endLine
      topBoundary = _lineMetrics[startLine].baseline - _lineMetrics[startLine].ascent;
      bottomBoundary = _lineMetrics[endLine].baseline + _lineMetrics[endLine].descent;

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

      canvas.drawParagraph(_paragraph, ui.Offset.zero);
      final ui.Picture picture = pictureRecorder.endRecording();

      final int totalHeight = (bottomBoundary - topBoundary).toInt();
      final int topOffset = topBoundary.toInt();

      final ui.Image image = await picture.toImage(_width, totalHeight);

      var byteData =
          (await image.toByteData(format: ui.ImageByteFormat.rawUnmodified))!;

      // loop over each requested line of text in the paragraph and create a TxSprite
      for (var line in _lineMetrics.sublist(startLine, endLine + 1)) {
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
          _sprites.add(TxSprite(
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
          _sprites.add(TxSprite(
            width: 1,
            height: 1,
            numColors: 2,
            paletteData: _getPalette().data,
            pixelData: Uint8List(1)
          ));
        }
      }
    }
  }

  /// Convert TxTextSpriteBlock back to a single image for testing/verification
  /// startLine and endLine are inclusive
  Future<Uint8List> toPngBytes({required int startLine, required int endLine}) async {
    if (_sprites.isEmpty) {
      throw Exception('_sprites is empty: call rasterize() before toPngBytes()');
    }

    // work out which range of lines we're drawing, and shift up by topOffset in Y
    final double topBoundary = _lineMetrics[startLine].baseline - _lineMetrics[startLine].ascent;
    final double bottomBoundary = _lineMetrics[endLine].baseline + _lineMetrics[endLine].descent;
    final int totalHeight = (bottomBoundary - topBoundary).toInt();
    final int topOffset = topBoundary.toInt();

    // create an image for the whole block
    var preview = img.Image(width: width, height: totalHeight);

    // copy in each of the sprites
    for (int i = startLine; i <= endLine; i++) {
      img.compositeImage(preview, rasterizedSprites[i].toImage(),
          dstY: (_lineMetrics[i].baseline - _lineMetrics[i].ascent - topOffset).toInt());
    }

    return img.encodePng(preview);
  }

  /// Corresponding parser should be called from frame_app data handler
  @override
  Uint8List pack() {
    if (_sprites.isEmpty) {
      throw Exception('_sprites is empty: call rasterize() before pack()');
    }

    int widthMsb = _width >> 8;
    int widthLsb = _width & 0xFF;

    // store the x (16-bit) and y (16-bit) offsets as pairs for each of the lines
    Uint8List offsets = Uint8List(_lineMetrics.length * 4);

    for (int i = 0; i < _lineMetrics.length; i++) {
      var lm = _lineMetrics[i];
      int xOffset = lm.left.toInt();
      int yOffset = (lm.baseline - lm.ascent).toInt();
      offsets[4 * i] = xOffset >> 8;
      offsets[4 * i + 1] = xOffset & 0xFF;
      offsets[4 * i + 2] = yOffset >> 8;
      offsets[4 * i + 3] = yOffset & 0xFF;
    }

    // special marker for Block header 0xFF, width of the block, max display rows, num lines, offsets within block for each line
    return Uint8List.fromList([
      0xFF,
      widthMsb,
      widthLsb,
      _maxDisplayRows & 0xFF,
      _sprites.length & 0xFF,
      ...offsets
    ]);
  }
}
