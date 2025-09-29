import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class ApiService {
  final String endpointUrl;

  ApiService({required this.endpointUrl});

  Future<String> processImage({
    required List<int> imageBytes,
    String fileName = 'image.jpg',
  }) async {
    // Create multipart request
    final request = http.MultipartRequest('POST', Uri.parse(endpointUrl));

    // Add image file
    final multipartFile = http.MultipartFile.fromBytes(
      'image',
      imageBytes,
      filename: fileName,
      contentType: MediaType('image', 'jpeg'),
    );
    request.files.add(multipartFile);

    // Send request
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception('API call returned status ${response.statusCode}: ${response.body}');
    }

    return response.body;
  }
}