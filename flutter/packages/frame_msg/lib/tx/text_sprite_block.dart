import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'sprite.dart';
import 'package:image/image.dart' as img;

/// Abstract base class for text layout strategies
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
  
  /// Get the layout parameters for a specific line at Y position
  /// Returns null if the line is outside the displayable area
  ({int width, int xOffset})? getLineLayout(double lineY, double lineHeight);
}

/// Rectangular text layout for Frame display
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
    // Check if line fits within height
    if (lineY + lineHeight > height) {
      return null;
    }
    return (width: width, xOffset: 0);
  }
}

/// Circular text layout for Halo display
class CircularTextLayout extends TextLayout {
  final double circleMargin;
  
  late final double radius;
  late final double centerX;
  late final double centerY;
  
  CircularTextLayout({
    required super.width,
    required super.height,
    required super.fontSize,
    this.circleMargin = 15.0,
    super.fontFamily,
    super.textAlign = ui.TextAlign.center,
  }) {
    radius = (math.min(width, height) / 2.0) - circleMargin;
    centerX = width / 2.0;
    centerY = height / 2.0;
  }
  
  @override
  ({int width, int xOffset})? getLineLayout(double lineY, double lineHeight) {
    double distFromCenter = (lineY + lineHeight / 2) - centerY;
    
    if (distFromCenter.abs() > radius) {
      return null;
    }
    
    double halfWidth = math.sqrt(radius * radius - distFromCenter * distFromCenter);
    int lineWidth = (halfWidth * 2).floor();
    int xOffset = (centerX - halfWidth).floor();
    
    // Ensure minimum width for readability
    if (lineWidth < 20) return null;
    
    return (width: lineWidth, xOffset: xOffset);
  }
}

/// Unified text sprite block that works with any TextLayout
class TxTextSpriteBlock {
  final TextLayout layout;
  final String text;
  
  String _remainingText;
  
  TxTextSpriteBlock({
    required this.layout,
    required this.text,
  }) : _remainingText = text.trim();
  
  String get remainingText => _remainingText;
  bool get hasMoreText => _remainingText.isNotEmpty;
  
  /// Measure the next page of text without rasterizing
  /// Returns the page data and updates remainingText
  Future<PageData?> measureNextPage() async {
    if (_remainingText.isEmpty) return null;
    
    List<_LineData> lines = [];
    String textToLayout = _remainingText;
    String originalText = _remainingText; // Track what we started with
    
    // For circular layout, start from top of circle
    // For rectangular, start from 0
    double currentY = 0;
    if (layout is CircularTextLayout) {
      final circLayout = layout as CircularTextLayout;
      currentY = circLayout.centerY - circLayout.radius;
    }
    
    while (textToLayout.isNotEmpty && currentY < layout.height) {
      // Estimate line height for initial positioning
      double estimatedLineHeight = layout.fontSize * 1.4;
      var lineLayout = layout.getLineLayout(currentY, estimatedLineHeight);
      
      if (lineLayout == null) {
        // Outside displayable area - this shouldn't happen for rectangular,
        // but can happen for circular. Move to next Y position
        currentY += estimatedLineHeight;
        continue;
      }
      
      // Create a paragraph with this specific width to measure actual metrics
      final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: layout.textAlign,
        textDirection: ui.TextDirection.ltr,
        fontFamily: layout.fontFamily,
        fontSize: layout.fontSize.toDouble(),
      ));
      
      paragraphBuilder.addText(textToLayout);
      final paragraph = paragraphBuilder.build();
      paragraph.layout(ui.ParagraphConstraints(width: lineLayout.width.toDouble()));
      
      var lineMetrics = paragraph.computeLineMetrics();
      
      if (lineMetrics.isEmpty) break;
      
      // Take only the first line
      var firstLine = lineMetrics[0];
      double actualLineHeight = firstLine.ascent + firstLine.descent;
      
      // Check if this line will fit at current Y with actual height
      if (currentY + actualLineHeight > layout.height) {
        // Line doesn't fit, stop this page
        break;
      }
      
      // Re-check layout with actual line height to get proper width
      var actualLineLayout = layout.getLineLayout(currentY, actualLineHeight);
      if (actualLineLayout == null) {
        // Line doesn't fit with actual height, move to next position
        currentY += actualLineHeight;
        continue;
      }
      
