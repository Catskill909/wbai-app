import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../../domain/models/affiliate_station.dart';

class AffiliateRepository {
  static const String xmlUrl = 'https://docs.pacifica.org/affiliates/pacifica_affiliates.xml';

  Future<List<AffiliateStation>> fetchAffiliates() async {
    final response = await http.get(Uri.parse(xmlUrl));
    if (response.statusCode != 200) throw Exception('Failed to load affiliates');
    final document = XmlDocument.parse(response.body);
    return document.findAllElements('item').map((node) {
      return AffiliateStation(
        title: node.getElement('title')?.innerText ?? '',
        description: node.getElement('description')?.innerText ?? '',
        link: node.getElement('link')?.innerText ?? '',
      );
    }).toList();
  }
}
