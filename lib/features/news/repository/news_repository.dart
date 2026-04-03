import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

import '../models/news_article.dart';

class NewsException implements Exception {
  final String message;
  const NewsException(this.message);

  @override
  String toString() => message;
}

class NewsRepository {
  // ─── Configuration ────────────────────────────────────────────────────────
  // To adapt for another station, update these constants only.
  static const String _homepageUrl = 'https://wbai.org/';
  static const String _archiveUrl = 'https://wbai.org/moreheadlines.php';
  static const String _baseUrl = 'https://wbai.org';
  static const int _archiveLimit = 20; // extra articles beyond the homepage 6

  static const Duration _cacheDuration = Duration(minutes: 30);

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
  };

  // ─── In-memory cache ─────────────────────────────────────────────────────
  List<NewsArticle>? _cache;
  DateTime? _cacheTime;

  Future<List<NewsArticle>> fetchArticles({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheDuration) {
        return _cache!;
      }
    }

    // Fetch both pages in parallel
    final results = await Future.wait([
      _fetchHomepage(),
      _fetchArchive(),
    ]);

    final homepage = results[0];
    final archive = results[1];

    if (homepage.isEmpty && archive.isEmpty) {
      throw const NewsException(
          'No articles found. The site layout may have changed.');
    }

    // Homepage articles have richer data (images, categories). Archive adds
    // additional articles not already represented on the homepage.
    final seenIds = <String>{};
    final combined = <NewsArticle>[];

    for (final a in homepage) {
      final id = _articleId(a.articleUrl);
      if (seenIds.add(id)) combined.add(a);
    }

    var extras = 0;
    for (final a in archive) {
      if (extras >= _archiveLimit) break;
      final id = _articleId(a.articleUrl);
      if (seenIds.add(id)) {
        combined.add(a);
        extras++;
      }
    }

    _cache = combined;
    _cacheTime = DateTime.now();
    return combined;
  }

  // ─── Homepage scrape (rich: images + categories) ─────────────────────────

  Future<List<NewsArticle>> _fetchHomepage() async {
    try {
      final response = await http
          .get(Uri.parse(_homepageUrl), headers: _headers)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return [];

      final imageRegex = RegExp(r'''url\(['"]?(.*?)['"]?\)''');
      final doc = html_parser.parse(response.body);
      final articles = <NewsArticle>[];

      for (final el in doc.querySelectorAll('.news-tile')) {
        final title =
            el.querySelector('.news-tile__title')?.text.trim() ?? '';
        if (title.isEmpty) continue;

        final href = el.attributes['href'] ?? '';
        final articleUrl =
            href.startsWith('http') ? href : '$_baseUrl/$href';

        final styleAttr = el.attributes['style'] ?? '';
        final imageMatch = imageRegex.firstMatch(styleAttr);
        String? imageUrl;
        if (imageMatch != null) {
          final path = Uri.decodeFull(imageMatch.group(1)!);
          imageUrl = path.startsWith('http') ? path : '$_baseUrl$path';
        }

        articles.add(NewsArticle(
          title: title,
          date: el.querySelector('.news-tile__date')?.text.trim() ?? '',
          author: el
                  .querySelector('.news-tile__author')
                  ?.text
                  .trim()
                  .replaceFirst(
                      RegExp(r'^by\s+', caseSensitive: false), '') ??
              '',
          category:
              el.querySelector('.news-tile__category')?.text.trim() ?? '',
          imageUrl: imageUrl,
          articleUrl: articleUrl,
        ));
      }

      return articles;
    } catch (_) {
      return [];
    }
  }

  // ─── Archive scrape (title + date only, no images) ───────────────────────

  Future<List<NewsArticle>> _fetchArchive() async {
    try {
      final response = await http
          .get(Uri.parse(_archiveUrl), headers: _headers)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return [];

      final dateRegex = RegExp(r'\((\d{2}/\d{2}/\d{4})\)');
      final doc = html_parser.parse(response.body);
      final articles = <NewsArticle>[];

      for (final el in doc.querySelectorAll('span.headline')) {
        final anchor = el.querySelector('a');
        if (anchor == null) continue;

        final title = anchor.text.trim();
        if (title.isEmpty) continue;

        final href = anchor.attributes['href'] ?? '';
        final articleUrl =
            href.startsWith('http') ? href : '$_baseUrl/$href';

        // Date sits as plain text immediately after the </span> in the parent <p>
        final parentText = el.parent?.text ?? '';
        final dateMatch = dateRegex.firstMatch(parentText);
        final date = dateMatch != null
            ? _formatArchiveDate(dateMatch.group(1)!)
            : '';

        articles.add(NewsArticle(
          title: title,
          date: date,
          author: '',
          category: '',
          imageUrl: null,
          articleUrl: articleUrl,
        ));
      }

      return articles;
    } catch (_) {
      return [];
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  /// Extracts the numeric article ID from the URL for deduplication.
  String _articleId(String url) {
    final match = RegExp(r'article=(\d+)').firstMatch(url);
    return match?.group(1) ?? url;
  }

  /// Converts "03/31/2026" → "March 31, 2026"
  String _formatArchiveDate(String raw) {
    final parts = raw.split('/');
    if (parts.length != 3) return raw;
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final month = int.tryParse(parts[0]) ?? 0;
    final day = int.tryParse(parts[1]) ?? 0;
    final year = parts[2];
    if (month < 1 || month > 12) return raw;
    return '${months[month]} $day, $year';
  }

  // ─── Article content fetcher ─────────────────────────────────────────────
  // Fetches an article page, extracts the body content, and returns a
  // self-contained mobile-friendly HTML string for rendering via loadData().
  // Pass the NewsArticle so we can build a properly styled header.

  Future<String> fetchArticleHtml(NewsArticle article) async {
    final response = await http
        .get(Uri.parse(article.articleUrl), headers: _headers)
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () =>
              throw const NewsException('Article load timed out.'),
        );

    if (response.statusCode != 200) {
      throw NewsException(
          'Could not load article (HTTP ${response.statusCode}).');
    }

    final doc = html_parser.parse(response.body);
    final content = doc.querySelector('#leftcontentcontainer');

    if (content == null) {
      throw const NewsException('Article content could not be found.');
    }

    // Remove elements that are now in our styled header
    content.querySelector('span.pagetitle')?.remove();
    content.querySelector('hr')?.remove();

    // Build styled header from NewsArticle metadata we already have
    final categoryHtml = article.category.isNotEmpty
        ? '<span class="article-category">${article.category}</span>'
        : '';
    final dateHtml = article.date.isNotEmpty
        ? '<p class="article-date">${article.date}</p>'
        : '';
    final authorHtml = article.author.isNotEmpty
        ? '<p class="article-author">by ${article.author}</p>'
        : '';

    return '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    * { box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      font-size: 17px;
      line-height: 1.75;
      color: #1a1a1a;
      padding: 20px 16px 60px;
      margin: 0;
      background: #fff;
    }
    .article-header { margin-bottom: 20px; }
    h1.article-title {
      font-size: 24px;
      font-weight: 800;
      line-height: 1.3;
      color: #111;
      margin: 0 0 10px;
    }
    .article-date {
      font-size: 13px;
      color: #999;
      margin: 0 0 4px;
      font-weight: 400;
    }
    .article-author {
      font-size: 14px;
      color: #555;
      font-weight: 500;
      margin: 0 0 10px;
    }
    .article-category {
      display: inline-block;
      background: #1BB4D8;
      color: white;
      font-size: 11px;
      font-weight: 600;
      padding: 3px 10px;
      border-radius: 20px;
      letter-spacing: 0.3px;
    }
    .article-divider { border: none; border-top: 1px solid #eee; margin: 16px 0 20px; }
    div { width: 100% !important; max-width: 100% !important; padding: 0 !important; }
    p { margin: 0 0 16px; }
    img { max-width: 100%; height: auto; display: block; margin: 16px auto; border-radius: 6px; }
    a { color: #1BB4D8; text-decoration: none; }
    a:hover { text-decoration: underline; }
    em { font-style: italic; }
    strong { font-weight: 600; }
  </style>
</head>
<body>
  <div class="article-header">
    <h1 class="article-title">${article.title}</h1>
    $dateHtml
    $authorHtml
    $categoryHtml
  </div>
  <hr class="article-divider">
  ${content.innerHtml}
</body>
</html>''';
  }

  // ─── Lazy cover image fetcher for archive articles ────────────────────────
  // Fetches the first inline image from an article page. Results are cached
  // so repeated calls (e.g. from card rebuild) are instant.

  final Map<String, String?> _imageCache = {};

  Future<String?> fetchArticleCoverImage(String articleUrl) async {
    if (_imageCache.containsKey(articleUrl)) {
      return _imageCache[articleUrl];
    }
    try {
      final response = await http
          .get(Uri.parse(articleUrl), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        _imageCache[articleUrl] = null;
        return null;
      }
      final doc = html_parser.parse(response.body);
      final img = doc.querySelector('#leftcontentcontainer img');
      final src = img?.attributes['src'] ?? '';
      if (src.isEmpty) {
        _imageCache[articleUrl] = null;
        return null;
      }
      final imageUrl = src.startsWith('http') ? src : '$_baseUrl/$src';
      _imageCache[articleUrl] = imageUrl;
      return imageUrl;
    } catch (_) {
      _imageCache[articleUrl] = null;
      return null;
    }
  }

  void clearCache() {
    _cache = null;
    _cacheTime = null;
  }
}
