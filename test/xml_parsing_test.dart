import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';

void main() {
  test('XML parsing test for Pacifica affiliates', () {
    // Test XML parsing with the provided XML structure
    const xmlContent = '''<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
<channel>
<title>Pacifica Network Affiliates</title>
<description>List of Pacifica Network affiliate stations</description>
<item>
<title>KPFK</title>
<link>https://www.kpfk.org/</link>
<description>Los Angeles, CA</description>
</item>
<item>
<title>KPFA</title>
<link>https://kpfa.org/</link>
<description>Berkeley, CA</description>
</item>
<item>
<title>Beware the Radio</title>
<link>https://bewaretheradio.com/</link>
<description>London, Great Britain</description>
</item>
</channel>
</rss>''';

    final document = XmlDocument.parse(xmlContent);
    final items = document.findAllElements('item');
    
    expect(items.length, 3);
    
    final firstItem = items.first;
    expect(firstItem.getElement('title')?.innerText, 'KPFK');
    expect(firstItem.getElement('description')?.innerText, 'Los Angeles, CA');
    expect(firstItem.getElement('link')?.innerText, 'https://www.kpfk.org/');
    
    debugPrint('XML parsing test passed - structure is compatible');
  });
}
