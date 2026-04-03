import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/news_article.dart';
import '../repository/news_repository.dart';

// ─── States ───────────────────────────────────────────────────────────────────

abstract class NewsState {}

class NewsInitial extends NewsState {}

class NewsLoading extends NewsState {}

class NewsLoaded extends NewsState {
  final List<NewsArticle> articles;
  NewsLoaded(this.articles);
}

class NewsError extends NewsState {
  final String message;
  NewsError(this.message);
}

// ─── Cubit ────────────────────────────────────────────────────────────────────

class NewsCubit extends Cubit<NewsState> {
  final NewsRepository _repository;

  NewsCubit(this._repository) : super(NewsInitial());

  Future<void> fetchNews({bool forceRefresh = false}) async {
    emit(NewsLoading());
    try {
      final articles =
          await _repository.fetchArticles(forceRefresh: forceRefresh);
      emit(NewsLoaded(articles));
    } on NewsException catch (e) {
      emit(NewsError(e.message));
    } catch (_) {
      emit(NewsError('Could not load news. Check your connection.'));
    }
  }
}
