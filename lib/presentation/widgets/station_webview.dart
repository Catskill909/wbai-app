import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/stream_constants.dart';
import '../../core/services/logger_service.dart';

class StationWebView extends StatefulWidget {
  const StationWebView({super.key});

  @override
  State<StationWebView> createState() => _StationWebViewState();
}

class _StationWebViewState extends State<StationWebView> {
  InAppWebViewController? _webViewController;
  double _progress = 0;

  InAppWebViewSettings get _webViewSettings => InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        useHybridComposition: true,
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_progress < 1.0)
          LinearProgressIndicator(
            value: _progress,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(StreamConstants.stationWebsite),
            ),
            initialSettings: _webViewSettings,
            onWebViewCreated: (controller) {
              _webViewController = controller;
              _setupJavaScriptHandlers(controller);
            },
            onLoadStart: (controller, url) {
              setState(() => _progress = 0);
            },
            onProgressChanged: (controller, progress) {
              setState(() => _progress = progress / 100);
            },
            onLoadStop: (controller, url) {
              setState(() => _progress = 1.0);
              _injectMetadataTracking(controller);
            },
            onReceivedError: (controller, request, error) {
              _handleLoadError(error.description);
            },
            shouldOverrideUrlLoading: _handleUrlLoading,
          ),
        ),
      ],
    );
  }

  void _setupJavaScriptHandlers(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'mediaMetadata',
      callback: (args) {
        if (args.isNotEmpty && args.first is Map) {
          LoggerService.debug('Received metadata: ${args.first}');
        }
      },
    );
  }

  Future<void> _injectMetadataTracking(
      InAppWebViewController controller) async {
    await controller.evaluateJavascript(source: '''
      // Metadata tracking script
      const observer = new MutationObserver((mutations) => {
        mutations.forEach((mutation) => {
          if (mutation.target.classList.contains('now-playing')) {
            window.flutter_inappwebview.callHandler('mediaMetadata', {
              title: document.querySelector('.now-playing-title')?.textContent,
              artist: document.querySelector('.now-playing-artist')?.textContent,
              show: document.querySelector('.now-playing-show')?.textContent
            });
          }
        });
      });
      
      observer.observe(document.body, {
        subtree: true,
        childList: true,
        attributes: true,
        attributeFilter: ['class']
      });
    ''');
  }

  Future<NavigationActionPolicy> _handleUrlLoading(
    InAppWebViewController controller,
    NavigationAction navigationAction,
  ) async {
    final uri = navigationAction.request.url;
    if (uri == null) return NavigationActionPolicy.CANCEL;

    // Handle external links
    if (!uri.toString().startsWith(StreamConstants.stationWebsite)) {
      try {
        final uriToLaunch = Uri.parse(uri.toString());
        final canLaunch = await canLaunchUrl(uriToLaunch);
        if (canLaunch) {
          await launchUrl(
            uriToLaunch,
            mode: LaunchMode.externalApplication,
          );
        }
      } catch (e) {
        LoggerService.webViewError('Failed to launch external URL', e);
        _showErrorSnackBar('Cannot open external link: ${uri.host}');
      }
      return NavigationActionPolicy.CANCEL;
    }

    return NavigationActionPolicy.ALLOW;
  }

  void _handleLoadError(String message) {
    LoggerService.webViewError('Page load error: $message');
    _showErrorSnackBar(message);
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Failed to load page: $message'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () {
            _webViewController?.reload();
          },
        ),
      ),
    );
  }
}
