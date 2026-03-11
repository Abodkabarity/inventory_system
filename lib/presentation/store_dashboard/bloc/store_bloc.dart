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

    emit(state.copyWith(isLoading: true));

    try {
      /// BRANCHES ORDERING TODAY
      final branches = await repo.fetchAllBranches();

      /// SUBMITTED BRANCHES
      final submitted = await repo.fetchSubmittedBranches(runDate);

      /// ADDITIONAL REQUESTS
      final additional = await repo.fetchAdditionalRequests(runDate);

      /// COUNT PENDING ADDITIONAL
      final pending = additional.where((e) => e.done == false).length;

      /// COUNT DONE ADDITIONAL
      final done = additional.where((e) => e.done == true).length;

      emit(
        state.copyWith(
          branches: branches,
          submittedBranches: submitted,
          additionalRequests: additional,

          /// KPI COUNTS
          submittedCount: submitted.length,
          additionalCount: additional.length,
          additionalPendingCount: pending,
          additionalDoneCount: done,

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
    emit(state.copyWith(selectedBranch: event.branch, isLoading: true));

    try {
      final items = await repo.fetchBranchItems(
        runDate: runDate,
        branch: event.branch,
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

      /// RELOAD DASHBOARD
      add(LoadStoreDashboard(runDate));
    } catch (e) {
      print("ApproveAdditional Error: $e");
    }
  }
}
