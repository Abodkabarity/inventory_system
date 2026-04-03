import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/entities/mismatch_item.dart';
import '../../../domain/repositories/inventory_repository.dart';
import 'inventory_event.dart';
import 'inventory_state.dart';

class InventoryBloc extends Bloc<InventoryEvent, InventoryState> {
  final InventoryRepository repo;

  String runDate = '';
  late final RealtimeChannel mismatchChannel;
  InventoryBloc(this.repo) : super(InventoryState.initial()) {
    /// ✅ أول شي عرفي كل events
    on<LoadInventoryDashboard>(_onLoad);
    on<SelectBranch>(_onSelectBranch);
    on<LoadBranchAnalytics>(_onBranchAnalytics);
    on<ApproveInventoryRequest>(_onApproveInventory);
    on<LoadBranchAdditionalStats>(_onBranchAdditionalStats);

    on<ChangeInventoryPage>((event, emit) {
      emit(state.copyWith(currentPage: event.page));
    });

    on<LoadMismatchTracker>(_onLoadMismatchTracker);
    on<LoadMismatch>(_onLoadMismatch);
    on<SearchMismatch>(_onSearchMismatch);
    on<FilterMismatchBranch>(_onFilterMismatchBranch);
    on<UpdateMismatchColumnWidth>(_onUpdateMismatchColumnWidth);

    /// ✅ هذا مهم
    on<StartMismatchRealtime>((event, emit) {
      mismatchChannel = Supabase.instance.client
          .channel('mismatch_live_bloc')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'mismatch_log',
            callback: (payload) {
              add(LoadInventoryDashboard(runDate, silent: true));
            },
          )
          .subscribe();
    });

