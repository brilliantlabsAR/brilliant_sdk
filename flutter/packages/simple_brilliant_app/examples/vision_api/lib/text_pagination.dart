import 'dart:math';

import 'package:simple_frame_app/text_utils.dart';

class TextPagination {
  final List<String> _originalLines = [];
  final int displayLinesPerPage;

  // Cached wrapped lines for efficiency, split into immutable and mutable parts
  final List<String> _immutableWrappedLines = [];
  List<String> _mutableWrappedLines = [];
  int _currentPageIndex = 0;

  TextPagination({
    this.displayLinesPerPage = 5,
  });

  void updateLastLine(String newLastLine) {
    // Replace the last line in originalLines and recompute mutable wrapped lines
    if (_originalLines.isNotEmpty) {
      _originalLines[_originalLines.length - 1] = newLastLine;
      _mutableWrappedLines = TextUtils.wrapText(newLastLine, 640, 4);
    }
  }

  void appendLine(String newLine) {
    // If there are mutable wrapped lines, transition them to immutable
    if (_mutableWrappedLines.isNotEmpty) {
      _immutableWrappedLines.addAll(_mutableWrappedLines);
      _mutableWrappedLines.clear();
    }

    // Add a new line to the original lines
    _originalLines.add(newLine);

    // Set the new line as the mutable wrapped lines
    _mutableWrappedLines = TextUtils.wrapText(newLine, 640, 4);
  }

  List<String> getCurrentPage() {
    // Combine immutable and mutable wrapped lines
    final allWrappedLines = [..._immutableWrappedLines, ..._mutableWrappedLines];

    int startIndex = _currentPageIndex * displayLinesPerPage;
    return allWrappedLines.sublist(
      startIndex,
      min(startIndex + displayLinesPerPage, allWrappedLines.length)
    );
  }

  bool hasNextPage() {
    final allWrappedLines = [..._immutableWrappedLines, ..._mutableWrappedLines];
    return (_currentPageIndex + 1) * displayLinesPerPage < allWrappedLines.length;
  }

  bool hasPreviousPage() {
    return _currentPageIndex > 0;
  }

  void nextPage() {
    if (hasNextPage()) {
      _currentPageIndex++;
    }
  }

  void previousPage() {
    if (hasPreviousPage()) {
      _currentPageIndex--;
    }
  }

  void clear() {
    // Reset all content to initial state
    _originalLines.clear();
    _immutableWrappedLines.clear();
    _mutableWrappedLines.clear();
    _currentPageIndex = 0;
  }

  int get totalPages {
    final allWrappedLines = [..._immutableWrappedLines, ..._mutableWrappedLines];
    return (allWrappedLines.length / displayLinesPerPage).ceil();
  }

  int get currentPageNumber => _currentPageIndex + 1;
}