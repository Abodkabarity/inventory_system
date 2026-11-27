import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/operational_date_helper.dart';
import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../core/utils/print_additional_service.dart';
import '../../../core/utils/web_notification.dart';
import '../../../domain/repositories/store_repository.dart';
import '../../../domain/entities/tibah_order.dart';
import '../../../data/datasources/remote/tibah_order_remote_ds.dart';
import 'store_event.dart';
import 'store_state.dart';

class StoreBloc extends Bloc<StoreEvent, StoreState> {
  final StoreRepository repo;
  RealtimeChannel? additionalChannel;

  final AudioPlayer _player = AudioPlayer();
  String runDate = '';
  final TibahOrderRemoteDs? tibah;
  bool _refreshingTibah = false;
  int _branchSelectionVersion = 0;

  StoreBloc(this.repo, {this.tibah}) : super(StoreState.initial()) {
    on<RefreshTibahOrder>(_onRefreshTibah);
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
    on<StartStoreAdditionalRealtime>((event, emit) {
      additionalChannel = Supabase.instance.client
          .channel('store_additional_live')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'additional_requests',
            callback: (payload) async {
              final oldStatus = (payload.oldRecord['status'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();

              final newStatus = (payload.newRecord['status'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();

              if (oldStatus == 'sent_to_store') {
                return;
              }

              if (newStatus != 'sent_to_store') {
                return;
              }

              final branch = (payload.newRecord['branch_name'] ?? '')
                  .toString();

              final item = (payload.newRecord['item_name'] ?? '').toString();

              final qty = (payload.newRecord['request_qty'] ?? 0).toString();

              try {
                await _player.play(AssetSource('sounds/notification.mp3'));
              } catch (e) {
                print(e);
              }

              WebNotification.show(
                title: 'New Store Request',
                body: '$branch\n$item\nQty: $qty',
              );

              add(LoadStoreDashboard(runDate, silent: true));
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'additional_order_inventory',
            callback: (_) => add(LoadStoreDashboard(runDate, silent: true)),
          )
          .subscribe();
    });
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
    WebNotification.init();

    add(StartStoreAdditionalRealtime());
  }
  @override
  Future<void> close() {
    if (additionalChannel != null) {
      Supabase.instance.client.removeChannel(additionalChannel!);
    }

    return super.close();
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
      final branchRows = await repo.fetchTodayBranches();

      final branches = <String>[];

      final startHours = <String, int>{};
      final endHours = <String, int>{};

      for (final row in branchRows) {
        final branch = row['branch_name'].toString();

        if (tibah != null && TibahOrder.isBranch(branch)) continue;

        branches.add(branch);

        startHours[branch] = row['submit_start_hour'] ?? 0;

        endHours[branch] = row['submit_end_hour'] ?? 24;
      }

      final submittedRows = await repo.fetchSubmittedBranches(runDate);

      final additional = await repo.fetchAdditionalRequests();

      final submitted = <String>[];
      final printed = <String>[];
      final submittedMap = <String, DateTime>{};

      for (final row in submittedRows) {
        final branch = row['branch_name'].toString();

        if (tibah != null && TibahOrder.isBranch(branch)) continue;

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
          return submittedMap[a]!.compareTo(submittedMap[b]!);
        }

        if (aSubmitted) return -1;
        if (bSubmitted) return 1;

        return a.toLowerCase().compareTo(b.toLowerCase());
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
      if (tibah != null) add(RefreshTibahOrder());
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
    final selectionVersion = ++_branchSelectionVersion;

    if (tibah != null && TibahOrder.isBranch(branch)) {
      emit(
        state.copyWith(
          selectedBranch: branch,
          items: [],
          isLoading: true,
          clearTibahSelection: true,
          tibahItemsLoaded: false,
        ),
      );
      try {
        final order = await tibah!.current(TibahOrderType.forBranch(branch)!);
        if (selectionVersion != _branchSelectionVersion ||
            state.selectedBranch != branch) {
          return;
        }
        if (order == null || !order.isPending) {
          emit(state.copyWith(isLoading: false));
          add(RefreshTibahOrder());
          return;
        }
        emit(
          state.copyWith(
            tibahOrders: {...state.tibahOrders, order.branch: order},
            selectedTibahOrder: order,
            isLoading: order.isReady,
          ),
        );
        if (!order.isReady) return;
        final items = await tibah!.items(order);
        if (selectionVersion != _branchSelectionVersion ||
            state.selectedBranch != branch ||
            state.selectedTibahOrder?.id != order.id) {
          return;
        }
        emit(
          state.copyWith(
            items: items,
            isLoading: false,
            tibahItemsLoaded: true,
          ),
        );
      } catch (error) {
        if (selectionVersion == _branchSelectionVersion &&
            state.selectedBranch == branch) {
          emit(
            state.copyWith(
              items: [],
              isLoading: false,
              tibahItemsLoaded: false,
              errorMessage: '$error',
            ),
          );
        }
      }
      return;
    }

    if (state.selectedBranch == branch) return;

    final bool isSubmitted = state.submittedBranches.contains(branch);

    emit(
      state.copyWith(
        selectedBranch: branch,
        items: [],
        isLoading: isSubmitted,
        clearTibahSelection: true,
        tibahItemsLoaded: false,
      ),
    );

    if (!isSubmitted) return;

    try {
      final items = await repo.fetchBranchItems(
        runDate: runDate,
        branch: branch,
      );

      if (selectionVersion != _branchSelectionVersion ||
          state.selectedBranch != branch) {
        return;
      }

      await repo.markBranchPrinted(runDate: runDate, branch: branch);

      add(LoadStoreDashboard(runDate, silent: true));

      emit(state.copyWith(items: items, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false));
      print("SelectBranch Error: $e");
    }
  }

  Future<void> _onRefreshTibah(
    RefreshTibahOrder event,
    Emitter<StoreState> emit,
  ) async {
    if (tibah == null || _refreshingTibah) return;
    _refreshingTibah = true;
    try {
      final orders = await tibah!.currentOrders();
      if (orders.any(
        (order) => state.tibahOrders[order.branch]?.id != order.id,
      )) {
        await StoreBranchIdentityRegistry.load(tibah!.client, force: true);
      }
      final branches = state.branches
          .where((b) => !TibahOrder.isBranch(b))
          .toList();
      final submitted = state.submittedBranches
          .where((b) => !TibahOrder.isBranch(b))
          .toList();
      for (final order in orders.where((o) => o.isPending)) {
        branches.add(order.branch);
        submitted.add(order.branch);
      }
      final byBranch = {for (final order in orders) order.branch: order};
      final order = byBranch[state.selectedBranch];
      final selected =
          state.selectedBranch != null &&
          TibahOrder.isBranch(state.selectedBranch!);
      final changed = selected && state.selectedTibahOrder != order;
      emit(
        state.copyWith(
          branches: branches,
          submittedBranches: submitted,
          submittedCount: submitted.length,
          tibahOrders: byBranch,
          selectedTibahOrder: selected && order?.isPending == true
              ? order
              : null,
          clearTibahSelection: selected && order?.isPending != true,
          clearSelectedBranch: selected && order?.isPending != true,
          items: changed ? [] : null,
          tibahItemsLoaded: changed ? false : null,
        ),
      );
      if (changed && order?.isPending == true) add(SelectBranch(order!.branch));
    } catch (error) {
      emit(state.copyWith(errorMessage: 'Could not refresh Tibah: $error'));
    } finally {
      _refreshingTibah = false;
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
      await repo.approveRequest(
        id: event.requestId,
        qty: event.qty,
        sourceTable: event.sourceTable,
      );

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
  bool _matchesAdditionalPrintClassification(
    Map<String, dynamic> item,
    String classification,
  ) {
    final selected = classification.trim().toLowerCase();
    if (selected == 'all') return true;

    final raw = (item['store_item_classifications'] ?? '').toString().trim();
    final normalized = raw.isEmpty ? 'medicine' : raw.toLowerCase();

    if (selected == 'general') {
      return normalized == 'general';
    }

    return normalized != 'general';
  }

  Future<Map<String, List<Map<String, dynamic>>>> _collect({
    String classification = 'all',
  }) async {
    final allRows = await repo.fetchAllSentToStore();
    final res = allRows
        .where(
          (item) => _matchesAdditionalPrintClassification(item, classification),
        )
        .toList();

    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final item in res) {
      final branch = item['branch_name'] ?? '';
      grouped.putIfAbsent(branch, () => []);
      grouped[branch]!.add(item);
    }

    await repo.markAsProcessing(res);

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
      final grouped = await _collect(classification: event.classification);

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
      final additional = await repo.fetchAdditionalRequests();

      emit(
        state.copyWith(
          isPrintingMain: false,
          processingList: res,
          filteredList: res,
          additionalRequests: additional,
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

      await repo.approveRequest(
        id: item['id'].toString(),
        qty: qty,
        sourceTable: (item['_source_table'] ?? 'additional_requests')
            .toString(),
      );

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
      final additional = await repo.fetchAdditionalRequests();
      emit(state.copyWith(additionalRequests: additional));
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
