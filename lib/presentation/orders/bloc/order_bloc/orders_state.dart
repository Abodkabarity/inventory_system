// orders_state.dart
import 'package:equatable/equatable.dart';

import '../../../../domain/entities/daily_order_row.dart';

enum OrdersStatus { idle, generating, loading, ready, failure }

class FinalReorderEdit extends Equatable {
  final String itemCode;
  final int oldQty; // auto/suggested numeric only
  final int newQty; // user edited qty numeric only
  final String reason; // required

  const FinalReorderEdit({
    required this.itemCode,
    required this.oldQty,
    required this.newQty,
    required this.reason,
  });

  int get diff => newQty - oldQty;

  FinalReorderEdit copyWith({int? oldQty, int? newQty, String? reason}) {
    return FinalReorderEdit(
      itemCode: itemCode,
      oldQty: oldQty ?? this.oldQty,
      newQty: newQty ?? this.newQty,
      reason: reason ?? this.reason,
    );
  }

  @override
  List<Object?> get props => [itemCode, oldQty, newQty, reason];
}

class OrdersState extends Equatable {
  final OrdersStatus status;

  final String runDate;
  final String branchName;

  final String search;

  /// All branch rows after enrich
  final List<DailyOrderRow> rows;

  /// After filters + search
  final List<DailyOrderRow> viewRows;

  /// UI Progress 0..100
  final int progress;
  final String? progressMessage;

  final String? error;

  final Set<String> visibleOptionalColumns;

  // Filters
  final String categoryFilter;
  final String formularyFilter;
  final bool nonWithSales45Only;

  // Edited final reorder values (by item_code)
  final Map<String, FinalReorderEdit> finalEdits;

  // For opening side panel
  final String? selectedItemCode;

  const OrdersState({
    required this.status,
    required this.runDate,
    required this.branchName,
    required this.search,
    required this.rows,
    required this.viewRows,
    required this.progress,
    required this.visibleOptionalColumns,
    required this.categoryFilter,
    required this.formularyFilter,
    required this.nonWithSales45Only,
    required this.finalEdits,
    this.selectedItemCode,
    this.progressMessage,
    this.error,
  });

  static const Set<String> defaultOptionalVisible = {};

  factory OrdersState.initial({
    required String runDate,
    required String branchName,
  }) {
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
      visibleOptionalColumns: defaultOptionalVisible,
      categoryFilter: 'ALL',
      formularyFilter: 'ALL',
      nonWithSales45Only: false,
      finalEdits: const {},
      selectedItemCode: null,
    );
  }

  bool get isInitial => status == OrdersStatus.idle && rows.isEmpty;

  bool get isBusy =>
      status == OrdersStatus.generating || status == OrdersStatus.loading;

  bool get hasEdits => finalEdits.isNotEmpty;

  int get editsCount => finalEdits.length;

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
    Set<String>? visibleOptionalColumns,
    String? categoryFilter,
    String? formularyFilter,
    bool? nonWithSales45Only,
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
      visibleOptionalColumns:
          visibleOptionalColumns ?? this.visibleOptionalColumns,
      categoryFilter: categoryFilter ?? this.categoryFilter,
      formularyFilter: formularyFilter ?? this.formularyFilter,
      nonWithSales45Only: nonWithSales45Only ?? this.nonWithSales45Only,
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
    visibleOptionalColumns,
    categoryFilter,
    formularyFilter,
    nonWithSales45Only,
    finalEdits,
    selectedItemCode,
  ];
}
