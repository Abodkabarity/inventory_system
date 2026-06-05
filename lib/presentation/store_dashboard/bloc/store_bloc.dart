import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/utils/operational_date_helper.dart';
import '../../../core/utils/print_additional_service.dart';
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
    on<ConfirmAdditionalItem>(_onConfirmItem);
    on<PrintBranchAdditional>(_onPrintBranch);
    on<OpenProcessingDialog>(_onOpenDialogWithLoading);
    on<PrintAllAdditional>(_onPrintAllWithLoading);
    on<RefreshProcessingList>(_onRefreshProcessingList);
    on<SearchProcessingItems>((event, emit) async {
      final res = await repo.fetchProcessingRequests();

      final query = event.query.toLowerCase();

      final filtered = query.isEmpty
          ? res
          : res.where((item) {
              final name = (item['item_name'] ?? '').toLowerCase();
              final code = (item['item_code'] ?? '').toLowerCase();
              return name.contains(query) || code.contains(query);
            }).toList();

      emit(state.copyWith(processingList: res, filteredList: filtered));
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
      final branchRows = await repo.fetchAllBranches();

      final branches = <String>[];

      final startHours = <String, int>{};
      final endHours = <String, int>{};

      for (final row in branchRows) {
        final branch = row['branch_name'].toString();

        branches.add(branch);

        startHours[branch] =
            row['submit_start_hour'] ?? 0;

        endHours[branch] =
            row['submit_end_hour'] ?? 24;
      }

      final submittedRows =
      await repo.fetchSubmittedBranches(runDate);

      final additional = await repo.fetchAdditionalRequests();

      final submitted = <String>[];
      final printed = <String>[];
      final submittedMap = <String, DateTime>{};

      for (final row in submittedRows) {
        final branch = row['branch_name'].toString();

        submitted.add(branch);

        if (row['printed'] == true) {
          printed.add(branch);
        }

        final submittedAt = DateTime.tryParse(
          row['submitted_at']?.toString() ?? '',
        );

        if (submittedAt != null) {
          submittedMap[branch] = submittedAt;
        }
      }

      final pending = additional
          .where((e) => e.status == 'sent_to_store')
          .length;

      final done = additional.where((e) => e.status == 'done').length;
      branches.sort((a, b) {
        final aSubmitted = submittedMap.containsKey(a);
        final bSubmitted = submittedMap.containsKey(b);

        final aLate =
            OperationalDateHelper.isMissingWindowForBranch(
              startHour: startHours[a] ?? 21,
              endHour: endHours[a] ?? 9,
            ) &&
                !aSubmitted;

        final bLate =
            OperationalDateHelper.isMissingWindowForBranch(
              startHour: startHours[b] ?? 21,
              endHour: endHours[b] ?? 9,
            ) &&
                !bSubmitted;

        if (aLate && !bLate) return 1;
        if (!aLate && bLate) return -1;

        if (aSubmitted && bSubmitted) {
          return submittedMap[a]!.compareTo(
            submittedMap[b]!,
          );
        }

        if (aSubmitted) return -1;
        if (bSubmitted) return 1;

        return a.toLowerCase().compareTo(
          b.toLowerCase(),
        );
      });
      emit(
        state.copyWith(
          branches: branches,
          submittedBranches: submitted,
          additionalRequests: additional,
          submitStartHours: startHours,
          printedBranches: printed,
          submitEndHours: endHours,
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

      await repo.markBranchPrinted(
        runDate: runDate,
        branch: branch,
      );

      add(
        LoadStoreDashboard(
          runDate,
          silent: true,
        ),
      );

      emit(
        state.copyWith(
          items: items,
          isLoading: false,
        ),
      );
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
    emit(state.copyWith(isPrintingMain: true, errorMessage: null));

    try {
      final grouped = await _collect();

      if (grouped.isEmpty) {
        emit(
          state.copyWith(
            isPrintingMain: false,
            errorMessage: "No pending additional requests",
          ),
        );
        return;
      }

      await PrintAdditionalService.printBatch(grouped);
      final res = await repo.fetchProcessingRequests();

      emit(
        state.copyWith(
          isPrintingMain: false,
          processingList: res,
          filteredList: res,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          isPrintingMain: false,
          errorMessage: "Something went wrong",
        ),
      );
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

  Future<void> _onConfirmItem(
    ConfirmAdditionalItem event,
    Emitter<StoreState> emit,
  ) async {
    final item = event.item;
    final id = item['id'].toString();

    final updatedMap = Map<String, bool>.from(state.confirmingItems);
    updatedMap[id] = true;

    emit(state.copyWith(confirmingItems: updatedMap));

    try {
      final qty = item['qty'];

      await repo.approveRequest(id: item['id'], qty: qty);

      final updatedList = state.processingList
          .where((e) => e['id'].toString() != id)
          .toList();

      emit(
        state.copyWith(processingList: updatedList, filteredList: updatedList),
      );
    } catch (e) {
      print("Confirm Error: $e");
    } finally {
      updatedMap[id] = false;
      emit(state.copyWith(confirmingItems: updatedMap));
    }
  }

  Future<void> _onPrintBranch(
    PrintBranchAdditional event,
    Emitter<StoreState> emit,
  ) async {
    emit(state.copyWith(isPrinting: true));

    try {
      await PrintAdditionalService.printBatch({event.branch: event.items});
    } catch (e) {
      print("Print Error: $e");
    }

    emit(state.copyWith(isPrinting: false));
  }

  Future<void> _onOpenDialogWithLoading(
    OpenProcessingDialog event,
    Emitter<StoreState> emit,
  ) async {
    emit(state.copyWith(isOpeningDialog: true));

    try {
      final res = await repo.fetchProcessingRequests();

      final Map<String, List<Map<String, dynamic>>> grouped = {};

      for (final item in res) {
        final branch = item['branch_name'] ?? '';
        grouped.putIfAbsent(branch, () => []);
        grouped[branch]!.add(item);
      }

      emit(
        state.copyWith(
          processingList: res,
          filteredList: res,
          processingBatch: grouped,
          isOpeningDialog: false,
          dialogOpened: true,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isOpeningDialog: false));
    }
  }

  Future<void> _onPrintAllWithLoading(
    PrintAllAdditional event,
    Emitter<StoreState> emit,
  ) async {
    emit(state.copyWith(isPrintingMain: true));

    try {
      final grouped = await _collect();
      await PrintAdditionalService.printBatch(grouped);
    } catch (e) {
      print("Print Error: $e");
    }

    emit(state.copyWith(isPrintingMain: false));
  }

  Future<void> _onRefreshProcessingList(
    RefreshProcessingList event,
    Emitter<StoreState> emit,
  ) async {
    try {
      final res = await repo.fetchProcessingRequests();

      emit(state.copyWith(processingList: res, filteredList: res));
    } catch (e) {
      print("Refresh Error: $e");
    }
  }
}