      // Use the actual line layout
      lineLayout = actualLineLayout;
      
      // Get the text for this line by finding where the line breaks
      int endIndex = 0;
      if (lineMetrics.isNotEmpty) {
        // Find the end of the first line using getBoxesForRange
        final boxes = paragraph.getBoxesForRange(0, textToLayout.length);
        if (boxes.isNotEmpty) {
          // Find the last character index in the first line's box
          final firstLineBottom = boxes[0].bottom;
          double maxRight = 0;
          for (final box in boxes) {
            if (box.bottom == firstLineBottom && box.right > maxRight) {
              maxRight = box.right;
            }
          }
          // Get the character index at the end of the first line
          final pos = paragraph.getPositionForOffset(ui.Offset(maxRight, firstLineBottom - 1));
          endIndex = pos.offset;          
        } else {
          endIndex = textToLayout.length;
        }
      } else {
        endIndex = textToLayout.length;
      }

      if (endIndex <= 0) endIndex = 1; // Ensure progress
      
      // Extract line text and handle word breaks
      String lineText = textToLayout.substring(0, endIndex);
      
      // Try to break at last space if we're mid-word
      if (endIndex < textToLayout.length && 
          !_isWhitespace(textToLayout[endIndex])) {
        int lastSpace = lineText.lastIndexOf(' ');
        if (lastSpace > 0) {
          endIndex = lastSpace + 1;
          lineText = textToLayout.substring(0, endIndex);
        }
      }
      
      lineText = lineText.trim();
      textToLayout = textToLayout.substring(endIndex).trim();
      
      // Store line data
      lines.add(_LineData(
        text: lineText,
        width: lineLayout.width,
        xOffset: lineLayout.xOffset,
        yOffset: currentY.toInt(),
        lineHeight: actualLineHeight.toInt(),
      ));
      
      currentY += actualLineHeight;
    }
    
    if (lines.isEmpty) {
      // Couldn't fit any lines - this shouldn't happen normally
      // but prevent infinite loop by consuming at least one character
      if (textToLayout.isEmpty) {
        _remainingText = textToLayout.substring(1);
      }
      return null;
    }
    
    // Update remaining text - use the textToLayout that was modified by the loop
    _remainingText = textToLayout;
    
    return PageData._(lines: lines, layout: layout);
  }
  
  /// Measure and rasterize the next page in one call
  Future<PageData?> rasterizeNextPage() async {
    final page = await measureNextPage();
    if (page != null) {
      await page.rasterize();
    }
    return page;
  }
  
  bool _isWhitespace(String char) {
    return char == ' ' || char == '\t' || char == '\n' || char == '\r';
  }
  
  static img.PaletteUint8? _monochromePal;
  
  static img.PaletteUint8 _getPalette() {
    if (_monochromePal == null) {
      _monochromePal = img.PaletteUint8(2, 3);
      _monochromePal!.setRgb(0, 0, 0, 0);
      _monochromePal!.setRgb(1, 255, 255, 255);
    }
    return _monochromePal!;
  }
}

/// Represents a measured page of text that can be rasterized
class PageData {
  final List<_LineData> _lines;
  final TextLayout layout;
  final List<TxSprite> _sprites = [];
  
  PageData._({
    required List<_LineData> lines,
    required this.layout,
  }) : _lines = lines;
  
  bool get isEmpty => _lines.isEmpty;
  bool get isNotEmpty => _lines.isNotEmpty;
  int get numLines => _lines.length;
  List<TxSprite> get rasterizedSprites => _sprites;
  bool get isRasterized => _sprites.isNotEmpty;
  
  /// Get the text content of all lines in this page
  List<String> get lineTexts => _lines.map((line) => line.text).toList();
  
  /// Rasterize the measured lines to create TxSprites
  Future<void> rasterize() async {
    if (_sprites.isNotEmpty) {
      // Already rasterized
      return;
    }
    
    for (var lineData in _lines) {
      if (lineData.text.isEmpty) {
        // Empty line - create 1x1 sprite
        _sprites.add(TxSprite(
          width: 1,
          height: 1,
          numColors: 2,
          paletteData: TxTextSpriteBlock._getPalette().data,
          pixelData: Uint8List(1),
        ));
        continue;
      }

      // Always use the full layout width for the sprite
      int spriteWidth = layout.width;
      int spriteHeight = lineData.lineHeight;

      // Render paragraph at the line's width (for correct metrics)
      final paragraphBuilder = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: layout.textAlign,
        textDirection: ui.TextDirection.ltr,
        fontFamily: layout.fontFamily,
        fontSize: layout.fontSize.toDouble(),
      ));

