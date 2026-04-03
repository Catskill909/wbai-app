import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/service_locator.dart';
import '../bloc/news_cubit.dart';
import '../widgets/news_card.dart';

class NewsPage extends StatelessWidget {
  const NewsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: getIt<NewsCubit>(),
      child: const _NewsContent(),
    );
  }
}

class _NewsContent extends StatefulWidget {
  const _NewsContent();

  @override
  State<_NewsContent> createState() => _NewsContentState();
}

class _NewsContentState extends State<_NewsContent> {
  final ScrollController _scrollController = ScrollController();
  int _visibleCount = 6;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    final cubit = context.read<NewsCubit>();
    if (cubit.state is NewsInitial) cubit.fetchNews();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final max = _scrollController.position.maxScrollExtent;
    final pos = _scrollController.position.pixels;
    if (pos >= max - 200) {
      final state = context.read<NewsCubit>().state;
      if (state is NewsLoaded && _visibleCount < state.articles.length) {
        setState(() => _visibleCount += 6);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        // Down chevron in place of the default back arrow — signals "slide down to close"
        leading: IconButton(
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 32,
            color: Colors.black87,
          ),
          tooltip: 'Close',
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'WBAI News',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            color: Colors.black87,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black54),
            tooltip: 'Refresh',
            onPressed: () {
              setState(() => _visibleCount = 6);
              context.read<NewsCubit>().fetchNews(forceRefresh: true);
            },
          ),
        ],
      ),
      body: BlocBuilder<NewsCubit, NewsState>(
        builder: (context, state) {
          if (state is NewsLoading || state is NewsInitial) {
            return const Center(
              child: CircularProgressIndicator(
                valueColor:
                    AlwaysStoppedAnimation<Color>(Color(0xFF1BB4D8)),
              ),
            );
          }

          if (state is NewsError) {
            return _ErrorView(
              message: state.message,
              onRetry: () {
                setState(() => _visibleCount = 6);
                context.read<NewsCubit>().fetchNews(forceRefresh: true);
              },
            );
          }

          if (state is NewsLoaded) {
            final visible = state.articles.take(_visibleCount).toList();
            final hasMore = _visibleCount < state.articles.length;

            return RefreshIndicator(
              color: const Color(0xFF1BB4D8),
              onRefresh: () async {
                setState(() => _visibleCount = 6);
                await context
                    .read<NewsCubit>()
                    .fetchNews(forceRefresh: true);
              },
              child: _NewsGrid(
                articles: visible,
                hasMore: hasMore,
                scrollController: _scrollController,
              ),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ─── Grid ─────────────────────────────────────────────────────────────────────

class _NewsGrid extends StatelessWidget {
  final List articles;
  final bool hasMore;
  final ScrollController scrollController;

  const _NewsGrid({
    required this.articles,
    required this.hasMore,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.shortestSide >= 600;

    return GridView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: articles.length + (hasMore ? 1 : 0),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isTablet ? 2 : 1,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: isTablet ? 1.1 : 1.6,
      ),
      itemBuilder: (context, index) {
        if (index == articles.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(
                valueColor:
                    AlwaysStoppedAnimation<Color>(Color(0xFF1BB4D8)),
                strokeWidth: 2,
              ),
            ),
          );
        }
        return NewsCard(article: articles[index]);
      },
    );
  }
}

// ─── Error view ───────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.black26),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 15, color: Colors.black54)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1BB4D8)),
            ),
          ],
        ),
      ),
    );
  }
}
