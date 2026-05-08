// orders_state.dart
import 'package:equatable/equatable.dart';

import '../../../../domain/entities/daily_order_row.dart';

enum OrdersStatus { idle, generating, loading, ready, failure }

class FinalReorderEdit extends Equatable {
  final String itemCode;
  final int oldQty;
  final int newQty;
  final String reason;

  const FinalReorderEdit({
    required this.itemCode,
    required this.oldQty,
    required this.newQty,
    required this.reason,
  });

  int get diff => newQty - oldQty;

  @override
  List<Object?> get props => [itemCode, oldQty, newQty, reason];
}

class AdditionalRequestEdit extends Equatable {
  final String id;

  final String itemCode;
  final String itemName;
  final num requestQty;
  final String reason;
  final bool isUrgent;

  const AdditionalRequestEdit({
    required this.itemCode,
    required this.itemName,
    required this.requestQty,
    required this.reason,
    required this.isUrgent,
    required this.id,
  });

  @override
  List<Object?> get props => [
    itemCode,
    itemName,
    requestQty,
    reason,
    isUrgent,
    id,
  ];
}

// Tracking row (flat list) for additional requests
class AdditionalRequestRow extends Equatable {
  final String id;
  final String itemCode;
  final String itemName;

  final num requestQty;
  final String reason;

  final String status; // pending / sent_to_store / done
  final num? fulfilledQty; // optional
  final String? storeNote; // optional

  final DateTime createdAt;
  final DateTime? sentToStoreAt;
  final DateTime? doneAt;

  const AdditionalRequestRow({
    required this.id,
    required this.itemCode,
    required this.itemName,
    required this.requestQty,
    required this.reason,
    required this.status,
    required this.fulfilledQty,
    required this.storeNote,
    required this.createdAt,
    required this.sentToStoreAt,
    required this.doneAt,
  });

  bool get isModifiedQty {
    if (fulfilledQty == null) return false;
    return fulfilledQty != requestQty;
  }

  AdditionalRequestRow copyWith({
    String? status,
    num? fulfilledQty,
    String? storeNote,
    DateTime? sentToStoreAt,
    DateTime? doneAt,
  }) {
    return AdditionalRequestRow(
      id: id,
      itemCode: itemCode,
      itemName: itemName,
      requestQty: requestQty,
      reason: reason,
      status: status ?? this.status,
      fulfilledQty: fulfilledQty ?? this.fulfilledQty,
      storeNote: storeNote ?? this.storeNote,
      createdAt: createdAt,
      sentToStoreAt: sentToStoreAt ?? this.sentToStoreAt,
      doneAt: doneAt ?? this.doneAt,
    );
  }