      paragraphBuilder.addText(lineData.text);
      final paragraph = paragraphBuilder.build();
      paragraph.layout(ui.ParagraphConstraints(width: lineData.width.toDouble()));

      var metrics = paragraph.computeLineMetrics();
      if (metrics.isEmpty) continue;

      var firstLine = metrics[0];
      int lineWidth = firstLine.width.toInt();
      int lineHeight = (firstLine.ascent + firstLine.descent).toInt();

      if (lineWidth == 0 || lineHeight == 0) {
        // Degenerate line - create 1x1 sprite
        _sprites.add(TxSprite(
          width: 1,
          height: 1,
          numColors: 2,
          paletteData: TxTextSpriteBlock._getPalette().data,
          pixelData: Uint8List(1),
        ));
        continue;
      }

      // Render to a full-width canvas, offsetting the text
      final pictureRecorder = ui.PictureRecorder();
      final canvas = ui.Canvas(pictureRecorder);

      // Draw the paragraph at the correct x offset
      canvas.drawParagraph(paragraph, ui.Offset(lineData.xOffset.toDouble(), 0));
      final picture = pictureRecorder.endRecording();

      final image = await picture.toImage(spriteWidth, spriteHeight);
      var byteData = (await image.toByteData(format: ui.ImageByteFormat.rawUnmodified))!;

      // Convert to monochrome
      var linePixelData = Uint8List(spriteWidth * spriteHeight);
      for (int i = 0; i < spriteHeight; i++) {
        var sourceRow = byteData.buffer.asUint8List(i * spriteWidth * 4, spriteWidth * 4);
        for (int j = 0; j < spriteWidth; j++) {
          linePixelData[i * spriteWidth + j] = sourceRow[4 * j] >= 128 ? 1 : 0;
        }
      }

      _sprites.add(TxSprite(
        width: spriteWidth,
        height: spriteHeight,
        numColors: 2,
        paletteData: TxTextSpriteBlock._getPalette().data,
        pixelData: linePixelData,
      ));
    }
  }
  
  /// Convert to PNG for testing/verification
  Future<Uint8List> toPngBytes() async {
    if (_sprites.isEmpty) {
      await rasterize();
    }
    
    // Create an image for the whole page
    var preview = img.Image(
      width: layout.width, 
      height: layout.height, 
      numChannels: 4
    );
    
    // Copy in each of the sprites at their correct positions
    for (int i = 0; i < _lines.length; i++) {
      img.compositeImage(
        preview, 
        _sprites[i].toImage(),
        dstX: _lines[i].xOffset,
        dstY: _lines[i].yOffset,
        blend: img.BlendMode.direct,
      );
    }
    
    return img.encodePng(preview);
  }
  
  /// Pack for transmission
  Uint8List pack() {
    if (_sprites.isEmpty) {
      throw Exception('Sprites not rasterized: call rasterize() before pack()');
    }
    
    int widthMsb = layout.width >> 8;
    int widthLsb = layout.width & 0xFF;
    
    // Store x and y offsets for each line
    Uint8List offsets = Uint8List(_lines.length * 4);
    
    for (int i = 0; i < _lines.length; i++) {
      var line = _lines[i];
      offsets[4 * i] = line.xOffset >> 8;
      offsets[4 * i + 1] = line.xOffset & 0xFF;
      offsets[4 * i + 2] = line.yOffset >> 8;
      offsets[4 * i + 3] = line.yOffset & 0xFF;
    }
    
    // Block header: 0xFF, width (2 bytes), height (2 bytes), num lines, offsets
    return Uint8List.fromList([
      0xFF,
      widthMsb,
      widthLsb,
      layout.height >> 8,
      layout.height & 0xFF,
      _sprites.length & 0xFF,
      ...offsets
    ]);
  }
}

/// Internal line data storage
class _LineData {
  final String text;
  final int width;
  final int xOffset;
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
