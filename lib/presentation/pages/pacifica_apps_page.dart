import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:convert';
import '../bloc/pacifica_bloc.dart';
import '../../data/repositories/pacifica_repository.dart';
import '../../domain/models/pacifica_item.dart';
import '../theme/font_constants.dart';
import '../widgets/affiliate_buttons_section.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class PacificaAppsPage extends StatelessWidget {
  const PacificaAppsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => PacificaBloc(
        repository: PacificaRepository(),
      )..add(FetchPacificaItems()),
      child: const _PacificaAppsView(),
    );
  }
}

class _PacificaAppsView extends StatelessWidget {
  const _PacificaAppsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF18191A),
      appBar: AppBar(
        backgroundColor: Color(0xFF18191A),
        title: Text(
          'Pacifica Foundation',
          style: AppTextStyles.drawerTitle,
        ),
      ),
      body: BlocBuilder<PacificaBloc, PacificaState>(
        builder: (context, state) {
          if (state.isLoading && state.items.isEmpty) {
            return _buildLoadingView();
          } else if (state.error != null && state.items.isEmpty) {
            return _buildErrorView(context, state.error!);
          } else {
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    "Pacifica Foundation's Sister Stations",
                    style: AppTextStyles.showTitle.copyWith(
                      fontSize: 20,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _buildGridView(context, state.items),
                const AffiliateButtonsSection(),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildLoadingView() {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
      ),
    );
  }

  Widget _buildErrorView(BuildContext context, String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: Colors.red[400], size: 60),
          const SizedBox(height: 16),
          Text(
            'Failed to load content',
            style: AppTextStyles.sectionTitle.copyWith(
              color: Colors.white,
              fontFamily: 'Oswald',
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              error,
              style: AppTextStyles.bodyMedium.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              context.read<PacificaBloc>().add(FetchPacificaItems());
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView(BuildContext context, List<PacificaItem> items) {
    // Determine column count based on screen width
    final width = MediaQuery.of(context).size.width;
    final isTablet = width > 600;
    final crossAxisCount = isTablet ? 4 : 2;
    
    return RefreshIndicator(
      onRefresh: () async {
        context.read<PacificaBloc>().add(RefreshPacificaItems());
      },
      color: Colors.white,
      backgroundColor: Colors.black87,
      child: GridView.builder(
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 1.0,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          return _buildGridItem(context, items[index]);
        },
      ),
    );
  }

  Widget _buildGridItem(BuildContext context, PacificaItem item) {
    // Helper method to detect small phones for this page only
    bool isSmallDevice = MediaQuery.of(context).size.shortestSide < 380;
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PacificaItemDetail(item: item),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          // Remove border completely for small devices to eliminate stroke
          border: isSmallDevice ? Border.all(
            color: Colors.transparent,
            width: 0,
          ) : Border.all(
            color: Colors.white.withValues(red: 255, green: 255, blue: 255, alpha: 40),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(red: 0, green: 0, blue: 0, alpha: 76),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isSmallDevice ? 12 : 10), // Adjust for border
          child: item.imageUrl != null
              ? Image.network(
                  item.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[800],
                      child: const Icon(
                        Icons.broken_image,
                        color: Colors.white54,
                        size: 50,
                      ),
                    );
                  },
                )
              : Container(
                  color: Colors.grey[800],
                  child: const Icon(
                    Icons.image,
                    color: Colors.white54,
                    size: 50,
                  ),
                ),
        ),
      ),
    );
  }
  

}

class PacificaItemDetail extends StatelessWidget {
  final PacificaItem item;

  const PacificaItemDetail({super.key, required this.item});
  
  // Helper method to remove HTML tags
  String _removeHtmlTags(String htmlString) {
    return htmlString.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF18191A),
      appBar: AppBar(
        backgroundColor: Color(0xFF18191A),
        title: Text(
          'Pacifica Foundation',
          style: AppTextStyles.drawerTitle,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri.uri(Uri.dataFromString(
          _wrapHtmlContent(item),
          mimeType: 'text/html',
          encoding: Encoding.getByName('utf-8')!,
        ))),
        initialSettings: InAppWebViewSettings(
          useShouldOverrideUrlLoading: true,
          mediaPlaybackRequiresUserGesture: false,
          transparentBackground: true,
          useHybridComposition: true,
          allowsInlineMediaPlayback: true,
        ),
        shouldOverrideUrlLoading: (controller, navigationAction) async {
          final uri = navigationAction.request.url;
          if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
            await launchUrl(Uri.parse(uri.toString()));
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
        },
      ),
    );
  }

  String _wrapHtmlContent(PacificaItem item) {
    return '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Oswald:wght@400;500;600&display=swap">
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            background-color: #121212;
            color: #ffffff;
            padding: 16px;
            max-width: 100%;
            word-wrap: break-word;
          }
          h1, h2, h3, h4, h5, h6 {
            font-family: 'Oswald', sans-serif;
            color: #ffffff;
          }
          h1 {
            font-size: 28px;
            margin-bottom: 16px;
            font-weight: 500;
          }
          img {
            max-width: 100%;
            height: auto;
            border-radius: 8px;
          }
          a {
            color: #4fc3f7;
            text-decoration: none;
          }
          p {
            line-height: 1.6;
            color: #e0e0e0;
          }
        </style>
      </head>
      <body>
        <h1>${_removeHtmlTags(item.title)}</h1>
        ${item.imageUrl != null ? '<img src="${item.imageUrl}" alt="${_removeHtmlTags(item.title)}">' : ''}
        ${item.content}
      </body>
      </html>
    ''';
  }
}  
