// orders_bloc.dart
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:stream_transform/stream_transform.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/utils/excel_exporter.dart';
import '../../../../core/utils/order_row_mapper.dart';
import '../../../../domain/entities/daily_order_row.dart';
import '../../../../domain/repositories/orders_repository.dart';
import '../../../../domain/usecases/fetch_orders_all.dart';
import '../../../../domain/usecases/generate_branch_order.dart';
import 'orders_event.dart';
import 'orders_state.dart';

class OrdersBloc extends Bloc<OrdersEvent, OrdersState> {
  final FetchOrdersAll fetchOrdersAll;
  final GenerateBranchOrder generateBranchOrder;
  final OrdersRepository repo;

  Timer? _progressTimer;

  OrdersBloc({
    required OrdersState initialState,
    required this.fetchOrdersAll,
    required this.generateBranchOrder,
    required this.repo,
  }) : super(initialState) {
    on<OrdersPressedGenerate>(_onPressedGenerate);
    on<OrdersLoadAll>(_onLoadAll);

    on<OrdersSearchChanged>(_onSearchChanged);

    // Columns
    on<OrdersSetColumnVisible>(_onSetColumnVisible);
    on<OrdersReorderColumns>(_onReorderColumns);
    on<OrdersResetColumnsToDefault>(_onResetColumnsToDefault);
    on<OrdersColumnResized>(_onColumnResized);
    on<OrdersLoadMismatch>(_onLoadMismatch);
    on<OrdersAddMismatch>(_onAddMismatch);
    on<OrdersUpdateMismatch>(_onUpdateMismatch);
    on<OrdersDeleteMismatch>(_onDeleteMismatch);
    on<OrdersSearchMismatchItems>(_onSearchMismatch);
    on<OrdersToggleMismatchEdit>(_onToggleMismatchEdit);
    // Filters
    on<OrdersCategoryChanged>(_onCategoryChanged);
    on<OrdersFormularyChanged>(_onFormularyChanged);
    on<OrdersNonWithSales45Toggled>(_onNonWithSales45Toggled);

    // NEW Filters
    on<OrdersNumericFinalOnlyToggled>(_onNumericFinalOnlyToggled);
    on<OrdersAdditionalOnlyToggled>(_onAdditionalOnlyToggled);
    on<OrdersClearAllFilters>(_onClearAllFilters);

    // Side panel + edits
    on<OrdersSelectItemForEdit>(_onSelectItemForEdit);
    on<OrdersClearSelection>(_onClearSelection);
    on<OrdersApplyFinalEdit>(_onApplyFinalEdit);
    on<OrdersResetFinalEdit>(_onResetFinalEdit);
    on<OrdersClearAllEdits>(_onClearAllEdits);

    // additional request edits
    on<OrdersApplyAdditionalRequest>(_onApplyAdditionalRequest);
    on<OrdersRemoveAdditionalRequest>(_onRemoveAdditionalRequest);
    on<OrdersSendAdditionalRequestsPressed>(_onSendAdditionalRequestsPressed);
    on<OrdersSubmitOrderPressed>(_onSubmitOrderPressed);

    // NEW: tracking
    on<OrdersLoadAdditionalTracking>(_onLoadAdditionalTracking);
    on<OrdersSearchMismatchList>(_onSearchMismatchList);
    on<OrdersSearchMismatchItemsCode>(_onSearchByCode);
    on<OrdersSearchMismatchItemsName>(_onSearchByName);
    on<OrdersClearMismatchResult>((event, emit) {
      emit(state.copyWith(showMismatchResult: false));
    });
    on<OrdersLoadMaxAdj>(_onLoadMaxAdj);
    on<OrdersAddMaxAdj>(_onAddMaxAdj);
    on<OrdersDeleteMaxAdj>(_onDeleteMaxAdj);
    on<OrdersSearchMaxAdjList>(_onSearchMaxAdjList);
    on<OrdersExportPressed>(_onExportPressed);
    on<OrdersClearSelectedDemand>((event, emit) {
      emit(state.copyWith(selectedItemDemand: 0));
    });
    on<OrdersFetchItemDemand>((event, emit) async {
      final demand = await repo.fetchItemDemand(
        branch: state.branchName,
        itemCode: event.itemCode,
      );

      emit(state.copyWith(selectedItemDemand: demand));
    });
    on<OrdersToggleBranchMaxAdj>((event, emit) {
      emit(state.copyWith(onlyBranchMaxAdj: event.value));
    });
  }

  @override
  Future<void> close() {
    _progressTimer?.cancel();
    return super.close();
  }

