# Pacifica Apps and Services Implementation

## iOS Lockscreen Metadata Issue

### Current Behavior (April 2025)

Based on recent screenshots, the iOS lockscreen metadata display shows persistent issues:

- **Default Text**: The lockscreen consistently shows "Loading stream..." and "Connecting..." text instead of actual show information
- **Artwork**: Only the default WPFW logo appears without proper show artwork
- **Playback State**: No difference in metadata display between playing and paused states
- **Controls**: Media controls (play/pause/skip) are visible and functional

### Root Cause Identified (April 18, 2025)

After multiple implementation attempts and careful analysis of the logs, we've identified the core issue:

```
flutter: INFO: 2025-04-18 13:24:41.830584: WPFWRadio: 🎵 Playback state changed: playing=false, updating lockscreen
flutter: INFO: 2025-04-18 13:24:42.351714: WPFWRadio: 🎵 Playback state changed: playing=false, updating lockscreen
flutter: INFO: 2025-04-18 13:24:42.901761: WPFWRadio: 🎵 Playback state changed: playing=false, updating lockscreen
flutter: INFO: 2025-04-18 13:24:43.530372: WPFWRadio: 🎵 Playback state changed: playing=false, updating lockscreen
```

**Excessive Playback State Updates**: The app is sending playback state updates approximately every 0.5 seconds, even when the actual playback state hasn't changed. This is overwhelming iOS's ability to process metadata updates.

### Solution Strategy

1. **Fix Playback State Spam**: Identify and fix the source of the excessive playback state updates in the audio_service implementation
2. **Implement Strict Throttling**: Add strict throttling to prevent more than one update every 5-10 seconds
3. **Consolidate Update Mechanisms**: Choose either the audio_service approach OR the native implementation, not both

See full technical analysis in `iOS_LOCKSCREEN_METADATA_ISSUE.md`

## Overview
This document outlines the implementation plan for the "Pacifica Apps and Services" feature - a modern, dark-themed UI that showcases Pacifica radio stations, apps, and services in a responsive grid layout.

## UI/UX Requirements
- **Title**: "Pacifica Apps and Services"
- **Theme**: Dark mode with modern styling
- **Grid Layout**:
  - 2 columns on phones
  - 4 columns on tablets/larger screens
- **Image Style**:
  - Square images
  - Title overlays with semi-transparent black background
  - White text using Oswald font (already used in the app)
- **Navigation**: Replace the current settings page when users tap the settings icon

## Data Source
The feature will use the WordPress API from Starkey Digital:
- Endpoint: `https://starkey.digital/wp-json/wp/v2/posts?_embed`
- Required fields:
  - Title: Post title
  - Link: URL to full content
  - Excerpt: Short description
  - Content: Full HTML content
  - Featured Image: Medium size from `_embedded.wp:featuredmedia[0].media_details.sizes.medium.source_url`

## Implementation Components

### 1. Data Models

```dart
class PacificaItem {
  final String title;
  final String link;
  final String excerpt;
  final String content;
  final String? imageUrl;

  PacificaItem({
    required this.title,
    required this.link,
    required this.excerpt,
    required this.content,
    this.imageUrl,
  });

  factory PacificaItem.fromJson(Map<String, dynamic> json) {
    String? imageUrl;
    
    // Parse the featured media from _embedded data
    if (json['_embedded'] != null && 
        json['_embedded']['wp:featuredmedia'] != null && 
        json['_embedded']['wp:featuredmedia'].isNotEmpty) {
      final media = json['_embedded']['wp:featuredmedia'][0];
      imageUrl = media['media_details']?['sizes']?['medium']?['source_url'];
    }

    return PacificaItem(
      title: json['title']['rendered'] ?? '',
      link: json['link'] ?? '',
      excerpt: json['excerpt']['rendered'] ?? '',
      content: json['content']['rendered'] ?? '',
      imageUrl: imageUrl,
    );
  }
}
```

### 2. Repository

```dart
class PacificaRepository {
  final client = http.Client();
  final String apiUrl = 'https://starkey.digital/wp-json/wp/v2/posts?_embed';

  Future<List<PacificaItem>> fetchItems() async {
    try {
      final response = await client.get(Uri.parse(apiUrl));
      
      if (response.statusCode == 200) {
        final List<dynamic> jsonData = jsonDecode(response.body);
        return jsonData.map((item) => PacificaItem.fromJson(item)).toList();
      } else {
        throw Exception('Failed to load items: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching items: $e');
    }
  }
}
```

