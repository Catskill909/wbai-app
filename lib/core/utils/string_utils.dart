import 'package:html_unescape/html_unescape.dart';

class StringUtils {
  static final HtmlUnescape _unescape = HtmlUnescape();

  /// Decodes all HTML entities in a string to their corresponding characters:
  /// named ("&amp;", "&reg;"), decimal ("&#039;"), and hex ("&#x2019;").
  /// Runs twice to also handle double-encoded feed data ("&amp;reg;").
  static String decodeHtmlEntities(String input) {
    final once = _unescape.convert(input);
    return once.contains('&') ? _unescape.convert(once) : once;
  }
}
