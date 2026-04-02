class StringUtils {
  /// Decodes HTML entities in a string to their corresponding characters.
  /// For example: "&amp;" becomes "&", "&#039;" becomes "'", etc.
  static String decodeHtmlEntities(String input) {
    return input
        // Basic HTML entities
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        // Quote entities
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        // Typographic quotes
        .replaceAll('&rsquo;', "'")
        .replaceAll('&lsquo;', "'")
        .replaceAll('&rdquo;', '"')
        .replaceAll('&ldquo;', '"')
        // Special characters
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&hellip;', '…');
  }
}