### 3. Bloc/State Management

```dart
// Events
abstract class PacificaEvent {}
class FetchPacificaItems extends PacificaEvent {}
class RefreshPacificaItems extends PacificaEvent {}

// States
class PacificaState {
  final List<PacificaItem> items;
  final bool isLoading;
  final String? error;

  PacificaState({
    this.items = const [],
    this.isLoading = false,
    this.error,
  });

  PacificaState copyWith({
    List<PacificaItem>? items,
    bool? isLoading,
    String? error,
  }) {
    return PacificaState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// BLoC
class PacificaBloc extends Bloc<PacificaEvent, PacificaState> {
  final PacificaRepository repository;

  PacificaBloc({required this.repository}) : super(PacificaState(isLoading: true)) {
    on<FetchPacificaItems>(_onFetchItems);
    on<RefreshPacificaItems>(_onRefreshItems);
  }

  Future<void> _onFetchItems(FetchPacificaItems event, Emitter<PacificaState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final items = await repository.fetchItems();
      emit(state.copyWith(items: items, isLoading: false));
    } catch (e) {
      emit(state.copyWith(error: e.toString(), isLoading: false));
    }
  }

  Future<void> _onRefreshItems(RefreshPacificaItems event, Emitter<PacificaState> emit) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final items = await repository.fetchItems();
      emit(state.copyWith(items: items, isLoading: false));
    } catch (e) {
      emit(state.copyWith(error: e.toString(), isLoading: false));
    }
  }
}
```

### 4. UI - Pacifica Apps & Services Grid Page

```dart
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          'Pacifica Apps and Services',
          style: AppTextStyles.drawerTitle.copyWith(
            fontFamily: 'Oswald',
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              context.read<PacificaBloc>().add(RefreshPacificaItems());
            },
          ),
        ],
      ),
      body: BlocBuilder<PacificaBloc, PacificaState>(
        builder: (context, state) {
          if (state.isLoading && state.items.isEmpty) {
            return _buildLoadingView();
          } else if (state.error != null && state.items.isEmpty) {
            return _buildErrorView(context, state.error!);
          } else {
            return _buildGridView(context, state.items);
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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image
              item.imageUrl != null
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
              
              // Title overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.8),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Text(
                    _removeHtmlTags(item.title),
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: Colors.white,
                      fontFamily: 'Oswald',
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  String _removeHtmlTags(String htmlString) {
    return htmlString.replaceAll(RegExp(r'<[^>]*>'), '');
  }
}
```

### 5. UI - Item Detail Page with WebView

```dart
class PacificaItemDetail extends StatelessWidget {
  final PacificaItem item;

  const PacificaItemDetail({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          'Pacifica',
          style: AppTextStyles.drawerTitle.copyWith(
            fontFamily: 'Oswald',
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser, color: Colors.white),
            onPressed: () {
              launchUrl(Uri.parse(item.link));
            },
          ),
        ],
      ),
      body: WebView(
        initialUrl: 'about:blank',
        javascriptMode: JavascriptMode.unrestricted,
        backgroundColor: Colors.black,
        onWebViewCreated: (WebViewController webViewController) {
          webViewController.loadHtmlString(_wrapHtmlContent(item));
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
  
  String _removeHtmlTags(String htmlString) {
    return htmlString.replaceAll(RegExp(r'<[^>]*>'), '');
  }
}
```

### 6. Update Navigation

Modify the `_navigateToSettings` method in `HomePage` to navigate to the `PacificaAppsPage`:

```dart
void _navigateToSettings(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => const PacificaAppsPage(),
    ),
  );
}
```

## Dependencies

Add these packages to the `pubspec.yaml` file:

```yaml
dependencies:
  # Existing dependencies...
  http: ^1.1.0
  webview_flutter: ^4.2.2
  url_launcher: ^6.1.12
  flutter_bloc: ^8.1.3
```

## Implementation Steps

1. Add required dependencies to `pubspec.yaml` and run `flutter pub get`
2. Create the model in `/lib/domain/models/pacifica_item.dart`
3. Create the repository in `/lib/data/repositories/pacifica_repository.dart`
4. Create the BLoC in `/lib/presentation/bloc/pacifica_bloc.dart`
5. Create the UI pages:
   - `/lib/presentation/pages/pacifica_apps_page.dart`
   - `/lib/presentation/pages/pacifica_item_detail.dart`
6. Update the HomePage's navigation method
7. Test the implementation with different screen sizes
8. Verify the dark theme and responsive grid works as expected
