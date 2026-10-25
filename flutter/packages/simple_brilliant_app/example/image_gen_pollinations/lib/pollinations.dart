import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

final _log = Logger("Pol");

/// Fetches the specified image as an Uint8List of image file data
/// (Uint8List, null) or (null, errorMessage)
///
/// No API key is needed, but the free tier is rate limited per IP address
/// (one image every 45 seconds at the time of writing). Over the limit the
/// service replies 402 with a message saying how long to wait.
Future<(Uint8List?, String?)> fetchImage(String prompt) async {
  const width = 256;
  const height = 256;
  const seed = 42; // Each seed generates a new image variation

  var imageUri = 'https://image.pollinations.ai/prompt/${Uri.encodeComponent(prompt)}?width=$width&height=$height&seed=$seed';

  _log.fine(() => 'Requesting image: $imageUri');
  var stopwatch = Stopwatch()..start();

  final response = await http.get(Uri.parse(imageUri));

  _log.fine(() => 'Function took ${stopwatch.elapsed.inMilliseconds} ms to execute.');

  if (response.statusCode == 200) {
    return (response.bodyBytes, null);
  }
  else {
    return (null, _errorMessage(response));
  }
}

/// Pollinations error responses carry a JSON body with a readable message,
/// e.g. {"error":{"code":"FREE_LIMIT","message":"Free limit reached: ..."}}
String _errorMessage(http.Response response) {
  try {
    final message = jsonDecode(response.body)['error']['message'];
    if (message is String) return message;
  }
  catch (_) {}
  return 'Failed to load image. Status code: ${response.statusCode}';
}
