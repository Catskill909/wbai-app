/// Expert M3U playlist parser - Industry standard approach
class M3UParser {
  /// Extracts the direct stream URL from M3U playlist content
  static String? parseStreamUrl(String m3uContent) {
    final lines = m3uContent.split('\n');
    
    for (final line in lines) {
      final trimmed = line.trim();
      // Look for HTTP/HTTPS URLs (the actual stream)
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        return trimmed;
      }
    }
    
    return null; // No stream URL found
  }
}
