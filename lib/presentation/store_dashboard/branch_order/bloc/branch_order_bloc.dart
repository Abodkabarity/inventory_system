import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/repositories/store_repository.dart';
import 'branch_order_event.dart';
import 'branch_order_state.dart';

class BranchOrderBloc extends Bloc<BranchOrderEvent, BranchOrderState> {
  final StoreRepository repo;

  BranchOrderBloc(this.repo) : super(BranchOrderState.initial()) {
    on<LoadBranchOrderBranches>(_onLoadBranches);
    on<BranchOrderBranchChanged>(_onBranchChanged);
    on<BranchOrderDateChanged>(_onDateChanged);
    on<BranchOrderSearchChanged>(_onSearchChanged);
    on<LoadBranchOrderRows>(_onLoadRows);
  }

  Future<void> _onLoadBranches(
    LoadBranchOrderBranches event,
    Emitter<BranchOrderState> emit,
  ) async {
    emit(state.copyWith(loadingBranches: true, error: ''));

    try {
      final branches = await repo.fetchActiveBranchNames();
      branches.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      emit(
        state.copyWith(
          loadingBranches: false,
          branches: branches,
          clearSelectedBranch: true,
        ),
      );
    } catch (e) {
      emit(state.copyWith(loadingBranches: false, error: e.toString()));
    }
  }

  void _onBranchChanged(
    BranchOrderBranchChanged event,
    Emitter<BranchOrderState> emit,
  ) {
    emit(
      state.copyWith(selectedBranch: event.branch, rows: const [], error: ''),
    );
    add(LoadBranchOrderRows());
  }

  void _onDateChanged(
    BranchOrderDateChanged event,
    Emitter<BranchOrderState> emit,
  ) {
    emit(
      state.copyWith(
        selectedDate: DateTime(
          event.date.year,
          event.date.month,
          event.date.day,
        ),
        rows: const [],
        error: '',
      ),
    );
    add(LoadBranchOrderRows());
  }

  void _onSearchChanged(
    BranchOrderSearchChanged event,
    Emitter<BranchOrderState> emit,
  ) {
    emit(state.copyWith(query: event.query, error: ''));
    add(LoadBranchOrderRows());
  }

  Future<void> _onLoadRows(
    LoadBranchOrderRows event,
    Emitter<BranchOrderState> emit,
  ) async {
    final branch = state.selectedBranch;
    if (branch == null || branch.trim().isEmpty) {
      emit(state.copyWith(rows: const [], loadingRows: false));
      return;
    }

    emit(state.copyWith(loadingRows: true, error: ''));

    try {
      final rows = await repo.fetchBranchOrderMovements(
        branch: branch,
        date: state.selectedDate,
        query: state.query,
      );

      emit(state.copyWith(loadingRows: false, rows: rows));
    } catch (e) {
      emit(
        state.copyWith(loadingRows: false, rows: const [], error: e.toString()),
      );
    }
  }
}
