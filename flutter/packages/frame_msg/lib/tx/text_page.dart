import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'sprite.dart';
import 'package:image/image.dart' as img;


/// Abstract base class for defining the geometry of a text layout area.
/// This allows for different shapes like rectangles and circles.
abstract class TextLayout {
  final int width;
  final int height;
  final int fontSize;
  final String? fontFamily;
  final ui.TextAlign textAlign;

  TextLayout({
    required this.width,
    required this.height,
    required this.fontSize,
    this.fontFamily,
    this.textAlign = ui.TextAlign.left,
  });

  /// The starting Y coordinate for laying out text.
  double get startY => 0.0;

  /// Gets the layout parameters (width and x-offset) for a line at a specific Y position.
  /// Returns null if the line is outside the displayable area.
  ({int width, int xOffset})? getLineLayout(double lineY, double lineHeight);
}

/// A standard rectangular text layout for the Frame device.
class RectangularTextLayout extends TextLayout {
  RectangularTextLayout({
    required super.width,
    required super.height,
    required super.fontSize,
    super.fontFamily,
    super.textAlign,
  });

  @override
  ({int width, int xOffset})? getLineLayout(double lineY, double lineHeight) {
    if (lineY < 0 || lineY + lineHeight > height) {
      return null; // Line is outside the vertical bounds.
    }
    return (width: width, xOffset: 0);
  }
}

/// A circular text layout, ideal for the Halo device. Text is constrained
/// within a circle inscribed in the defined width/height.
class CircularTextLayout extends TextLayout {
  final double circleMargin;
  late final double radius;
  late final double centerX;
  late final double centerY;

  CircularTextLayout({
    required super.width,
    required super.height,
    required super.fontSize,
    this.circleMargin = 15.0, // Margin from the edge of the canvas to the circle.
    super.fontFamily,
    super.textAlign = ui.TextAlign.center,
  }) {
    radius = (math.min(width, height) / 2.0) - circleMargin;
    centerX = width / 2.0;
    centerY = height / 2.0;
  }

  @override
  double get startY => centerY - radius;

  @override
  ({int width, int xOffset})? getLineLayout(double lineY, double lineHeight) {
    // Calculate the vertical distance from the center of the circle to the middle of the line.
    final double distFromCenter = (lineY + lineHeight / 2) - centerY;

    if (distFromCenter.abs() > radius) {
      return null; // Line is completely outside the circle.
    }

    // Use the Pythagorean theorem to calculate the half-width of the chord at this y-position.
    final double halfWidth = math.sqrt(radius * radius - distFromCenter * distFromCenter);
    final int lineWidth = (halfWidth * 2).floor();
    final int xOffset = (centerX - halfWidth).floor();

    // Avoid rendering text on very narrow lines near the top/bottom of the circle.
    if (lineWidth < fontSize) return null;

    return (width: lineWidth, xOffset: xOffset);
  }
}

/// Manages the process of laying out and rasterizing text into pages (TxSpriteBlocks).
/// It works with any `TextLayout` to support different display shapes.
class TxTextPage {
  final TextLayout layout;
  final String text;

  String _remainingText;

  TxTextPage({
    required this.layout,
    required this.text,
  }) : _remainingText = text.trim();

  /// The portion of the text that has not yet been processed into a page.
  String get remainingText => _remainingText;

  /// Returns true if there is more text to be laid out.
  bool get hasMoreText => _remainingText.isNotEmpty;

  /// Measures the next page of text and returns its data without rasterizing.
  /// This is useful for previewing content or getting layout information.
  Future<PageData?> measureNextPage() async {
    if (_remainingText.isEmpty) return null;

    final List<_LineData> lines = [];
    String textToLayout = _remainingText;
    double currentY = layout.startY;
    
    final double estimatedLineHeight = layout.fontSize * 1.4;

    while (textToLayout.isNotEmpty && currentY < layout.height) {
      // Get the available width for a line at the current Y position.
      var lineLayout = layout.getLineLayout(currentY, estimatedLineHeight);

      if (lineLayout == null) {
        // We have moved outside the drawable area, so this page is done.
        break;
      }
      
      // Use a Paragraph to measure the text for the current line.
      final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: layout.textAlign,
        fontFamily: layout.fontFamily,
        fontSize: layout.fontSize.toDouble(),
        textDirection: ui.TextDirection.ltr,
      ));
      paragraphBuilder.addText(textToLayout);
      final paragraph = paragraphBuilder.build();
      paragraph.layout(ui.ParagraphConstraints(width: lineLayout.width.toDouble()));
      