  // ==========================
  // Generate
  // ==========================
  Future<void> _onPressedGenerate(
    OrdersPressedGenerate e,
    Emitter<OrdersState> emit,
  ) async {
    final submissionStatus = await repo.fetchSubmissionStatus(
      runDate: state.runDate,
      branchName: state.branchName,
    );

    emit(
      state.copyWith(
        status: OrdersStatus.generating,
        error: null,
        progress: 0,
        numericFinalOnly: submissionStatus == 'submitted'
            ? false
            : state.numericFinalOnly,
        progressMessage: 'Generating order...',
      ),
    );
    _startSmoothProgress(emit);

    try {
      await generateBranchOrder(
        runDate: state.runDate,
        branchName: state.branchName,
      );

      _progressTimer?.cancel();

      emit(
        state.copyWith(
          status: OrdersStatus.loading,
          progress: 0,

          progressMessage: 'Starting load...',
        ),
      );

      add(const OrdersLoadAll());
    } catch (err) {
      _progressTimer?.cancel();
      emit(state.copyWith(status: OrdersStatus.failure, error: err.toString()));
    }
  }

  void _startSmoothProgress(Emitter<OrdersState> emit) {
    _progressTimer?.cancel();
    var p = 0;

    _progressTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (state.status != OrdersStatus.generating) return;
      if (p >= 90) return;

      p += 2;
      emit(
        state.copyWith(progress: p, progressMessage: 'Generating... $p/100'),
      );
    });
  }

  // ==========================
  // Load
  // ==========================
  Future<void> _onLoadAll(OrdersLoadAll e, Emitter<OrdersState> emit) async {
    emit(
      state.copyWith(
        status: OrdersStatus.loading,
        error: null,
        progress: 0,
        progressMessage: 'Loading items...',
      ),
    );

    try {
      // 1) Load base rows
      final baseRows = await fetchOrdersAll(
        runDate: state.runDate,
        branchName: state.branchName,
        batchSize: 5000,
        onProgress: (loaded) {
          const total = 15000;
          final p = ((loaded / total) * 90).clamp(0, 90).round();
          emit(
            state.copyWith(
              status: OrdersStatus.loading,
              progress: p,
              progressMessage: 'Loading... $loaded / $total',
            ),
          );
        },
      );

      // 2) Load submission status + sent additional requests map
      emit(
        state.copyWith(
          status: OrdersStatus.loading,
          progress: 91,
          progressMessage: 'Syncing status...',
        ),
      );

      final submissionStatus = await repo.fetchSubmissionStatus(
        runDate: state.runDate,
        branchName: state.branchName,
      );

      final sentHistory = await repo.fetchAdditionalRequestsHistoryForBranch(
        runDate: state.runDate,
        branchName: state.branchName,
      );

      // build qty summary map (sum per item_code)
      final sentAdditional = <String, num>{};
      sentHistory.forEach((code, rows) {
        num total = 0;
        for (final r in rows) {
          final v = r['request_qty'];
          total += (v is num) ? v : (num.tryParse((v ?? '').toString()) ?? 0);
        }
        sentAdditional[code] = total;
      });

      // Show additional_request column ONLY if submitted
      final nextVisible = Set<String>.from(state.visibleColumns);
      nextVisible.add('additional_request');

      emit(
        state.copyWith(
          status: OrdersStatus.loading,
          progress: 92,
          progressMessage: 'Applying filters...',
          submissionStatus: submissionStatus,
          visibleColumns: nextVisible,
          sentAdditionalQtyByItemCode: sentAdditional,
          sentAdditionalHistoryByItemCode: sentHistory,
        ),
      );

      // 3) Load tracking list (flat requests with status)
      final trackingRaw = await repo.fetchAdditionalRequestsTrackingForBranch(
        runDate: state.runDate,
        branchName: state.branchName,
      );
      final trackingRows = trackingRaw
          .map(AdditionalRequestRow.fromMap)
          .toList();

      emit(
        state.copyWith(
          status: OrdersStatus.loading,
          progress: 93,
          progressMessage: 'Syncing tracking...',
          additionalTrackingRows: trackingRows,
        ),
      );

      final searched = _applySearch(baseRows, state.search);
      final orderDays = await repo.fetchBranchOrderDays(
        branchName: state.branchName,
      );

      final today = DateTime.parse(state.runDate).weekday;

      const map = {
        1: 'Monday',
        2: 'Tuesday',
        3: 'Wednesday',
        4: 'Thursday',
        5: 'Friday',
        6: 'Saturday',
        7: 'Sunday',
      };

      final todayName = map[today];

      final isOrderDay = orderDays.contains(todayName);
      final view = _applyUiFilters(
        rows: searched,
        categoryFilter: state.categoryFilter,
        formularyFilter: state.formularyFilter,
        nonWithSales45Only: state.nonWithSales45Only,
        numericFinalOnly: submissionStatus == 'submitted'
            ? false
            : state.numericFinalOnly,
        additionalOnly: state.additionalOnly,
        additionalEdits: state.additionalEdits,
        sentAdditionalQtyByItemCode: sentAdditional,
      );

      emit(
        state.copyWith(
          status: OrdersStatus.ready,
          progress: 100,
          progressMessage: 'Done ${baseRows.length}/${baseRows.length}',
          rows: baseRows,
          viewRows: view,
          isOrderDay: isOrderDay,

          error: null,
        ),
      );
    } catch (err) {
      emit(state.copyWith(status: OrdersStatus.failure, error: err.toString()));
    }
  }

  // ==========================
  // NEW: Load tracking list only
  // ==========================
  Future<void> _onLoadAdditionalTracking(
    OrdersLoadAdditionalTracking e,
    Emitter<OrdersState> emit,
  ) async {
    try {
      final raw = await repo.fetchAdditionalRequestsTrackingForBranch(
        branchName: state.branchName,
      );
      final rows = raw.map(AdditionalRequestRow.fromMap).toList();

      emit(state.copyWith(additionalTrackingRows: rows));
    } catch (err) {
      // keep UI stable; do not break whole page
    }
  }

  // ==========================
  // Search
  // ==========================
  void _onSearchChanged(OrdersSearchChanged e, Emitter<OrdersState> emit) {
    final nextSearch = e.search;

    final view = _applyUiFilters(
      rows: _applySearch(state.rows, nextSearch),
      categoryFilter: state.categoryFilter,
      formularyFilter: state.formularyFilter,
      nonWithSales45Only: state.nonWithSales45Only,
      numericFinalOnly: state.numericFinalOnly,
      additionalOnly: state.additionalOnly,
      additionalEdits: state.additionalEdits,
      sentAdditionalQtyByItemCode: state.sentAdditionalQtyByItemCode,
    );

    emit(state.copyWith(search: nextSearch, viewRows: view));
  }

  List<DailyOrderRow> _applySearch(List<DailyOrderRow> rows, String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return rows;

    bool hit(DailyOrderRow r) {
      final a = r.itemCode.toLowerCase();
      final b = r.itemName.toLowerCase();
      final bc = (r.barcode ?? '').toLowerCase();
      return a.contains(s) || b.contains(s) || bc.contains(s);
    }

    return rows.where(hit).toList();
  }

  // ==========================
  // Columns
  // ==========================
  void _onSetColumnVisible(
    OrdersSetColumnVisible e,
    Emitter<OrdersState> emit,
  ) {
    if (e.columnKey == 'additional_request' && !e.visible) {
      return;
    }

    final next = Set<String>.from(state.visibleColumns);

    if (e.visible) {
      next.add(e.columnKey);
    } else {
      next.remove(e.columnKey);
    }

    emit(state.copyWith(visibleColumns: next));
  }

  void _onReorderColumns(OrdersReorderColumns e, Emitter<OrdersState> emit) {
    final list = List<String>.from(state.columnOrder);

    var newIndex = e.newIndex;
    if (newIndex > e.oldIndex) newIndex -= 1;

    if (e.oldIndex < 0 || e.oldIndex >= list.length) return;
    if (newIndex < 0 || newIndex >= list.length) return;

    final item = list.removeAt(e.oldIndex);
    list.insert(newIndex, item);

    emit(state.copyWith(columnOrder: list));
  }

  void _onResetColumnsToDefault(
    OrdersResetColumnsToDefault e,
    Emitter<OrdersState> emit,
  ) {
    emit(
      state.copyWith(
        visibleColumns: OrdersState.defaultVisibleInTable.toSet(),
        columnOrder: OrdersState.defaultColumnOrder,
      ),
    );
  }

  // ==========================
  // Filters
  // ==========================
  void _onCategoryChanged(OrdersCategoryChanged e, Emitter<OrdersState> emit) {
    final view = _applyUiFilters(
      rows: _applySearch(state.rows, state.search),
      categoryFilter: e.category,
      formularyFilter: state.formularyFilter,
      nonWithSales45Only: state.nonWithSales45Only,
      numericFinalOnly: state.numericFinalOnly,
      additionalOnly: state.additionalOnly,
      additionalEdits: state.additionalEdits,
      sentAdditionalQtyByItemCode: state.sentAdditionalQtyByItemCode,
    );
    emit(state.copyWith(categoryFilter: e.category, viewRows: view));
  }

  void _onFormularyChanged(
    OrdersFormularyChanged e,
    Emitter<OrdersState> emit,
  ) {
    final view = _applyUiFilters(
      rows: _applySearch(state.rows, state.search),
      categoryFilter: state.categoryFilter,
      formularyFilter: e.formulary,
      nonWithSales45Only: state.nonWithSales45Only,
      numericFinalOnly: state.numericFinalOnly,
      additionalOnly: state.additionalOnly,
      additionalEdits: state.additionalEdits,
      sentAdditionalQtyByItemCode: state.sentAdditionalQtyByItemCode,
    );
    emit(state.copyWith(formularyFilter: e.formulary, viewRows: view));
  }

  void _onNonWithSales45Toggled(
    OrdersNonWithSales45Toggled e,
    Emitter<OrdersState> emit,
  ) {
    final view = _applyUiFilters(
      rows: _applySearch(state.rows, state.search),
      categoryFilter: state.categoryFilter,
      formularyFilter: state.formularyFilter,
      nonWithSales45Only: e.value,
      numericFinalOnly: state.numericFinalOnly,
      additionalOnly: state.additionalOnly,
      additionalEdits: state.additionalEdits,
      sentAdditionalQtyByItemCode: state.sentAdditionalQtyByItemCode,
    );
    emit(state.copyWith(nonWithSales45Only: e.value, viewRows: view));
  }

  void _onNumericFinalOnlyToggled(
    OrdersNumericFinalOnlyToggled e,
    Emitter<OrdersState> emit,
  ) {
    final view = _applyUiFilters(
      rows: _applySearch(state.rows, state.search),
      categoryFilter: state.categoryFilter,
      formularyFilter: state.formularyFilter,
      nonWithSales45Only: state.nonWithSales45Only,
      numericFinalOnly: e.value,
      additionalOnly: state.additionalOnly,
      additionalEdits: state.additionalEdits,
      sentAdditionalQtyByItemCode: state.sentAdditionalQtyByItemCode,
    );

    emit(state.copyWith(numericFinalOnly: e.value, viewRows: view));
  }

  void _onAdditionalOnlyToggled(
    OrdersAdditionalOnlyToggled e,
    Emitter<OrdersState> emit,
  ) {
    final view = _applyUiFilters(
      rows: _applySearch(state.rows, state.search),
      categoryFilter: state.categoryFilter,
      formularyFilter: state.formularyFilter,
      nonWithSales45Only: state.nonWithSales45Only,
      numericFinalOnly: state.numericFinalOnly,
      additionalOnly: e.value,
      additionalEdits: state.additionalEdits,
      sentAdditionalQtyByItemCode: state.sentAdditionalQtyByItemCode,
    );

    emit(state.copyWith(additionalOnly: e.value, viewRows: view));
  }

  void _onClearAllFilters(OrdersClearAllFilters e, Emitter<OrdersState> emit) {
    const category = 'ALL';
    const formulary = 'ALL';
    const nonSales = false;
    const search = '';
    const numericFinalOnly = false;
    const additionalOnly = false;

    final view = _applyUiFilters(
      rows: _applySearch(state.rows, search),
      categoryFilter: category,
      formularyFilter: formulary,
      nonWithSales45Only: nonSales,
      numericFinalOnly: numericFinalOnly,
      additionalOnly: additionalOnly,
      additionalEdits: state.additionalEdits,
      sentAdditionalQtyByItemCode: state.sentAdditionalQtyByItemCode,
    );

    emit(
      state.copyWith(
        search: search,
        categoryFilter: category,
        formularyFilter: formulary,
        nonWithSales45Only: nonSales,
        numericFinalOnly: numericFinalOnly,
        additionalOnly: additionalOnly,
        viewRows: view,
      ),
    );
  }

  List<DailyOrderRow> _applyUiFilters({
    required List<DailyOrderRow> rows,
    required String categoryFilter,
    required String formularyFilter,
    required bool nonWithSales45Only,
    required bool numericFinalOnly,
    required bool additionalOnly,
    required Map<String, AdditionalRequestEdit> additionalEdits,
    required Map<String, num> sentAdditionalQtyByItemCode,
  }) {
    bool matchCategory(DailyOrderRow r) {
      if (categoryFilter == 'ALL') return true;
      final cat = (r.category ?? '').toString().trim();
      return cat == categoryFilter;
    }

    bool matchFormulary(DailyOrderRow r) {
      if (formularyFilter == 'ALL') return true;
      final f = (r.branchFormulary ?? '').toString().trim().toUpperCase();
      return f == formularyFilter.toUpperCase();
    }

    bool matchNonWithSales45(DailyOrderRow r) {
      if (!nonWithSales45Only) return true;
      final f = (r.branchFormulary ?? '').toString().trim().toUpperCase();
      final sales45 = _toNum(r.qty30DaysFromLast45d);
      return f == 'NON' && sales45 > 0;
    }

    bool matchNumericFinalOnly(DailyOrderRow r) {
      if (!numericFinalOnly) return true;

      return _isStrictNumericFinalReorder(r.finalReorderQtyStoreStockGt0);
    }

    bool matchAdditionalOnly(DailyOrderRow r) {
      if (!additionalOnly) return true;
      final hasLocalDraft = additionalEdits.containsKey(r.itemCode);
      final sentQty = sentAdditionalQtyByItemCode[r.itemCode] ?? 0;
      final hasSent = sentQty > 0;
      return hasLocalDraft || hasSent;
    }

    return rows.where((r) {
      return matchCategory(r) &&
          matchFormulary(r) &&
          matchNonWithSales45(r) &&
          matchNumericFinalOnly(r) &&
          matchAdditionalOnly(r);
    }).toList();
  }

  bool _isStrictNumericFinalReorder(String? v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return false;
    final normalized = s.replaceAll(',', '');
    return num.tryParse(normalized) != null;
  }

  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return 0;
    return num.tryParse(s.replaceAll(',', '')) ?? 0;
  }

  // ==========================
  // Side panel selection
  // ==========================
  void _onSelectItemForEdit(
    OrdersSelectItemForEdit e,
    Emitter<OrdersState> emit,
  ) {
    emit(state.copyWith(selectedItemCode: e.itemCode));
  }

  void _onClearSelection(OrdersClearSelection e, Emitter<OrdersState> emit) {
    emit(state.copyWith(selectedItemCode: null));
  }

  // ==========================
  // Final edits
  // ==========================
  void _onApplyFinalEdit(OrdersApplyFinalEdit e, Emitter<OrdersState> emit) {
    final next = Map<String, FinalReorderEdit>.from(state.finalEdits);
    final reason = e.reason.trim();

    if (e.newQty == e.oldQty) {
      next.remove(e.itemCode);
      emit(state.copyWith(finalEdits: next));
      return;
    }

    if (reason.isEmpty) return;

    next[e.itemCode] = FinalReorderEdit(
      itemCode: e.itemCode,
      oldQty: e.oldQty,
      newQty: e.newQty,
      reason: reason,
    );

    emit(state.copyWith(finalEdits: next));
  }

  void _onResetFinalEdit(OrdersResetFinalEdit e, Emitter<OrdersState> emit) {
    final next = Map<String, FinalReorderEdit>.from(state.finalEdits);
    next.remove(e.itemCode);
    emit(state.copyWith(finalEdits: next));
  }

  void _onClearAllEdits(OrdersClearAllEdits e, Emitter<OrdersState> emit) {
    emit(state.copyWith(finalEdits: const {}));
  }

  void _onColumnResized(OrdersColumnResized e, Emitter<OrdersState> emit) {
    final next = Map<String, double>.from(state.columnWidths);
    next[e.columnKey] = e.width;
    emit(state.copyWith(columnWidths: next));
  }

  // ==========================
  // Additional requests (local draft)
  // ==========================
  void _onApplyAdditionalRequest(
    OrdersApplyAdditionalRequest e,
    Emitter<OrdersState> emit,
  ) {
    final code = e.itemCode.trim();
    final name = e.itemName.trim();
    final reason = e.reason.trim();

    if (code.isEmpty) return;
    if (name.isEmpty) return;
    if (e.requestQty <= 0) return;
    if (reason.isEmpty) return;

    final next = Map<String, AdditionalRequestEdit>.from(state.additionalEdits);
    next[code] = AdditionalRequestEdit(
      itemCode: code,
      itemName: name,
      requestQty: e.requestQty,
      reason: reason,
      isUrgent: e.isUrgent,
    );

    final view = _applyUiFilters(
      rows: _applySearch(state.rows, state.search),
      categoryFilter: state.categoryFilter,
      formularyFilter: state.formularyFilter,
      nonWithSales45Only: state.nonWithSales45Only,
      numericFinalOnly: state.numericFinalOnly,
      additionalOnly: state.additionalOnly,
      additionalEdits: next,
      sentAdditionalQtyByItemCode: state.sentAdditionalQtyByItemCode,
    );

    emit(state.copyWith(additionalEdits: next, viewRows: view));
  }

  void _onRemoveAdditionalRequest(
    OrdersRemoveAdditionalRequest e,
    Emitter<OrdersState> emit,
  ) {
    final next = Map<String, AdditionalRequestEdit>.from(state.additionalEdits);
    next.remove(e.itemCode);

    final view = _applyUiFilters(
      rows: _applySearch(state.rows, state.search),
      categoryFilter: state.categoryFilter,
      formularyFilter: state.formularyFilter,
      nonWithSales45Only: state.nonWithSales45Only,
      numericFinalOnly: state.numericFinalOnly,
      additionalOnly: state.additionalOnly,
      additionalEdits: next,
      sentAdditionalQtyByItemCode: state.sentAdditionalQtyByItemCode,
    );

    emit(state.copyWith(additionalEdits: next, viewRows: view));
  }

  // ==========================
  // Send additional requests to DB
  // ==========================
  Future<void> _onSendAdditionalRequestsPressed(
    OrdersSendAdditionalRequestsPressed e,
    Emitter<OrdersState> emit,
  ) async {
    final zone = e.zone.trim();
    if (zone.isEmpty) return;
    if (state.branchName.trim().isEmpty) return;

    if (state.additionalEdits.isEmpty) return;

    emit(
      state.copyWith(
        status: OrdersStatus.loading,
        error: null,
        progressMessage: 'Sending additional requests...',
      ),
    );

    try {
      final nowIso = DateTime.now().toIso8601String();

      const uuid = Uuid();
      final requestGroupId = uuid.v4();

      final payload = state.additionalEdits.values.map((a) {
        return <String, dynamic>{
          'request_group_id': requestGroupId,
          'run_date': state.runDate,
          'zone': zone,
          'branch_name': state.branchName,
          'item_code': a.itemCode,
          'item_name': a.itemName,
          'request_qty': a.requestQty,
          'reason': a.reason,
          'status': 'pending',
          'contact_logistic': a.isUrgent ? 'urgent' : null,

          'created_at': nowIso,
        };
      }).toList();

      await repo.insertAdditionalRequests(
        runDate: state.runDate,
        zone: zone,
        branchName: state.branchName,
        rows: payload,
      );

      final sentAdditionalQty = await repo.fetchAdditionalRequestsForBranch(
        runDate: state.runDate,
        branchName: state.branchName,
      );

      final sentHistory = await repo.fetchAdditionalRequestsHistoryForBranch(
        runDate: state.runDate,
        branchName: state.branchName,
      );

      final trackingRaw = await repo.fetchAdditionalRequestsTrackingForBranch(
        runDate: state.runDate,
        branchName: state.branchName,
      );

      final trackingRows = trackingRaw
          .map(AdditionalRequestRow.fromMap)
          .toList();

      final view = _applyUiFilters(
        rows: _applySearch(state.rows, state.search),
        categoryFilter: state.categoryFilter,
        formularyFilter: state.formularyFilter,
        nonWithSales45Only: state.nonWithSales45Only,
        numericFinalOnly: state.numericFinalOnly,
        additionalOnly: state.additionalOnly,
        additionalEdits: const {},
        sentAdditionalQtyByItemCode: sentAdditionalQty,
      );

      emit(
        state.copyWith(
          status: OrdersStatus.ready,
          additionalEdits: const {},
          sentAdditionalQtyByItemCode: sentAdditionalQty,
          sentAdditionalHistoryByItemCode: sentHistory,
          additionalTrackingRows: trackingRows,
          viewRows: view,
          progressMessage: 'Additional requests sent',
        ),
      );
    } catch (err) {
      emit(state.copyWith(status: OrdersStatus.failure, error: err.toString()));
    }
  }

  // ==========================
  // Submit order (save edits + status -> submitted)
  // ==========================
  Future<void> _onSubmitOrderPressed(
    OrdersSubmitOrderPressed e,
    Emitter<OrdersState> emit,
  ) async {
    if (!state.isOrderDay) return;
    final zone = e.zone.trim();
    if (zone.isEmpty) return;
    if (state.branchName.trim().isEmpty) return;

    emit(
      state.copyWith(
        status: OrdersStatus.loading,
        error: null,
        progressMessage: 'Submitting order...',
      ),
    );

    try {
      final now = DateTime.now().toIso8601String();

      /// ✅ MOVE THIS HERE (outside IF)
      final rowsByCode = <String, DailyOrderRow>{};
      for (final r in state.rows) {
        rowsByCode[r.itemCode] = r;
      }

      // ==========================
      // 1) Save final edits
      // ==========================
      if (state.finalEdits.isNotEmpty) {
        final editsPayload = <Map<String, dynamic>>[];

        for (final edit in state.finalEdits.values) {
          final row = rowsByCode[edit.itemCode];
          final itemName = row?.itemName ?? '';

          editsPayload.add(<String, dynamic>{
            'run_date': state.runDate,
            'zone': zone,
            'branch_name': state.branchName,
            'item_code': edit.itemCode,
            'item_name': itemName,
            'old_qty': edit.oldQty,
            'new_qty': edit.newQty,
            'reason': edit.reason,
            'created_at': now,
            'updated_at': now,
          });
        }

        await repo.upsertOrderEdits(
          runDate: state.runDate,
          zone: zone,
          branchName: state.branchName,
          rows: editsPayload,
        );
      }

      // ==========================
      // 🔥 2) APPLY MAX ADJ (AFTER SAVE)
      // ==========================
      for (final edit in state.finalEdits.values) {
        if (edit.newQty < edit.oldQty) {
          final row = rowsByCode[edit.itemCode];
          if (row == null) continue;

          final demand = await repo.fetchItemDemand(
            branch: state.branchName,
            itemCode: edit.itemCode,
          );

          await repo.upsertMaxAdjFromFinalReorder(
            branchName: state.branchName,
            itemCode: edit.itemCode,
            itemName: row.itemName,
            oldQty: edit.oldQty,
            newQty: edit.newQty,
            currentDemand: demand,
            reason: edit.reason,
          );
        }
      }

      // ==========================
      // 3) Submit status
      // ==========================
      await repo.upsertSubmission(
        runDate: state.runDate,
        zone: zone,
        branchName: state.branchName,
        status: 'submitted',
      );

      final nextVisible = Set<String>.from(state.visibleColumns);
      nextVisible.add('additional_request');

      final view = _applyUiFilters(
        rows: _applySearch(state.rows, state.search),
        categoryFilter: state.categoryFilter,
        formularyFilter: state.formularyFilter,
        nonWithSales45Only: state.nonWithSales45Only,
        numericFinalOnly: false,
        additionalOnly: state.additionalOnly,
        additionalEdits: state.additionalEdits,
        sentAdditionalQtyByItemCode: state.sentAdditionalQtyByItemCode,
      );

      emit(
        state.copyWith(
          status: OrdersStatus.ready,
          submissionStatus: 'submitted',
          visibleColumns: nextVisible,
          numericFinalOnly: false,
          viewRows: view,
          progressMessage: 'Submitted',
        ),
      );
    } catch (err) {
      emit(state.copyWith(status: OrdersStatus.failure, error: err.toString()));
    }
  }

  Future<void> _onLoadMismatch(
    OrdersLoadMismatch e,
    Emitter<OrdersState> emit,
  ) async {
    emit(state.copyWith(isMismatchLoading: true));

    final data = await repo.fetchMismatch(branch: state.branchName);

    emit(
      state.copyWith(
        status: OrdersStatus.ready,
        mismatchItems: data,
        isMismatchLoading: false,
      ),
    );
  }

  Future<void> _onAddMismatch(
    OrdersAddMismatch e,
    Emitter<OrdersState> emit,
  ) async {
    emit(state.copyWith(isMismatchLoading: true));

    try {
      // 🔥 أهم سطر (كان ناقص)
      await repo.insertMismatch(e.data);

      final newList = await repo.fetchMismatch(branch: state.branchName);

      emit(
        state.copyWith(
          status: OrdersStatus.ready,
          mismatchItems: newList,
          error: null,
          isMismatchLoading: false,
          lastActionSuccess: true,
          showMismatchResult: true,
        ),
      );
    } catch (err) {
      emit(
        state.copyWith(
          status: OrdersStatus.ready,
          error: err.toString(),
          lastActionSuccess: false,
          showMismatchResult: true,
          isMismatchLoading: false,
        ),
      );
    }
  }

  Future<void> _onUpdateMismatch(
    OrdersUpdateMismatch e,
    Emitter<OrdersState> emit,
  ) async {
    emit(state.copyWith(isMismatchLoading: true));

    await repo.updateMismatch(
      id: e.id,
      system: e.system,
      actual: e.actual,
      old: e.old,
    );
    emit(state.copyWith(isMismatchLoading: true));

    add(const OrdersLoadMismatch());
  }

  Future<void> _onDeleteMismatch(
    OrdersDeleteMismatch e,
    Emitter<OrdersState> emit,
  ) async {
    if (state.isMismatchLoading) return;

    emit(state.copyWith(isMismatchLoading: true));

    try {
      await repo.deleteMismatch(e.id);

      add(const OrdersLoadMismatch());
    } catch (err) {
      emit(state.copyWith(error: err.toString()));
    }

    emit(state.copyWith(isMismatchLoading: false));
  }

  void _onToggleMismatchEdit(
    OrdersToggleMismatchEdit e,
    Emitter<OrdersState> emit,
  ) {
    emit(state.copyWith(editingMismatchId: e.id));
  }

  void _onSearchMismatchList(
    OrdersSearchMismatchList e,
    Emitter<OrdersState> emit,
  ) {
    emit(state.copyWith(mismatchSearch: e.query));
  }

  EventTransformer<T> debounce<T>() {
    return (events, mapper) =>
        events.debounce(const Duration(milliseconds: 300)).switchMap(mapper);
  }

  Future<void> _onSearchByCode(
    OrdersSearchMismatchItemsCode e,
    Emitter<OrdersState> emit,
  ) async {
    final res = await repo.searchItemsByCode(e.query);
    emit(state.copyWith(mismatchSuggestions: res));
  }

  Future<void> _onSearchByName(
    OrdersSearchMismatchItemsName e,
    Emitter<OrdersState> emit,
  ) async {
    final res = await repo.searchItemsByName(e.query);
    emit(state.copyWith(mismatchSuggestions: res));
  }

  Future<void> _onSearchMismatch(
    OrdersSearchMismatchItems e,
    Emitter<OrdersState> emit,
  ) async {
    emit(state.copyWith(mismatchSuggestions: []));
  }

  Future<void> _onLoadMaxAdj(
    OrdersLoadMaxAdj e,
    Emitter<OrdersState> emit,
  ) async {
    emit(state.copyWith(isMaxAdjLoading: true));

    final data = await repo.fetchMaxAdj(branch: state.branchName);

    emit(
      state.copyWith(
        status: OrdersStatus.ready,
        maxAdjItems: data,
        isMaxAdjLoading: false,
      ),
    );
  }

  Future<void> _onAddMaxAdj(
    OrdersAddMaxAdj e,
    Emitter<OrdersState> emit,
  ) async {
    emit(state.copyWith(isMaxAdjLoading: true));

    try {
      await repo.insertMaxAdj(e.data);

      final newList = await repo.fetchMaxAdj(branch: state.branchName);

      emit(
        state.copyWith(
          status: OrdersStatus.ready,
          maxAdjItems: newList,
          error: null,
          isMaxAdjLoading: false,

          lastActionSuccess: true,
          showMismatchResult: true,
        ),
      );
    } catch (err) {
      emit(
        state.copyWith(
          status: OrdersStatus.ready,
          error: err.toString(),
          lastActionSuccess: false,
          showMismatchResult: true,
        ),
      );
    }
  }

  Future<void> _onDeleteMaxAdj(
    OrdersDeleteMaxAdj e,
    Emitter<OrdersState> emit,
  ) async {
    emit(state.copyWith(isMaxAdjLoading: true));

    await repo.deleteMaxAdj(e.id);

    add(const OrdersLoadMaxAdj());
  }

  void _onSearchMaxAdjList(
    OrdersSearchMaxAdjList e,
    Emitter<OrdersState> emit,
  ) {
    emit(state.copyWith(maxAdjSearch: e.query));
  }

  Future<void> _onExportPressed(
    OrdersExportPressed e,
    Emitter<OrdersState> emit,
  ) async {
    emit(state.copyWith(isExporting: true));

    await Future.delayed(const Duration(milliseconds: 100));

    try {
      final columns = state.columnOrder
          .where((c) => state.visibleColumns.contains(c))
          .toList();

      final rows = state.viewRows.map((r) {
        final map = <String, dynamic>{};

        for (final col in columns) {
          map[col] = OrderRowMapper.getValue(
            r,
            col,
            state.sentAdditionalQtyByItemCode,
          );
        }

        return map;
      }).toList();

      await ExcelExporter.exportOrdersWeb(rows: rows, columns: columns);

      emit(state.copyWith(isExporting: false));
    } catch (e) {
      emit(state.copyWith(isExporting: false));
    }
  }
}
