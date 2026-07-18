import 'package:flutter_test/flutter_test.dart';
import 'package:wbai_radio/core/utils/string_utils.dart';

void main() {
  group('StringUtils.decodeHtmlEntities', () {
    const cases = {
      'WBAI&reg; Radio': 'WBAI® Radio',
      'Rock &amp; Roll': 'Rock & Roll',
      'It&#039;s Alive': "It's Alive",
      'caf&eacute; &ndash; live': 'café – live',
      'Tom &amp; Jerry &copy; &trade;': 'Tom & Jerry © ™',
      'hex &#x2019;quote&#x2019;': 'hex ’quote’',
      '&ldquo;Democracy Now!&rdquo;': '“Democracy Now!”',
      'plain text': 'plain text',
      '': '',
    };

    cases.forEach((input, expected) {
      test('decodes "$input"', () {
        expect(StringUtils.decodeHtmlEntities(input), expected);
      });
    });

    test('decodes double-encoded entities', () {
      expect(StringUtils.decodeHtmlEntities('&amp;reg; doubled'), '® doubled');
      expect(StringUtils.decodeHtmlEntities('&amp;amp;'), '&');
    });

    test('leaves bare ampersands alone', () {
      expect(StringUtils.decodeHtmlEntities('R&B and Soul'), 'R&B and Soul');
    });
  });
}
