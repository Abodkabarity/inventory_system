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

    /// 🔥 NEW EVENTS
    on<CollectAndPrintAdditional>(_onCollectAndPrint);
    on<CollectAndOpenDialogAdditional>(_onCollectAndOpenDialog);

    on<ClearProcessingBatch>(_onClearProcessing);
    on<ClearPrintBatch>(_onClearPrint);
    on<SearchProcessingItems>((event, emit) {
      final query = event.query.toLowerCase();

      if (query.isEmpty) {
        emit(
          state.copyWith(
            filteredProcessing: state.processingBatch,
            searchQuery: '',
          ),
        );
        return;
      }

      final Map<String, List<Map<String, dynamic>>> filtered = {};

      state.processingBatch.forEach((branch, items) {
        final matched = items.where((item) {
          final name = (item['item_name'] ?? '').toString().toLowerCase();
          return name.contains(query);
        }).toList();

        if (matched.isNotEmpty) {
          filtered[branch] = matched;
        }
      });

      emit(
        state.copyWith(filteredProcessing: filtered, searchQuery: event.query),
      );
    });
  }

  /// ================================
  /// LOAD DASHBOARD
  /// ================================
  Future<void> _onLoad(
    LoadStoreDashboard event,
    Emitter<StoreState> emit,
  ) async {
    runDate = event.runDate;

    if (!event.silent) {
      emit(state.copyWith(isLoading: true));
    }

    try {
      final branches = await repo.fetchAllBranches();
      final submitted = await repo.fetchSubmittedBranches(runDate);
      final additional = await repo.fetchAdditionalRequests();

      final pending = additional
          .where((e) => e.status == 'sent_to_store')
          .length;

      final done = additional.where((e) => e.status == 'done').length;

      emit(
        state.copyWith(
          branches: branches,
          submittedBranches: submitted,
          additionalRequests: additional,
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
    final branch = event.branch;

    if (state.selectedBranch == branch) return;

    final bool isSubmitted = state.submittedBranches.contains(branch);

    emit(
      state.copyWith(selectedBranch: branch, items: [], isLoading: isSubmitted),
    );

    if (!isSubmitted) return;

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

  /// ================================
  /// 🔥 COLLECT (CORE LOGIC)
  /// ================================
  Future<Map<String, List<Map<String, dynamic>>>> _collect() async {
    final res = await repo.fetchAllSentToStore();
    print("DATA: $res");
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final item in res) {
      final branch = item['branch_name'] ?? '';
      grouped.putIfAbsent(branch, () => []);
      grouped[branch]!.add(item);
    }

    final ids = res.map((e) => e['id'].toString()).toList();

    await repo.markAsProcessing(ids);

    return grouped;
  }

  /// ================================
  /// 🖨 PRINT
  /// ================================
  Future<void> _onCollectAndPrint(
    CollectAndPrintAdditional event,
    Emitter<StoreState> emit,
  ) async {
    try {
      final grouped = await _collect();

      emit(state.copyWith(printBatch: grouped));
    } catch (e) {
      print("Print Error: $e");
    }
  }

  /// ================================
  /// 📋 OPEN DIALOG
  /// ================================
  Future<void> _onCollectAndOpenDialog(
    CollectAndOpenDialogAdditional event,
    Emitter<StoreState> emit,
  ) async {
    try {
      final res = await repo.fetchProcessingRequests();

      final Map<String, List<Map<String, dynamic>>> grouped = {};

      for (final item in res) {
        final branch = item['branch_name'] ?? '';
        grouped.putIfAbsent(branch, () => []);
        grouped[branch]!.add(item);
      }

      emit(
        state.copyWith(processingBatch: grouped, filteredProcessing: grouped),
      );
    } catch (e) {
      print("Dialog Error: $e");
    }
  }

  /// ================================
  /// CLEAR PROCESSING
  /// ================================
  void _onClearProcessing(
    ClearProcessingBatch event,
    Emitter<StoreState> emit,
  ) {
    emit(state.copyWith(processingBatch: {}));
  }

  /// ================================
  /// CLEAR PRINT
  /// ================================
  void _onClearPrint(ClearPrintBatch event, Emitter<StoreState> emit) {
    emit(state.copyWith(printBatch: {}));
  }
}
