import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../domain/models/pacifica_item.dart';

class PacificaRepository {
  final client = http.Client();
  final String apiUrl = 'https://starkey.digital/wp-json/wp/v2/posts?_embed';

  Future<List<PacificaItem>> fetchItems() async {
    try {
      final response = await client.get(Uri.parse(apiUrl));
      
      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        return jsonData.map((item) => PacificaItem.fromJson(item)).toList();
      } else {
        throw Exception('Failed to load items: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching items: $e');
    }
  }
}