  static num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return 0;
    return num.tryParse(s.replaceAll(',', '')) ?? 0;
  }

  static DateTime? _toDt(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static AdditionalRequestRow fromMap(Map<String, dynamic> map) {
    final id = (map['id'] ?? '').toString().trim();
    final itemCode = (map['item_code'] ?? '').toString().trim();
    final itemName = (map['item_name'] ?? '').toString().trim();
    final requestQty = _toNum(map['request_qty']);
    final reason = (map['reason'] ?? '').toString();
    final status = (map['status'] ?? 'pending').toString().trim();

    final fulfilled = (map.containsKey('fulfilled_qty'))
        ? (map['fulfilled_qty'] == null ? null : _toNum(map['fulfilled_qty']))
        : null;

    final storeNote = map['store_note']?.toString();

    final createdAt = _toDt(map['created_at']) ?? DateTime.now();
    final sentToStoreAt = _toDt(map['sent_to_store_at']);
    final doneAt = _toDt(map['done_at']);

    return AdditionalRequestRow(
      id: id,
      itemCode: itemCode,
      itemName: itemName,
      requestQty: requestQty,
      reason: reason,
      status: status,
      fulfilledQty: fulfilled,
      storeNote: storeNote,
      createdAt: createdAt,
      sentToStoreAt: sentToStoreAt,
      doneAt: doneAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    itemCode,
    itemName,
    requestQty,
    reason,
    status,
    fulfilledQty,
    storeNote,
    createdAt,
    sentToStoreAt,
    doneAt,
  ];
}

class OrdersState extends Equatable {
  final OrdersStatus status;

  final String runDate;
  final String branchName;
  final String maxAdjSearch;
  final String search;
  // ==========================
  // MISMATCH
  // ==========================
  final List<Map<String, dynamic>> mismatchItems;
  final List<Map<String, dynamic>> mismatchSuggestions;
  final String? editingMismatchId;
  final List<DailyOrderRow> rows;
  final List<DailyOrderRow> viewRows;
  final String mismatchSearch;
  final int progress;
  final String? progressMessage;
  final bool onlyBranchMaxAdj;
  final String? error;
  final bool isMismatchLoading;
  final Map<String, List<Map<String, dynamic>>> sentAdditionalHistoryByItemCode;
  final bool showCreate;
  final Set<String> visibleColumns;
  final List<String> columnOrder;
  final Map<String, double> columnWidths;
  final bool isRemovingFilters;
  final String categoryFilter;
  final String formularyFilter;
  final bool nonWithSales45Only;
  final bool numericFinalOnly;
  final bool? lastActionSuccess;
  final Map<String, FinalReorderEdit> finalEdits;
  final List<Map<String, dynamic>> maxAdjItems;
  final bool isMaxAdjLoading;
  // additional requests (local draft)
  final Map<String, AdditionalRequestEdit> additionalEdits;
  final num selectedItemDemand;
  // already sent additional requests (loaded from db) - per item_code sum
  final Map<String, num> sentAdditionalQtyByItemCode;

  // filter additional only
  final bool additionalOnly;

  // submission status
  final String submissionStatus; // draft/submitted
  final bool isExporting;
  final String? selectedItemCode;
  final bool? showMismatchResult;
  // tracking list (flat list of requests rows)
  final List<AdditionalRequestRow> additionalTrackingRows;
  final bool isOrderDay;
  const OrdersState({
    required this.status,
    required this.runDate,
    required this.branchName,
    required this.search,
    required this.rows,
    required this.viewRows,
    required this.progress,
    required this.visibleColumns,
    required this.columnOrder,
    required this.columnWidths,
    required this.categoryFilter,
    required this.formularyFilter,
    required this.nonWithSales45Only,
    required this.numericFinalOnly,
    required this.finalEdits,
    required this.additionalEdits,
    required this.sentAdditionalQtyByItemCode,
    required this.additionalOnly,
    required this.submissionStatus,
    required this.sentAdditionalHistoryByItemCode,
    required this.additionalTrackingRows,
    this.selectedItemCode,
    this.progressMessage,
    this.error,
    required this.mismatchItems,
    required this.mismatchSuggestions,
    this.editingMismatchId,
    required this.mismatchSearch,
    this.lastActionSuccess,
    this.showMismatchResult,
    required this.isMismatchLoading,
    required this.maxAdjItems,
    required this.isMaxAdjLoading,
    required this.maxAdjSearch,
    required this.isExporting,
    required this.isOrderDay,
    required this.selectedItemDemand,
    required this.onlyBranchMaxAdj,
    required this.showCreate,
    required this.isRemovingFilters,
  });

  static const List<String> defaultVisibleInTable = [
    'item_code',
    'item_name',
    'branch_stock',
    'store_stock',
    'demand_for_30_days',
    'final_reorder_qty_store_stock_gt_0',
    'qty_30_days_from_last_45d',
    'branch_formulary',
  ];

  static const List<String> defaultColumnOrder = [
    ...defaultVisibleInTable,

    // Keep it in the system, but it becomes visible only after submit
    'additional_request',

    'branch',
    'mismatch_stock',
    'pending_stock_received',
    'extra_qty_more_than_month',
    'max_adjustment_30d',
    'reorder_point_min',
    'reorder_max',
    'reorder_qty',
    'date_of_last_qty_received_in_branch',
    'assortment_qty_base_stock',
    'assortment_by',
    'reason',
    'assortment_start',
    'assortment_end',
    'tma_qty',
    'tma_start',
    'tma_end',
    'item_purchase_type',
    'sales_orientation',
    'category',
    'sub_category',
    'company',
    'supplier',
    'indication',
    'active_ingredient',
    'pack_size',
    'concentration',
    'product_type_form',
    'retail_price',
    'vat',
    'is_upp',
    'upp_thiqa',
    'upp_basic',
    'tier',
    'item_minimum_order_unit',
    'barcode',
    'store_item_classifications',
    'goods_received_last_7_days',
    'total_sold_qty_cash_last_90',
    'total_sold_qty_online_last_90',
    'total_sold_qty_insurance_last_90',
  ];

  // ✅ FIX: needed by other files that reference OrdersState.defaultMinWidth
  static const double defaultMinWidth = 120;

  static double defaultWidthFor(String key) {
    if (key == 'row_no') return 70;
    if (key == 'additional_request') return 190;

    if (key == 'item_name') return 420;
    if (key == 'item_code') return 160;
    if (key == 'branch') return 170;

    if (key == 'final_reorder_qty_store_stock_gt_0') return 260;
    if (key == 'max_adjustment_30d') return 240;
    if (key == 'reason_for_max_adjustment_30d') return 280;
    if (key == 'pending_stock_received') return 220;
    if (key == 'extra_qty_more_than_month') return 230;

    if (key == 'store_item_classifications') return 260;
    if (key == 'active_ingredient') return 240;
    if (key == 'product_type_form') return 210;

    if (key == 'category' || key == 'company' || key == 'supplier') return 220;
    if (key == 'barcode') return 190;
    if (key == 'branch_formulary') return 170;

    return 170;
  }

  static Map<String, double> defaultColumnWidths(Iterable<String> allKeys) {
    final map = <String, double>{};
    for (final k in allKeys) {
      map[k] = defaultWidthFor(k);
    }
    return map;
  }

  factory OrdersState.initial({
    required String runDate,
    required String branchName,
  }) {
    final allKeys = <String>[
      'row_no',
      'additional_request',
      ...defaultColumnOrder,
    ];

    return OrdersState(
      status: OrdersStatus.idle,
      runDate: runDate,
      branchName: branchName,
      search: '',
      rows: const [],
      viewRows: const [],
      progress: 0,
      progressMessage: null,
      error: null,
      mismatchItems: const [],
      mismatchSuggestions: const [],
      editingMismatchId: null,
      maxAdjSearch: '',
      isMismatchLoading: false,
      isExporting: false,
      selectedItemDemand: 0,
      visibleColumns: defaultVisibleInTable.toSet(),
      columnOrder: defaultColumnOrder,
      columnWidths: defaultColumnWidths(allKeys),
      categoryFilter: 'ALL',
      formularyFilter: 'ALL',
      nonWithSales45Only: false,
      showCreate: true,
      isRemovingFilters: false,
      numericFinalOnly: false,
      lastActionSuccess: false,
      showMismatchResult: false,
      finalEdits: const {},
      isOrderDay: true,
      additionalEdits: const {},
      sentAdditionalHistoryByItemCode: const {},
      sentAdditionalQtyByItemCode: const {},
      additionalOnly: false,
      submissionStatus: 'draft',
      selectedItemCode: null,
      additionalTrackingRows: const [],
      mismatchSearch: '',
      maxAdjItems: const [],
      isMaxAdjLoading: false,
      onlyBranchMaxAdj: false,
    );
  }

  bool get isInitial => status == OrdersStatus.idle && rows.isEmpty;

  bool get isBusy =>
      status == OrdersStatus.generating || status == OrdersStatus.loading;

  bool get hasEdits => finalEdits.isNotEmpty;

  int get editsCount => finalEdits.length;

  bool get hasAdditional => additionalEdits.isNotEmpty;

  int get additionalCount => additionalEdits.length;

  bool get isSubmitted => submissionStatus == 'submitted';

  List<String> get orderedVisibleColumns =>
      columnOrder.where(visibleColumns.contains).toList();

  // tracking stats
  int get trackingTotal => additionalTrackingRows.length;

  int get trackingPending => additionalTrackingRows
      .where((r) => r.status.trim().toLowerCase() == 'pending')
      .length;

  int get trackingSentToStore => additionalTrackingRows
      .where((r) => r.status.trim().toLowerCase() == 'sent_to_store')
      .length;

  int get trackingDone => additionalTrackingRows
      .where((r) => r.status.trim().toLowerCase() == 'done')
      .length;

  int get trackingModifiedQty =>
      additionalTrackingRows.where((r) => r.isModifiedQty).length;

  OrdersState copyWith({
    OrdersStatus? status,
    String? runDate,
    String? branchName,
    String? search,
    List<DailyOrderRow>? rows,
    List<DailyOrderRow>? viewRows,
    int? progress,
    Map<String, List<Map<String, dynamic>>>? sentAdditionalHistoryByItemCode,
    String? progressMessage,
    String? error,
    num? selectedItemDemand,
    String? maxAdjSearch,
    bool? showMismatchResult,
    bool? isRemovingFilters,
    Set<String>? visibleColumns,
    List<String>? columnOrder,
    Map<String, double>? columnWidths,
    String? categoryFilter,
    String? formularyFilter,
    bool? nonWithSales45Only,
    bool? numericFinalOnly,
    bool? isMismatchLoading,
    bool? lastActionSuccess,
    bool? isExporting,
    bool? isOrderDay,
    bool? onlyBranchMaxAdj,
    bool? showCreate,
    List<Map<String, dynamic>>? mismatchItems,
    List<Map<String, dynamic>>? mismatchSuggestions,
    String? editingMismatchId,
    Map<String, FinalReorderEdit>? finalEdits,
    Map<String, AdditionalRequestEdit>? additionalEdits,
    Map<String, num>? sentAdditionalQtyByItemCode,
    bool? additionalOnly,
    String? submissionStatus,
    String? selectedItemCode,
    String? mismatchSearch,
    List<AdditionalRequestRow>? additionalTrackingRows,
    List<Map<String, dynamic>>? maxAdjItems,
    bool? isMaxAdjLoading,
  }) {
    return OrdersState(
      status: status ?? this.status,
      runDate: runDate ?? this.runDate,
      branchName: branchName ?? this.branchName,
      search: search ?? this.search,
      rows: rows ?? this.rows,
      viewRows: viewRows ?? this.viewRows,
      progress: progress ?? this.progress,
      progressMessage: progressMessage ?? this.progressMessage,
      error: error,
      visibleColumns: visibleColumns ?? this.visibleColumns,
      columnOrder: columnOrder ?? this.columnOrder,
      columnWidths: columnWidths ?? this.columnWidths,
      categoryFilter: categoryFilter ?? this.categoryFilter,
      formularyFilter: formularyFilter ?? this.formularyFilter,
      nonWithSales45Only: nonWithSales45Only ?? this.nonWithSales45Only,
      numericFinalOnly: numericFinalOnly ?? this.numericFinalOnly,
      finalEdits: finalEdits ?? this.finalEdits,
      additionalEdits: additionalEdits ?? this.additionalEdits,
      sentAdditionalQtyByItemCode:
          sentAdditionalQtyByItemCode ?? this.sentAdditionalQtyByItemCode,
      additionalOnly: additionalOnly ?? this.additionalOnly,
      submissionStatus: submissionStatus ?? this.submissionStatus,
      selectedItemCode: selectedItemCode ?? this.selectedItemCode,
      sentAdditionalHistoryByItemCode:
          sentAdditionalHistoryByItemCode ??
          this.sentAdditionalHistoryByItemCode,
      additionalTrackingRows:
          additionalTrackingRows ?? this.additionalTrackingRows,
      mismatchItems: mismatchItems ?? this.mismatchItems,
      mismatchSuggestions: mismatchSuggestions ?? this.mismatchSuggestions,
      editingMismatchId: editingMismatchId ?? this.editingMismatchId,
      isRemovingFilters: isRemovingFilters ?? this.isRemovingFilters,
      mismatchSearch: mismatchSearch ?? this.mismatchSearch,
      lastActionSuccess: lastActionSuccess ?? this.lastActionSuccess,
      showMismatchResult: showMismatchResult ?? this.showMismatchResult,
      isMismatchLoading: isMismatchLoading ?? this.isMismatchLoading,
      maxAdjItems: maxAdjItems ?? this.maxAdjItems,
      isMaxAdjLoading: isMaxAdjLoading ?? this.isMaxAdjLoading,
      maxAdjSearch: maxAdjSearch ?? this.maxAdjSearch,
      isExporting: isExporting ?? this.isExporting,
      isOrderDay: isOrderDay ?? this.isOrderDay,
      selectedItemDemand: selectedItemDemand ?? this.selectedItemDemand,
      onlyBranchMaxAdj: onlyBranchMaxAdj ?? this.onlyBranchMaxAdj,
      showCreate: showCreate ?? this.showCreate,
    );
  }

  @override
  List<Object?> get props => [
    status,
    runDate,
    branchName,
    search,
    rows,
    viewRows,
    progress,
    progressMessage,
    error,
    visibleColumns,
    columnOrder,
    columnWidths,
    categoryFilter,
    formularyFilter,
    mismatchItems,
    mismatchSuggestions,
    editingMismatchId,
    nonWithSales45Only,
    numericFinalOnly,
    finalEdits,
    sentAdditionalHistoryByItemCode,
    additionalEdits,
    sentAdditionalQtyByItemCode,
    additionalOnly,
    isRemovingFilters,
    submissionStatus,
    selectedItemCode,
    additionalTrackingRows,
    mismatchSearch,
    lastActionSuccess,
    showMismatchResult,
    isMismatchLoading,
    maxAdjItems,
    isMaxAdjLoading,
    maxAdjSearch,
    isExporting,
    isOrderDay,
    selectedItemDemand,
    onlyBranchMaxAdj,
    showCreate,
  ];
}
