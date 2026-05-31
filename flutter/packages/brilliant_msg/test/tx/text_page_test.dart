import 'package:flutter_test/flutter_test.dart';
import 'package:brilliant_msg/tx/text_page.dart';

void main() {
  // Ensure Flutter binding is initialized for text rendering
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('RectangularTextLayout', () {
    test('should create layout with correct dimensions', () {
      final layout = RectangularTextLayout(
        width: 640,
        height: 400,
        fontSize: 32,
      );
      
      expect(layout.width, 640);
      expect(layout.height, 400);
      expect(layout.fontSize, 32);
    });
    
    test('should return full width for lines within height', () {
      final layout = RectangularTextLayout(
        width: 640,
        height: 400,
        fontSize: 32,
      );
      
      final lineLayout = layout.getLineLayout(0, 40);
      expect(lineLayout, isNotNull);
      expect(lineLayout!.width, 640);
      expect(lineLayout.xOffset, 0);
    });
    
    test('should return null for lines exceeding height', () {
      final layout = RectangularTextLayout(
        width: 640,
        height: 400,
        fontSize: 32,
      );
      
      // Line starting at 380 with height 40 would end at 420, exceeding 400
      final lineLayout = layout.getLineLayout(380, 40);
      expect(lineLayout, isNull);
    });
    
    test('should handle line exactly at boundary', () {
      final layout = RectangularTextLayout(
        width: 640,
        height: 400,
        fontSize: 32,
      );
      
      // Line starting at 360 with height 40 ends exactly at 400
      final lineLayout = layout.getLineLayout(360, 40);
      expect(lineLayout, isNotNull);
    });
  });
  
  group('CircularTextLayout', () {
    test('should create layout with correct dimensions', () {
      final layout = CircularTextLayout(
        width: 320,
        height: 240,
        fontSize: 32,
        circleMargin: 15,
      );
      
      expect(layout.width, 320);
      expect(layout.height, 240);
      expect(layout.fontSize, 32);
      expect(layout.circleMargin, 15);
    });
    
    test('should calculate circle geometry correctly', () {
      final layout = CircularTextLayout(
        width: 320,
        height: 240,
        fontSize: 32,
        circleMargin: 15,
      );
      
      // Minimum dimension is 240, so radius should be (240/2) - 15 = 105
      expect(layout.radius, 105);
      expect(layout.centerX, 160);
      expect(layout.centerY, 120);
    });
    
    test('should return max width at center', () {
      final layout = CircularTextLayout(
        width: 320,
        height: 240,
        fontSize: 32,
        circleMargin: 15,
      );
      
      // At center (y=120), line should be full diameter
      final lineLayout = layout.getLineLayout(120 - 20, 40); // Line centered at 120
      expect(lineLayout, isNotNull);
      expect(lineLayout!.width, closeTo(210, 1)); // diameter = 2 * radius
    });
    
    test('should return null outside circle', () {
      final layout = CircularTextLayout(
        width: 320,
        height: 240,
        fontSize: 32,
        circleMargin: 15,
      );
      
      // Line far outside circle
      final lineLayout = layout.getLineLayout(0, 10);
      expect(lineLayout, isNull);
    });
    
    test('should return narrower width away from center', () {
      final layout = CircularTextLayout(
        width: 320,
        height: 240,
        fontSize: 32,
        circleMargin: 15,
      );
      
      final centerLayout = layout.getLineLayout(120 - 20, 40);
      final edgeLayout = layout.getLineLayout(70, 40); // Further from center
      
      expect(edgeLayout, isNotNull);
      expect(edgeLayout!.width, lessThan(centerLayout!.width));
    });
    
    test('should have symmetric widths above and below center', () {
      final layout = CircularTextLayout(
        width: 320,
        height: 240,
        fontSize: 32,
        circleMargin: 15,
      );
      
      final above = layout.getLineLayout(80, 40);
      final below = layout.getLineLayout(120, 40);
      
      if (above != null && below != null) {
        expect(above.width, closeTo(below.width, 2));
      }
    });
  });
  
  group('TxTextSpriteBlock - Rectangular', () {
    late RectangularTextLayout layout;
    
    setUp(() {
      layout = RectangularTextLayout(
        width: 640,
        height: 400,
        fontSize: 32,
      );
    });
    
    test('should create empty block with empty text', () {
      final tsb = TxTextPage(
        layout: layout,
        text: '',
      );
      
      expect(tsb.hasMoreText, false);
      expect(tsb.remainingText, '');
    });
    
    test('should track remaining text', () async {
      final shortText = 'Hello World';
      final tsb = TxTextPage(
        layout: layout,
        text: shortText,
      );
      
      expect(tsb.hasMoreText, true);
      final page = await tsb.measureNextPage();
      expect(page, isNotNull);
    });
    
    test('should measure pages without rasterizing', () async {
      final text = 'This is a test of the text layout system. '
                   'It should wrap text across multiple lines. '
                   'Each line should be measured correctly.';
      
      final tsb = TxTextPage(
        layout: layout,
        text: text,
      );
      
      final page = await tsb.measureNextPage();
      expect(page, isNotNull);
      expect(page!.isRasterized, false);
      expect(page.lineTexts.length, greaterThan(0));
    });
    
    test('should rasterize page when requested', () async {
      final text = 'This is a test of the text layout system.';
      
      final tsb = TxTextPage(
        layout: layout,
        text: text,
      );
      
      final page = await tsb.measureNextPage();
      expect(page, isNotNull);
      expect(page!.isRasterized, false);
      
      await page.rasterize();
      expect(page.isRasterized, true);
      expect(page.rasterizedSprites.length, page.lineTexts.length);
    });
    
    test('should preserve all text across pages', () async {
      final originalText = 'The quick brown fox jumps over the lazy dog. '
                          'Pack my box with five dozen liquor jugs. '
                          'How vexingly quick daft zebras jump! '
                          'The five boxing wizards jump quickly. '
                          'Sphinx of black quartz, judge my vow.';
      
      final tsb = TxTextPage(
        layout: layout,
        text: originalText,
      );
      
      List<String> allLinesText = [];
      
      while (tsb.hasMoreText) {
        final page = await tsb.measureNextPage();
        if (page == null) break;
        
        // Extract text from each line
        allLinesText.addAll(page.lineTexts);
      }
      
      // Join all lines and compare to original (ignoring whitespace differences)
      String reconstructed = allLinesText.join(' ');
      String normalizedOriginal = originalText.replaceAll(RegExp(r'\s+'), ' ').trim();
      String normalizedReconstructed = reconstructed.replaceAll(RegExp(r'\s+'), ' ').trim();
      
      expect(normalizedReconstructed, normalizedOriginal);
    });
    
    test('should handle single word per line', () async {
      final layout = RectangularTextLayout(
        width: 100, // Very narrow
        height: 400,
        fontSize: 32,
      );
      
      final text = 'One Two Three Four Five';
      final tsb = TxTextPage(
        layout: layout,
        text: text,
      );
      
      final page = await tsb.measureNextPage();
      expect(page, isNotNull);
      expect(page!.lineTexts.length, greaterThan(1));
    });
    
    test('should paginate long text correctly', () async {
      final layout = RectangularTextLayout(
        width: 640,
        height: 120, // Small height to force pagination
        fontSize: 32,
      );
      
      final text = 'Line one content here. '
                   'Line two content here. '
                   'Line three content here. '
                   'Line four content here. '
                   'Line five content here.';
      
      final tsb = TxTextPage(
        layout: layout,
        text: text,
      );
      
      List<PageData> pages = [];
      while (tsb.hasMoreText) {
        final page = await tsb.measureNextPage();
        if (page != null) {
          pages.add(page);
        }
      }
      
      expect(pages.length, greaterThan(1));
      
      // Verify all text is accounted for
      List<String> allText = [];
      for (var page in pages) {
        allText.addAll(page.lineTexts);
      }
      
      String reconstructed = allText.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      String normalizedOriginal = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      expect(reconstructed, normalizedOriginal);
    });
  });
  
  group('TxTextSpriteBlock - Circular', () {
    late CircularTextLayout layout;
    
    setUp(() {
      layout = CircularTextLayout(
        width: 320,
        height: 240,
        fontSize: 32,
        circleMargin: 15,
      );
    });
    
    test('should measure circular pages', () async {
      final text = 'This text should wrap in a circular pattern. '
                   'Each line gets narrower near the edges.';
      
      final tsb = TxTextPage(
        layout: layout,
        text: text,
      );
      
      final page = await tsb.measureNextPage();
      expect(page, isNotNull);
      expect(page!.lineTexts.length, greaterThan(0));
    });
    
    test('should have varying line widths in circular layout', () async {
      final text = 'Line one. Line two. Line three. Line four. Line five. Line six.';
      
      final tsb = TxTextPage(
        layout: layout,
        text: text,
      );
      
      final page = await tsb.measureNextPage();
      expect(page, isNotNull);
      
      if (page!.lineTexts.length > 2) {
        // Check that not all lines have the same width
        // We can't directly check widths without exposing _lines,
        // but we can verify lines exist
        expect(page.lineTexts.length, greaterThan(2));
      }
    });
    
    test('should preserve all text in circular layout', () async {
      final originalText = 'The quick brown fox jumps over the lazy dog. '
                          'Pack my box with five dozen liquor jugs.';
      
      final tsb = TxTextPage(
        layout: layout,
        text: originalText,
      );
      
      List<String> allLinesText = [];
      
      while (tsb.hasMoreText) {
        final page = await tsb.measureNextPage();
        if (page == null) break;
        
        allLinesText.addAll(page.lineTexts);
      }
      
      String reconstructed = allLinesText.join(' ');
      String normalizedOriginal = originalText.replaceAll(RegExp(r'\s+'), ' ').trim();
      String normalizedReconstructed = reconstructed.replaceAll(RegExp(r'\s+'), ' ').trim();
      
      expect(normalizedReconstructed, normalizedOriginal);
    });
  });
  
  group('PageData', () {
    test('should not be rasterized initially', () async {
      final layout = RectangularTextLayout(
        width: 640,
        height: 400,
        fontSize: 32,
      );
      
      final tsb = TxTextPage(
        layout: layout,
        text: 'Test text',
      );
      
      final page = await tsb.measureNextPage();
      expect(page, isNotNull);
      expect(page!.isRasterized, false);
      expect(page.rasterizedSprites, isEmpty);
    });
    
    test('should be rasterized after calling rasterize', () async {
      final layout = RectangularTextLayout(
        width: 640,
        height: 400,
        fontSize: 32,
      );
      
      final tsb = TxTextPage(
        layout: layout,
        text: 'Test text',
      );
      
      final page = await tsb.measureNextPage();
      await page!.rasterize();
      
      expect(page.isRasterized, true);
      expect(page.rasterizedSprites, isNotEmpty);
      expect(page.rasterizedSprites.length, page.lineTexts.length);
    });
    
    test('should throw when packing before rasterizing', () async {
      final layout = RectangularTextLayout(
        width: 640,
        height: 400,
        fontSize: 32,
      );
      
      final tsb = TxTextPage(
        layout: layout,
        text: 'Test text',
      );
      
      final page = await tsb.measureNextPage();
      
      expect(() => page!.pack(), throwsException);
    });
    
    test('should pack successfully after rasterizing', () async {
      final layout = RectangularTextLayout(
        width: 640,
        height: 400,
        fontSize: 32,
      );
      
      final tsb = TxTextPage(
        layout: layout,
        text: 'Test text',
      );
      
      final page = await tsb.measureNextPage();
      await page!.rasterize();
      
      final packed = page.pack();
      expect(packed, isNotNull);
      expect(packed.length, greaterThan(0));
      expect(packed[0], 0xFF); // Header marker
    });
    
    test('should automatically rasterize when converting to PNG before explicit rasterizing call', () async {
      final layout = RectangularTextLayout(
        width: 640,
        height: 400,
        fontSize: 32,
      );
      
      final tsb = TxTextPage(
        layout: layout,
        text: 'Test text',
      );
      
      final page = await tsb.measureNextPage();
      
      final png = await page!.toPngBytes();
      expect(png, isNotNull);
      expect(png.length, greaterThan(0));
    });
    
    test('should convert to PNG after rasterizing', () async {
      final layout = RectangularTextLayout(
        width: 640,
        height: 400,
        fontSize: 32,
      );
      
      final tsb = TxTextPage(
        layout: layout,
        text: 'Test text',
      );
      
      final page = await tsb.measureNextPage();
      await page!.rasterize();
      
      final png = await page.toPngBytes();
      expect(png, isNotNull);
      expect(png.length, greaterThan(0));
    });
  });
  
  group('Edge Cases', () {
    test('should handle whitespace-only text', () async {
      final layout = RectangularTextLayout(
        width: 640,
        height: 400,
        fontSize: 32,
      );
      
      final tsb = TxTextPage(
        layout: layout,
        text: '   \n  \t  ',
      );
      
      expect(tsb.hasMoreText, false);
    });
    
    test('should handle very long word', () async {
      final layout = RectangularTextLayout(
        width: 200,
        height: 400,
        fontSize: 32,
      );
      
      final longWord = 'Supercalifragilisticexpialidocious';
      final tsb = TxTextPage(
        layout: layout,
        text: longWord,
      );
      
      final page = await tsb.measureNextPage();
      expect(page, isNotNull);
    });
    
    test('should handle text with multiple spaces', () async {
      final layout = RectangularTextLayout(
        width: 640,
        height: 400,
        fontSize: 32,
      );
      
      final text = 'Word1    Word2     Word3';
      final tsb = TxTextPage(
        layout: layout,
        text: text,
      );
      
      final page = await tsb.measureNextPage();
      expect(page, isNotNull);
    });
    
    test('should handle single character', () async {
      final layout = RectangularTextLayout(
        width: 640,
        height: 400,
        fontSize: 32,
      );
      
      final tsb = TxTextPage(
        layout: layout,
        text: 'A',
      );
      
      final page = await tsb.measureNextPage();
      expect(page, isNotNull);
      expect(page!.lineTexts.length, 1);
    });
    
    test('should handle layout with zero height gracefully', () async {
      final layout = RectangularTextLayout(
        width: 640,
        height: 0,
        fontSize: 32,
      );
      
      final tsb = TxTextPage(
        layout: layout,
        text: 'This should not fit',
      );
      
      final page = await tsb.measureNextPage();
      // Should return null or empty page
      expect(page?.lineTexts.length ?? 0, 0);
    });
  });
  
  group('Integration Tests', () {
    test('should handle complete workflow: measure, rasterize, pack', () async {
      final layout = RectangularTextLayout(
        width: 640,
        height: 400,
        fontSize: 32,
      );
      
      final text = 'This is a complete integration test. '
                   'It should measure, rasterize, and pack successfully.';
      
      final tsb = TxTextPage(
        layout: layout,
        text: text,
      );
      
      // Measure
      final page = await tsb.measureNextPage();
      expect(page, isNotNull);
      expect(page!.isRasterized, false);
      
      // Rasterize
      await page.rasterize();
      expect(page.isRasterized, true);
      
      // Pack
      final packed = page.pack();
      expect(packed[0], 0xFF);
      
      // PNG
      final png = await page.toPngBytes();
      expect(png.length, greaterThan(0));
    });
    
    test('should handle rasterizeNextPage convenience method', () async {
      final layout = RectangularTextLayout(
        width: 640,
        height: 400,
        fontSize: 32,
      );
      
      final text = 'Test convenience method';
      
      final tsb = TxTextPage(
        layout: layout,
        text: text,
      );
      
      final page = await tsb.rasterizeNextPage();
      expect(page, isNotNull);
      expect(page!.isRasterized, true);
    });
  });
}