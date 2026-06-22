import 'package:flutter_test/flutter_test.dart';
import 'package:wbai_radio/core/utils/m3u_parser.dart';

void main() {
  group('M3UParser.parseStreamUrl', () {
    test('extracts the first http(s) URL from a playlist', () {
      const m3u = '''
#EXTM3U
#EXTINF:-1,WBAI 99.5 FM
https://streams.pacifica.org:9000/wbai_128
''';
      expect(
        M3UParser.parseStreamUrl(m3u),
        'https://streams.pacifica.org:9000/wbai_128',
      );
    });

    test('handles a bare URL with no directives', () {
      expect(
        M3UParser.parseStreamUrl('http://example.com/mount'),
        'http://example.com/mount',
      );
    });

    test('trims surrounding whitespace', () {
      expect(
        M3UParser.parseStreamUrl('   https://example.com/m  \n'),
        'https://example.com/m',
      );
    });

    test('returns null when there is no stream URL', () {
      expect(M3UParser.parseStreamUrl('#EXTM3U\n#EXTINF:-1,Nothing'), isNull);
    });

    test('returns null for empty content', () {
      expect(M3UParser.parseStreamUrl(''), isNull);
    });
  });
}
