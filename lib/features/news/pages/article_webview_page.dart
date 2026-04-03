import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/di/service_locator.dart';
import '../models/news_article.dart';
import '../repository/news_repository.dart';

class ArticleWebViewPage extends StatefulWidget {
  final NewsArticle article;

  const ArticleWebViewPage({required this.article, super.key});

  @override
  State<ArticleWebViewPage> createState() => _ArticleWebViewPageState();
}

class _ArticleWebViewPageState extends State<ArticleWebViewPage> {
  InAppWebViewController? _controller;
  String? _pendingHtml;
  bool _fetchingContent = true;
  String? _fetchError;

  static final InAppWebViewSettings _settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    supportZoom: false,
    useHybridComposition: true,
    allowsInlineMediaPlayback: true,
    useShouldOverrideUrlLoading: true,
  );

  @override
  void initState() {
    super.initState();
    _fetchArticleContent();
  }

  Future<void> _fetchArticleContent() async {
    try {
      final html =
          await getIt<NewsRepository>().fetchArticleHtml(widget.article);
      if (!mounted) return;
      _pendingHtml = html;
      _tryLoad();
      setState(() => _fetchingContent = false);
    } on NewsException catch (e) {
      if (!mounted) return;
      setState(() {
        _fetchError = e.message;
        _fetchingContent = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fetchError = 'Could not load article. Check your connection.';
        _fetchingContent = false;
      });
    }
  }

  void _tryLoad() {
    if (_controller != null && _pendingHtml != null) {
      _controller!.loadData(
        data: _pendingHtml!,
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: WebUri('https://wbai.org/'),
      );
      _pendingHtml = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        title: const Text(
          'WBAI News',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri('about:blank')),
            initialSettings: _settings,
            onWebViewCreated: (controller) {
              _controller = controller;
              _tryLoad();
            },
            shouldOverrideUrlLoading: (controller, action) async {
              final url = action.request.url;
              if (url == null) return NavigationActionPolicy.CANCEL;
              // Allow programmatic loads (about:blank init, loadData base URL, etc.)
              if (action.navigationType != NavigationType.LINK_ACTIVATED) {
                return NavigationActionPolicy.ALLOW;
              }
              // User-tapped links open in the external browser
              final uri = Uri.parse(url.toString());
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
              return NavigationActionPolicy.CANCEL;
            },
          ),

          // Spinner while content is being fetched
          if (_fetchingContent)
            const ColoredBox(
              color: Colors.white,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(Color(0xFF1BB4D8)),
                ),
              ),
            ),

          // Error state
          if (_fetchError != null)
            ColoredBox(
              color: Colors.white,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded,
                          size: 48, color: Colors.black26),
                      const SizedBox(height: 16),
                      Text(
                        _fetchError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 15, color: Colors.black54),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () {
                          setState(() {
                            _fetchError = null;
                            _fetchingContent = true;
                          });
                          _fetchArticleContent();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try Again'),
                        style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1BB4D8)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
