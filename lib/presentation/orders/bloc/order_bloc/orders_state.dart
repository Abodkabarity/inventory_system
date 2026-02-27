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

class OrdersState extends Equatable {
  final OrdersStatus status;

  final String runDate;
  final String branchName;

  final String search;

  final List<DailyOrderRow> rows;
  final List<DailyOrderRow> viewRows;

  final int progress;
  final String? progressMessage;

  final String? error;

  final Set<String> visibleColumns;
  final List<String> columnOrder;

  final Map<String, double> columnWidths;

  final String categoryFilter;
  final String formularyFilter;
  final bool nonWithSales45Only;

  final bool numericFinalOnly;

  final Map<String, FinalReorderEdit> finalEdits;

  final String? selectedItemCode;

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
    this.selectedItemCode,
    this.progressMessage,
    this.error,
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

  static const double defaultMinWidth = 120;

  static double defaultWidthFor(String key) {
    if (key == 'row_no') return 70;

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
    final allKeys = <String>['row_no', ...defaultColumnOrder];

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
      visibleColumns: defaultVisibleInTable.toSet(),
      columnOrder: defaultColumnOrder,
      columnWidths: defaultColumnWidths(allKeys),
      categoryFilter: 'ALL',
      formularyFilter: 'ALL',
      nonWithSales45Only: false,
      numericFinalOnly: true,
      finalEdits: const {},
      selectedItemCode: null,
    );
  }

  bool get isInitial => status == OrdersStatus.idle && rows.isEmpty;

  bool get isBusy =>
      status == OrdersStatus.generating || status == OrdersStatus.loading;

  bool get hasEdits => finalEdits.isNotEmpty;

  int get editsCount => finalEdits.length;

  List<String> get orderedVisibleColumns =>
      columnOrder.where(visibleColumns.contains).toList();

  OrdersState copyWith({
    OrdersStatus? status,
    String? runDate,
    String? branchName,
    String? search,
    List<DailyOrderRow>? rows,
    List<DailyOrderRow>? viewRows,
    int? progress,
    String? progressMessage,
    String? error,
    Set<String>? visibleColumns,
    List<String>? columnOrder,
    Map<String, double>? columnWidths,
    String? categoryFilter,
    String? formularyFilter,
    bool? nonWithSales45Only,
    bool? numericFinalOnly,
    Map<String, FinalReorderEdit>? finalEdits,
    String? selectedItemCode,
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
      selectedItemCode: selectedItemCode ?? this.selectedItemCode,
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
    nonWithSales45Only,
    numericFinalOnly,
    finalEdits,
    selectedItemCode,
  ];
}
