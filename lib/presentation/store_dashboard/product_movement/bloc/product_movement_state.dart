import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import '../../../../domain/entities/product_movement.dart';

class ProductMovementState extends Equatable {
  final bool loadingBranches;
  final bool loadingRows;
  final List<String> branches;
  final String? selectedBranch;
  final DateTimeRange dateRange;
  final String movementType;
  final String query;
  final String selectedItemCode;
  final String selectedItemName;
  final List<Map<String, dynamic>> suggestions;
  final List<ProductMovement> rows;
  final String error;
  final bool searched;

  const ProductMovementState({
    required this.loadingBranches,
    required this.loadingRows,
    required this.branches,
    required this.selectedBranch,
    required this.dateRange,
    required this.movementType,
    required this.query,
    required this.selectedItemCode,
    required this.selectedItemName,
    required this.suggestions,
    required this.rows,
    required this.error,
    required this.searched,
  });

  factory ProductMovementState.initial() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    return ProductMovementState(
      loadingBranches: false,
      loadingRows: false,
      branches: const [],
      selectedBranch: null,
      dateRange: DateTimeRange(start: start, end: end),
      movementType: 'all',
      query: '',
      selectedItemCode: '',
      selectedItemName: '',
      suggestions: const [],
      rows: const [],
      error: '',
      searched: false,
    );
  }

  ProductMovementState copyWith({
    bool? loadingBranches,
    bool? loadingRows,
    List<String>? branches,
    String? selectedBranch,
    bool clearSelectedBranch = false,
    DateTimeRange? dateRange,
    String? movementType,
    String? query,
    String? selectedItemCode,
    String? selectedItemName,
    List<Map<String, dynamic>>? suggestions,
    List<ProductMovement>? rows,
    String? error,
    bool? searched,
  }) {
    return ProductMovementState(
      loadingBranches: loadingBranches ?? this.loadingBranches,
      loadingRows: loadingRows ?? this.loadingRows,
      branches: branches ?? this.branches,
      selectedBranch: clearSelectedBranch
          ? null
          : (selectedBranch ?? this.selectedBranch),
      dateRange: dateRange ?? this.dateRange,
      movementType: movementType ?? this.movementType,
      query: query ?? this.query,
      selectedItemCode: selectedItemCode ?? this.selectedItemCode,
      selectedItemName: selectedItemName ?? this.selectedItemName,
      suggestions: suggestions ?? this.suggestions,
      rows: rows ?? this.rows,
      error: error ?? this.error,
      searched: searched ?? this.searched,
    );
  }

  int get dailyCount =>
      rows.where((e) => e.movementType == 'daily_order').length;

  int get additionalCount =>
      rows.where((e) => e.movementType == 'additional_request').length;

  num get totalQty {
    num total = 0;
    for (final row in rows) {
      total += row.qty;
    }
    return total;
  }

  @override
  List<Object?> get props => [
    loadingBranches,
    loadingRows,
    branches,
    selectedBranch,
    dateRange,
    movementType,
    query,
    selectedItemCode,
    selectedItemName,
    suggestions,
    rows,
    error,
    searched,
  ];
}
