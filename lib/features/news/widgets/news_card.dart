import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/di/service_locator.dart';
import '../models/news_article.dart';
import '../pages/article_webview_page.dart';
import '../repository/news_repository.dart';

class NewsCard extends StatelessWidget {
  final NewsArticle article;

  const NewsCard({required this.article, super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArticleWebViewPage(article: article),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Cover image (eager if available, lazy-fetched if not) ──────
            _buildBackground(),

            // ── Bottom gradient overlay ───────────────────────────────────
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.25, 1.0],
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
            ),

            // ── Text block bottom-left ────────────────────────────────────
            Positioned(
              left: 12,
              right: article.category.isNotEmpty ? 70 : 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (article.date.isNotEmpty)
                    Text(
                      article.date,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    article.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      height: 1.25,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (article.author.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'by ${article.author}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // ── Category chip top-right ───────────────────────────────────
            if (article.category.isNotEmpty)
              Positioned(
                top: 10,
                right: 10,
                child: _CategoryChip(label: article.category),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    // Homepage articles: image URL comes in the feed directly
    if (article.imageUrl != null) {
      return _networkImage(article.imageUrl!);
    }

    // Archive articles: lazily fetch the first inline image from the article page.
    // Results are cached in the repository so repeated builds are instant.
    return FutureBuilder<String?>(
      future:
          getIt<NewsRepository>().fetchArticleCoverImage(article.articleUrl),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data != null) {
          return _networkImage(snapshot.data!);
        }
        return const _WBAIPlaceholder();
      },
    );
  }

  Widget _networkImage(String url) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => const _WBAIPlaceholder(),
      errorWidget: (_, __, ___) => const _WBAIPlaceholder(),
    );
  }
}

// ─── Branded placeholder ─────────────────────────────────────────────────────

class _WBAIPlaceholder extends StatelessWidget {
  const _WBAIPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B2A36), Color(0xFF0E4D6B)],
        ),
      ),
      child: const Center(
        child: Opacity(
          opacity: 0.15,
          child: Text(
            'WBAI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Category chip ────────────────────────────────────────────────────────────

class _CategoryChip extends StatelessWidget {
  final String label;
  const _CategoryChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1BB4D8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
