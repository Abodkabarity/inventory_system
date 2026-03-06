import 'package:flutter_bloc/flutter_bloc.dart';

enum TrackTab { all, pending, sent, done, rejected }

class TrackingFilterState {
  final TrackTab tab;
  final String query;

  const TrackingFilterState({required this.tab, required this.query});

  factory TrackingFilterState.initial() =>
      const TrackingFilterState(tab: TrackTab.all, query: '');

  TrackingFilterState copyWith({TrackTab? tab, String? query}) {
    return TrackingFilterState(
      tab: tab ?? this.tab,
      query: query ?? this.query,
    );
  }
}

class TrackingFilterCubit extends Cubit<TrackingFilterState> {
  TrackingFilterCubit() : super(TrackingFilterState.initial());

  void setTab(TrackTab tab) => emit(state.copyWith(tab: tab));
  void setQuery(String q) => emit(state.copyWith(query: q.trim()));
  void clearQuery() => emit(state.copyWith(query: ''));
}
