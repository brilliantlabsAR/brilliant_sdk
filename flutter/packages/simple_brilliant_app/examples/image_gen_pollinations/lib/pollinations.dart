import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

final _log = Logger("Pol");

/// Fetches the specified image as an Uint8List of image file data
/// (Uint8List, null) or (null, errorMessage)
Future<(Uint8List?, String?)> fetchImage(String prompt) async {
  const width = 340;
  const height = 340;
  const seed = 42; // Each seed generates a new image variation
  const model = 'flux'; // Using 'flux' as default if model is not provided

  var imageUri = 'https://pollinations.ai/p/${Uri.encodeComponent(prompt)}?width=$width&height=$height&seed=$seed&model=$model';

  _log.fine(() => 'Requesting image: $imageUri');
  var stopwatch = Stopwatch()..start();

  final response = await http.get(Uri.parse(imageUri));

  _log.fine(() => 'Function took ${stopwatch.elapsed.inMilliseconds} ms to execute.');

  if (response.statusCode == 200) {
    return (response.bodyBytes, null);
  }
  else {
    return (null, 'Failed to load image. Status code: ${response.statusCode}');
  }
}
