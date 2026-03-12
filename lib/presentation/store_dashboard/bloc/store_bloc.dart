import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/repositories/store_repository.dart';
import 'store_event.dart';
import 'store_state.dart';

class StoreBloc extends Bloc<StoreEvent, StoreState> {
  final StoreRepository repo;

  String runDate = '';

  StoreBloc(this.repo) : super(StoreState.initial()) {
    on<LoadStoreDashboard>(_onLoad);

    on<SelectBranch>(_onSelectBranch);
    on<LoadAdditionalHistory>(_onLoadHistory);
    on<ApproveAdditionalRequest>(_onApproveAdditional);
  }

  /// ================================
  /// LOAD DASHBOARD
  /// ================================
  Future<void> _onLoad(
    LoadStoreDashboard event,
    Emitter<StoreState> emit,
  ) async {
    runDate = event.runDate;

    /// loading فقط إذا لم يكن silent
    if (!event.silent) {
      emit(state.copyWith(isLoading: true));
    }

    try {
      /// =========================
      /// FETCH DATA
      /// =========================

      final branches = await repo.fetchAllBranches();

      final submitted = await repo.fetchSubmittedBranches(runDate);

      final additional = await repo.fetchAdditionalRequests();

      /// =========================
      /// COUNTS
      /// =========================

      final pending = additional
          .where((e) => e.status == 'sent_to_store')
          .length;

      final done = additional.where((e) => e.status == 'done').length;

      /// =========================
      /// EMIT STATE
      /// =========================

      emit(
        state.copyWith(
          branches: branches,
          submittedBranches: submitted,
          additionalRequests: additional,

          /// KPI
          submittedCount: submitted.length,
          additionalCount: additional.length,
          additionalPendingCount: pending,
          additionalDoneCount: done,

          /// stop loading
          isLoading: false,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false));

      print("StoreBloc Load Error: $e");
    }
  }

  /// ================================
  /// SELECT BRANCH
  /// ================================
  Future<void> _onSelectBranch(
    SelectBranch event,
    Emitter<StoreState> emit,
  ) async {
    final branch = event.branch;

    if (state.selectedBranch == branch) return;

    final bool isSubmitted = state.submittedBranches.contains(branch);

    emit(
      state.copyWith(selectedBranch: branch, items: [], isLoading: isSubmitted),
    );

    if (!isSubmitted) {
      return;
    }

    try {
      final items = await repo.fetchBranchItems(
        runDate: runDate,
        branch: branch,
      );

      emit(state.copyWith(items: items, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false));
      print("SelectBranch Error: $e");
    }
  }

  /// ================================
  /// APPROVE ADDITIONAL REQUEST
  /// ================================
  Future<void> _onApproveAdditional(
    ApproveAdditionalRequest event,
    Emitter<StoreState> emit,
  ) async {
    try {
      await repo.approveRequest(id: event.requestId, qty: event.qty);

      /// reload dashboard بدون loading
      add(LoadStoreDashboard(runDate, silent: true));
    } catch (e) {
      print("ApproveAdditional Error: $e");
    }
  }

  /// ================================
  /// LOAD HISTORY
  /// ================================
  Future<void> _onLoadHistory(
    LoadAdditionalHistory event,
    Emitter<StoreState> emit,
  ) async {
    try {
      final history = await repo.fetchAdditionalHistory(
        from: event.from,
        to: event.to,
      );

      emit(state.copyWith(additionalHistory: history));
    } catch (e) {
      print("History load error: $e");
    }
  }
}