      // Get the metrics for the first line that fits within the constraints.
      final lineMetrics = paragraph.computeLineMetrics();
      if (lineMetrics.isEmpty) break; // No more text fits.

      final firstLine = lineMetrics.first;
      final double actualLineHeight = firstLine.height;

      // Final check to ensure this line actually fits vertically.
      if (currentY + actualLineHeight > layout.height) {
        break;
      }

      // Re-check the layout with the actual height for better accuracy, especially for circles.
      var finalLineLayout = layout.getLineLayout(currentY, actualLineHeight) ?? lineLayout;

      // Get the character range for the first line. This is the most reliable way
      // to determine where Flutter decided to break the line.
      final lineBreak = paragraph.getLineBoundary(const ui.TextPosition(offset: 0));
      int endIndex = lineBreak.end;
      
      if (endIndex == 0 && textToLayout.isNotEmpty) {
        // Failsafe for cases where not even one character fits. Consume one to prevent loops.
        endIndex = 1;
      }

      String lineText = textToLayout.substring(0, endIndex);

      // Refine word wrapping: if the line breaks in the middle of a word,
      // try to break at the previous space instead.
      if (endIndex < textToLayout.length) {
          final nextChar = textToLayout[endIndex];
          if (lineText.isNotEmpty && !_isWhitespace(nextChar) && !_isWhitespace(lineText[lineText.length - 1])) {
              int lastSpace = lineText.trimRight().lastIndexOf(' ');
              if (lastSpace != -1) {
                  // Re-measure endIndex to the character after the space.
                  endIndex = textToLayout.substring(0, lastSpace).length + 1;
                  lineText = textToLayout.substring(0, endIndex);
              }
          }
      }

      // Only add the line if it contains non-whitespace characters.
      final trimmedLine = lineText.trim();
      if (trimmedLine.isNotEmpty) {
        lines.add(_LineData(
          text: trimmedLine,
          width: finalLineLayout.width,
          xOffset: finalLineLayout.xOffset,
          yOffset: currentY.toInt(),
          lineHeight: actualLineHeight.toInt(),
        ));
      }

      // Advance Y position and update remaining text.
      currentY += actualLineHeight;
      textToLayout = textToLayout.substring(endIndex).trimLeft();
    }

    if (lines.isEmpty && _remainingText.isNotEmpty) {
      // This can happen if the first word is too long to fit on any line.
      // To prevent an infinite loop, we consume the text that was attempted.
      _remainingText = textToLayout;
      return null;
    }

    _remainingText = textToLayout;
    return PageData._(lines: lines, layout: layout);
  }
  
  /// Measures and rasterizes the next page in one call.
  Future<PageData?> rasterizeNextPage() async {
    final page = await measureNextPage();
    await page?.rasterize();
    return page;
  }

  bool _isWhitespace(String char) {
    return char == ' ' || char == '\t' || char == '\n' || char == '\r';
  }

  // Caches a monochrome palette for creating 1-bit sprites.
  static img.PaletteUint8? _monochromePal;
  static img.PaletteUint8 _getPalette() {
    return _monochromePal ??= img.PaletteUint8(2, 3)
      ..setRgb(0, 0, 0, 0)       // Black
      ..setRgb(1, 255, 255, 255); // White
  }
}

/// Represents a single, measured page of text that is ready to be rasterized into sprites.
class PageData {
  final List<_LineData> _lines;
  final TextLayout layout;
  final List<TxSprite> _sprites = [];
  bool _isRasterizing = false;

  PageData._({required List<_LineData> lines, required this.layout}) : _lines = lines;

  bool get isEmpty => _lines.isEmpty;
  bool get isRasterized => _sprites.isNotEmpty;
  List<TxSprite> get rasterizedSprites => _sprites;
  List<String> get lineTexts => _lines.map((line) => line.text).toList();

