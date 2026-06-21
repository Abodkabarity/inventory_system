import 'package:equatable/equatable.dart';

class BranchOrderState extends Equatable {
  final bool loadingBranches;
  final bool loadingRows;
  final List<String> branches;
  final String? selectedBranch;
  final DateTime selectedDate;
  final String query;
  final List<Map<String, dynamic>> rows;
  final String error;

  const BranchOrderState({
    required this.loadingBranches,
    required this.loadingRows,
    required this.branches,
    required this.selectedBranch,
    required this.selectedDate,
    required this.query,
    required this.rows,
    required this.error,
  });

  factory BranchOrderState.initial() {
    final now = DateTime.now();
    return BranchOrderState(
      loadingBranches: false,
      loadingRows: false,
      branches: const [],
      selectedBranch: null,
      selectedDate: DateTime(now.year, now.month, now.day),
      query: '',
      rows: const [],
      error: '',
    );
  }

  BranchOrderState copyWith({
    bool? loadingBranches,
    bool? loadingRows,
    List<String>? branches,
    String? selectedBranch,
    bool clearSelectedBranch = false,
    DateTime? selectedDate,
    String? query,
    List<Map<String, dynamic>>? rows,
    String? error,
  }) {
    return BranchOrderState(
      loadingBranches: loadingBranches ?? this.loadingBranches,
      loadingRows: loadingRows ?? this.loadingRows,
      branches: branches ?? this.branches,
      selectedBranch: clearSelectedBranch
          ? null
          : (selectedBranch ?? this.selectedBranch),
      selectedDate: selectedDate ?? this.selectedDate,
      query: query ?? this.query,
      rows: rows ?? this.rows,
      error: error ?? this.error,
    );
  }

  int get itemCount => rows.length;

  num get totalQty {
    num total = 0;
    for (final row in rows) {
      total += num.tryParse((row['qty'] ?? '0').toString()) ?? 0;
    }
    return total;
  }

  @override
  List<Object?> get props => [
    loadingBranches,
    loadingRows,
    branches,
    selectedBranch,
    selectedDate,
    query,
    rows,
    error,
  ];
}