    add(StartMismatchRealtime());
  }

  /// ================================
  /// LOAD DASHBOARD
  /// ================================
  Future<void> _onLoad(
    LoadInventoryDashboard event,
    Emitter<InventoryState> emit,
  ) async {
    runDate = event.runDate;

    if (!event.silent) {
      emit(state.copyWith(isLoading: true));
    }

    try {
      final branches = await repo.fetchBranchesToday();

      final submitted = await repo.fetchSubmittedBranches(runDate);

      final additional = await repo.fetchAdditionalRequests();

      final mismatchToday = await repo.fetchMismatchToday();
      final mismatchMonth = await repo.fetchMismatchMonth();
      final mismatchTotal = await repo.fetchMismatchTotal();
      final mismatchDiff = await repo.fetchMismatchDiffSum();
      final mismatchData = await repo.fetchMismatch();
      final editsCount = await repo.fetchBranchEditsCount(runDate);

      /// NEW
      final additionalBranchToday = await repo.fetchAdditionalTodayByBranch(
        runDate,
      );

      final pending = additional
          .where((e) => e.status == 'pending_inventory')
          .length;

      final sentToStore = additional
          .where((e) => e.status == 'sent_to_store')
          .length;

      emit(
        state.copyWith(
          branches: branches,
          submittedBranches: submitted,
          additionalRequests: additional,
          editsCount: editsCount,
          additionalTodayBranchCount: additionalBranchToday,
          mismatchTotalCount: mismatchTotal,
          submittedCount: submitted.length,
          additionalCount: additional.length,
          additionalPendingCount: pending,
          additionalSentToStoreCount: sentToStore,
          mismatchTodayCount: mismatchToday,
          mismatchMonthCount: mismatchMonth,
          mismatch: mismatchData,
          mismatchDiffSum: mismatchDiff,
          filteredMismatch: mismatchData,
          isLoading: false,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoading: false));

      print("InventoryBloc Load Error: $e");
    }
  }

  /// ================================
  /// SELECT BRANCH
  /// ================================
  Future<void> _onSelectBranch(
    SelectBranch event,
    Emitter<InventoryState> emit,
  ) async {
    final branch = event.branch;

    if (state.selectedBranch == branch) return;

    final bool isSubmitted = state.submittedBranches.contains(branch);

    emit(
      state.copyWith(selectedBranch: branch, edits: [], isLoading: isSubmitted),
    );

    if (!isSubmitted) {
      return;
    }

    try {
      final edits = await repo.fetchBranchEdits(
        runDate: runDate,
        branch: branch,
      );

      emit(state.copyWith(edits: edits, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false));

      print("SelectBranch Inventory Error: $e");
    }
  }

  /// ================================
  /// APPROVE INVENTORY REQUEST
  /// ================================
  Future<void> _onApproveInventory(
    ApproveInventoryRequest event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      await repo.approveInventory(id: event.requestId, qty: event.qty);

      /// reload dashboard silently
      add(LoadInventoryDashboard(runDate, silent: true));
    } catch (e) {
      print("Inventory Approve Error: $e");
    }
  }

  Future<void> _onBranchAnalytics(
    LoadBranchAnalytics event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      final edits = await repo.fetchBranchEdits(
        runDate: runDate,
        branch: event.branch,
      );

      emit(state.copyWith(selectedBranch: event.branch, edits: edits));
    } catch (e) {
      print("Branch Analytics Error: $e");
    }
  }

  Future<void> _onBranchAdditionalStats(
    LoadBranchAdditionalStats event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      final month = await repo.fetchAdditionalMonthByBranch(event.branch);

      final today = await repo.fetchAdditionalTodayByBranchExact(event.branch);

      final monthMap = Map<String, int>.from(state.additionalMonthBranchCount);
      final todayMap = Map<String, int>.from(
        state.additionalTodayBranchExactCount,
      );

      monthMap[event.branch] = month;
      todayMap[event.branch] = today;

      emit(
        state.copyWith(
          additionalMonthBranchCount: monthMap,
          additionalTodayBranchExactCount: todayMap,
        ),
      );
    } catch (e) {
      print("Branch Additional Stats Error: $e");
    }
  }

  Future<void> _onLoadMismatch(
    LoadMismatch event,
    Emitter<InventoryState> emit,
  ) async {
    final data = await repo.fetchMismatch();

    emit(state.copyWith(mismatch: data, filteredMismatch: data));
  }

  void _onSearchMismatch(SearchMismatch event, Emitter<InventoryState> emit) {
    final filtered = _applyMismatchFilters(
      list: state.mismatch,
      search: event.query,
      branch: state.mismatchBranch,
    );

    emit(
      state.copyWith(mismatchSearch: event.query, filteredMismatch: filtered),
    );
  }

  void _onFilterMismatchBranch(
    FilterMismatchBranch event,
    Emitter<InventoryState> emit,
  ) {
    final filtered = _applyMismatchFilters(
      list: state.mismatch,
      search: state.mismatchSearch,
      branch: event.branch,
    );

    emit(
      state.copyWith(mismatchBranch: event.branch, filteredMismatch: filtered),
    );
  }

  List<MismatchItem> _applyMismatchFilters({
    required List<MismatchItem> list,
    required String search,
    required String branch,
  }) {
    var result = list;

    /// search
    if (search.isNotEmpty) {
      final q = search.toLowerCase();

      result = result.where((e) {
        return e.itemName.toLowerCase().contains(q) ||
            e.itemCode.toLowerCase().contains(q);
      }).toList();
    }

    /// branch
    if (branch != 'ALL') {
      result = result.where((e) => e.branchName == branch).toList();
    }

    return result;
  }

  void _onUpdateMismatchColumnWidth(
    UpdateMismatchColumnWidth event,
    Emitter<InventoryState> emit,
  ) {
    final updated = Map<String, double>.from(state.mismatchColumnWidths);

    updated[event.column] = event.width;

    emit(state.copyWith(mismatchColumnWidths: updated));
  }

  Future<void> _onLoadMismatchTracker(
    LoadMismatchTracker event,
    Emitter<InventoryState> emit,
  ) async {
    try {
      final data = await repo.fetchMismatchTracker(
        from: event.from,
        to: event.to,
        branch: event.branch,
      );

      emit(state.copyWith(mismatchTracker: data));
    } catch (e) {
      print("Mismatch Tracker Error: $e");
    }
  }

  @override
  Future<void> close() {
    Supabase.instance.client.removeChannel(mismatchChannel);
    return super.close();
  }
}