  /// Rasterizes the measured lines into a list of `TxSprite` objects.
  /// Each sprite represents one line of text.
  Future<void> rasterize() async {
    // If rasterization is already complete or is currently in progress, do nothing.
    // This prevents race conditions from concurrent calls.
    if (isRasterized || _isRasterizing) return;

    _isRasterizing = true;
    try {
      // This check is now mostly for safety; measureNextPage should prevent empty lines.
      for (final lineData in _lines) {
        if (lineData.text.isEmpty || lineData.lineHeight <= 0) {
          continue; // Skip invalid lines.
        }

        final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
          textAlign: layout.textAlign,
          fontFamily: layout.fontFamily,
          fontSize: layout.fontSize.toDouble(),
        ));
        paragraphBuilder.addText(lineData.text);
        final paragraph = paragraphBuilder.build();
        // Layout with the specific width calculated for this line.
        paragraph.layout(ui.ParagraphConstraints(width: lineData.width.toDouble()));

        final lineMetrics = paragraph.computeLineMetrics();
        if (lineMetrics.isEmpty) {
          continue; // No line metrics available, skip.
        }
        final firstLineMetrics = lineMetrics.first;
        
        // The canvas for the sprite should span the full width of the layout
        // to ensure consistent sprite dimensions.
        final int spriteWidth = firstLineMetrics.width.ceil();
        final int spriteHeight = lineData.lineHeight;

        if (spriteWidth <= 0 || spriteHeight <= 0) {
          continue; // Skip invalid sprite sizes.
        }

        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);

        // Draw the paragraph at its calculated horizontal offset.
        canvas.drawParagraph(paragraph, ui.Offset(-firstLineMetrics.left, 0));

        final picture = recorder.endRecording();
        final image = await picture.toImage(spriteWidth, spriteHeight);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

        if (byteData == null) continue;

        // Convert the 32-bit RGBA image to a 1-bit monochrome sprite.
        final pixels = Uint8List(spriteWidth * spriteHeight);
        final rgba = byteData.buffer.asUint8List();
        for (int i = 0; i < pixels.length; ++i) {
          // Use the red channel to determine color (assuming grayscale text).
          // A threshold of 128 determines black or white.
          pixels[i] = rgba[i * 4] >= 128 ? 1 : 0;
        }

        // After rasterizing, update the lineData with the final sprite geometry
        lineData.xOffset = (lineData.xOffset + firstLineMetrics.left).toInt();
        lineData.width = spriteWidth;

        _sprites.add(TxSprite(
          width: spriteWidth,
          height: spriteHeight,
          numColors: 2,
          paletteData: TxTextPage._getPalette().data,
          pixelData: pixels,
        ));
      }
    } finally {
      // Ensure the flag is always reset, even if an error occurs.
      _isRasterizing = false;
    }
  }

  /// Generates a single PNG image of the entire page for debugging or verification.
  Future<Uint8List> toPngBytes() async {
    if (!isRasterized) {
      await rasterize();
    }

    assert(lineTexts.length == _sprites.length);

    // Create a composite image for the whole page.
    final pageImage = img.Image(width: layout.width, height: layout.height, numChannels: 4);
    img.fill(pageImage, color: img.ColorRgba8(0,0,0,0)); // Transparent background

    for (int i = 0; i < _sprites.length; i++) {
      img.compositeImage(
        pageImage,
        _sprites[i].toImage(),
        dstX: _lines[i].xOffset,
        dstY: _lines[i].yOffset,
        // No dstX needed as the sprite itself is full-width with the text offset baked in.
      );
    }

    return img.encodePng(pageImage);
  }

  /// Packs the page layout data for transmission to a device.
  Uint8List pack() {
    if (!isRasterized) {
      throw Exception('Page must be rasterized before packing.');
    }

    final offsets = Uint8List(_lines.length * 4);
    for (int i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      offsets[4 * i] = line.xOffset >> 8;
      offsets[4 * i + 1] = line.xOffset & 0xFF;
      offsets[4 * i + 2] = line.yOffset >> 8;
      offsets[4 * i + 3] = line.yOffset & 0xFF;
    }

    return Uint8List.fromList([
      0xFF, // Header byte
      layout.width >> 8,
      layout.width & 0xFF,
      layout.height >> 8,
      layout.height & 0xFF,
      _sprites.length & 0xFF,
      ...offsets,
    ]);
  }
}

/// Internal data class to store measured information for a single line of text.
/// Its width and xOffset are mutable and are updated during rasterization.
class _LineData {
  final String text;
  int width;
  int xOffset;
  final int yOffset;
  final int lineHeight;

  _LineData({
    required this.text,
    required this.width,
    required this.xOffset,
    required this.yOffset,
    required this.lineHeight,
  });
}

