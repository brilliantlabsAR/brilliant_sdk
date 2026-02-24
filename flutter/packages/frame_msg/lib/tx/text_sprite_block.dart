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
    final double dpr = ui.window.devicePixelRatio;

    // 1. Force a massive line height to space lines far apart.
    // This guarantees ascenders/descenders from adjacent lines
    // won't bleed into the current line's isolated bounding box.
    final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: textAlign,
      textDirection: textDirection,
      fontFamily: fontFamily,
      fontSize: _fontSize.toDouble(),
      height: 5.0, // Massive multiplier to isolate lines
    ));

    paragraphBuilder.addText(text);
    final ui.Paragraph paragraph = paragraphBuilder.build();

    paragraph.layout(ui.ParagraphConstraints(width: width.toDouble()));
    List<ui.LineMetrics> lineMetrics = paragraph.computeLineMetrics();

    if (lineMetrics.isEmpty) {
      return sprites;
    }

    // 2. Choose a fixed baseline for all lines in this block.
    // Placing the baseline at 80% of the line height is standard.
    // For a 16px line height, this puts the baseline at Y=13,
    // leaving 13px for ascenders and 3px for descenders.
    final double fixedBaseline = (_lineHeight * 0.8).roundToDouble();

    for (var line in lineMetrics) {
      final int lineWidth = line.width.ceil();

      // check for non-blank lines
      if (lineWidth > 0) {
        final pictureRecorder = ui.PictureRecorder();
        final canvas = ui.Canvas(pictureRecorder);

        // Scale the canvas by DPR so the text is rendered at high fidelity
        canvas.scale(dpr);

        // Clip the canvas exactly to our sprite dimensions
        canvas.clipRect(Rect.fromLTWH(0, 0, lineWidth.toDouble(), _lineHeight.toDouble()));

        // 3. Align the line's specific baseline exactly to our fixedBaseline
        canvas.translate(-line.left, fixedBaseline - line.baseline);

        canvas.drawParagraph(paragraph, ui.Offset.zero);
        final ui.Picture picture = pictureRecorder.endRecording();

        final int scaledWidth = (lineWidth * dpr).round();
        final int scaledHeight = (_lineHeight * dpr).round();
        final ui.Image image = await picture.toImage(scaledWidth, scaledHeight);

        // Force RGBA for predictable byte-access on Android/iOS
        final ByteData? byteData = (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!;
        if (byteData == null) continue;

        final Uint8List pixels = byteData.buffer.asUint8List();
        final Uint8List linePixelData = Uint8List(lineWidth * _lineHeight);

        // 4. Downsample: Map the high-res buffer back to your 1-bit grid
        for (int y = 0; y < _lineHeight; y++) {
          for (int x = 0; x < lineWidth; x++) {
            // Calculate the "center" pixel of the DPR-scaled block
            // This ensures we aren't sampling an anti-aliased edge pixel
            int centerX = (x * dpr + dpr / 2).floor();
            int centerY = (y * dpr + dpr / 2).floor();
            
            // Index in the RGBA8888 byte array
            int pos = (centerY * scaledWidth + centerX) * 4;

            // Thresholding logic: 
            // iOS Impeller might need a slightly lower threshold (e.g., 100) 
            // if your fonts appear too thin.
            int threshold = 110; 
            linePixelData[y * lineWidth + x] = pixels[pos] >= threshold ? 1 : 0;
          }
        }

        sprites.add(TxSprite(
          width: lineWidth,
          height: _lineHeight,
          numColors: 2,
          paletteData: _getPalette().data,
          pixelData: linePixelData,
        ));
      } else {
        // zero-width line, a blank line in the text block
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
