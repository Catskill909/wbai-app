import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

class DonateWebViewSheet extends StatefulWidget {
  final String initialUrl;

  const DonateWebViewSheet({super.key, required this.initialUrl});

  @override
  State<DonateWebViewSheet> createState() => _DonateWebViewSheetState();
}

class _DonateWebViewSheetState extends State<DonateWebViewSheet> {
  double _progress = 0.0;
  bool _announcedLoaded = false;

  InAppWebViewSettings get _settings => InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        useHybridComposition: true,
        verticalScrollBarEnabled: true,
        disableVerticalScroll: false,
        disableHorizontalScroll: true,
        transparentBackground: true,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: theme.colorScheme.surface,
          elevation: 2,
          title: const Text('Support WBAI'),
          centerTitle: true,
          actions: [
            Semantics(
              label: 'Close donate',
              button: true,
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
                initialSettings: _settings,
                onProgressChanged: (controller, progress) {
                  setState(() => _progress = progress / 100);
                  if (_progress >= 1.0 && !_announcedLoaded) {
                    _announcedLoaded = true;
                    SemanticsService.sendAnnouncement(
                        View.of(context), 'Donate page loaded', Directionality.of(context));
                  }
                },
                shouldOverrideUrlLoading: _handleUrlLoading,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<NavigationActionPolicy> _handleUrlLoading(
    InAppWebViewController controller,
    NavigationAction navigationAction,
  ) async {
    final url = navigationAction.request.url;
    if (url == null) return NavigationActionPolicy.CANCEL;

    final uri = Uri.parse(url.toString());
    final isHttp = uri.scheme == 'http' || uri.scheme == 'https';
    final isSameDomain = uri.host.endsWith('docs.pacifica.org');

    if (!isHttp || !isSameDomain) {
      // Capture text direction before awaiting to avoid using context across async gaps
      final textDirection = Directionality.of(context);
      final supported = await canLaunchUrl(uri);
      if (!mounted) return NavigationActionPolicy.CANCEL;
      if (supported) {
        // Announce opening external browser for accessibility
        SemanticsService.sendAnnouncement(View.of(context), 'Opening external browser', textDirection);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return NavigationActionPolicy.CANCEL;
    }

    return NavigationActionPolicy.ALLOW;
  }
}
