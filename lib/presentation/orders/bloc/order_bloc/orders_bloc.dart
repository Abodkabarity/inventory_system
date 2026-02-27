// orders_bloc.dart
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

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

    // ✅ Columns
    on<OrdersSetColumnVisible>(_onSetColumnVisible);
    on<OrdersReorderColumns>(_onReorderColumns);
    on<OrdersResetColumnsToDefault>(_onResetColumnsToDefault);
    on<OrdersColumnResized>(_onColumnResized);
    // Filters
    on<OrdersCategoryChanged>(_onCategoryChanged);
    on<OrdersFormularyChanged>(_onFormularyChanged);
    on<OrdersNonWithSales45Toggled>(_onNonWithSales45Toggled);

    // ✅ NEW Filters
    on<OrdersNumericFinalOnlyToggled>(_onNumericFinalOnlyToggled);
    on<OrdersClearAllFilters>(_onClearAllFilters);

    // Side panel + edits
    on<OrdersSelectItemForEdit>(_onSelectItemForEdit);
    on<OrdersClearSelection>(_onClearSelection);
    on<OrdersApplyFinalEdit>(_onApplyFinalEdit);
    on<OrdersResetFinalEdit>(_onResetFinalEdit);
    on<OrdersClearAllEdits>(_onClearAllEdits);
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
    emit(
      state.copyWith(
        status: OrdersStatus.generating,
        error: null,
        progress: 0,
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

      emit(
        state.copyWith(
          status: OrdersStatus.loading,
          progress: 92,
          progressMessage: 'Applying filters...',
        ),
      );

      final searched = _applySearch(baseRows, state.search);

      final view = _applyUiFilters(
        rows: searched,
        categoryFilter: state.categoryFilter,
        formularyFilter: state.formularyFilter,
        nonWithSales45Only: state.nonWithSales45Only,
        numericFinalOnly: state.numericFinalOnly,
      );

      emit(
        state.copyWith(
          status: OrdersStatus.ready,
          progress: 100,
          progressMessage: 'Done ${baseRows.length}/${baseRows.length}',
          rows: baseRows,
          viewRows: view,
        ),
      );
    } catch (err) {
      emit(state.copyWith(status: OrdersStatus.failure, error: err.toString()));
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
    );
    emit(state.copyWith(nonWithSales45Only: e.value, viewRows: view));
  }

  // ✅ NEW: numeric final reorder only
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
    );

    emit(state.copyWith(numericFinalOnly: e.value, viewRows: view));
  }

  // ✅ NEW: clear all filters (keep numericFinalOnly ON by default)
  void _onClearAllFilters(OrdersClearAllFilters e, Emitter<OrdersState> emit) {
    const category = 'ALL';
    const formulary = 'ALL';
    const nonSales = false;
    const search = '';

    // keep ON
    const numericFinalOnly = true;

    final view = _applyUiFilters(
      rows: _applySearch(state.rows, search),
      categoryFilter: category,
      formularyFilter: formulary,
      nonWithSales45Only: nonSales,
      numericFinalOnly: numericFinalOnly,
    );

    emit(
      state.copyWith(
        search: search,
        categoryFilter: category,
        formularyFilter: formulary,
        nonWithSales45Only: nonSales,
        numericFinalOnly: numericFinalOnly,
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

    // ✅ NEW: strict numeric final reorder only
    bool matchNumericFinalOnly(DailyOrderRow r) {
      if (!numericFinalOnly) return true;
      return _isStrictNumericFinalReorder(r.finalReorderQtyStoreStockGt0);
    }

    return rows.where((r) {
      return matchCategory(r) &&
          matchFormulary(r) &&
          matchNonWithSales45(r) &&
          matchNumericFinalOnly(r);
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

    // If no change -> remove
    if (e.newQty == e.oldQty) {
      next.remove(e.itemCode);
      emit(state.copyWith(finalEdits: next));
      return;
    }

    // Reason is mandatory
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
}
