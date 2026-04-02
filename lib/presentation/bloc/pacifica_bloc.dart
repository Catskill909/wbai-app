import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../data/repositories/pacifica_repository.dart';
import '../../domain/models/pacifica_item.dart';

// Events
abstract class PacificaEvent extends Equatable {
  const PacificaEvent();

  @override
  List<Object> get props => [];
}

class FetchPacificaItems extends PacificaEvent {}
class RefreshPacificaItems extends PacificaEvent {}

// States
class PacificaState extends Equatable {
  final List<PacificaItem> items;
  final bool isLoading;
  final String? error;

  const PacificaState({
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

  @override
  List<Object?> get props => [items, isLoading, error];
}

// BLoC
class PacificaBloc extends Bloc<PacificaEvent, PacificaState> {
  final PacificaRepository repository;

  PacificaBloc({required this.repository}) : super(const PacificaState(isLoading: true)) {
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
