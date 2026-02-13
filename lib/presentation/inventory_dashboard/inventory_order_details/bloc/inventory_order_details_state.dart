enum InventoryOrderDetailsStatus { idle, loading, ready, failure }

class InventoryOrderDetailsState {
  final InventoryOrderDetailsStatus status;
  final String runDate;
  final int pageIndex;
  final int pageSize;
  final List<Map<String, dynamic>> rows;
  final String? error;

  const InventoryOrderDetailsState({
    required this.status,
    required this.runDate,
    required this.pageIndex,
    required this.pageSize,
    required this.rows,
    this.error,
  });

  factory InventoryOrderDetailsState.initial() {
    final now = DateTime.now();
    final d =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    return InventoryOrderDetailsState(
      status: InventoryOrderDetailsStatus.idle,
      runDate: d,
      pageIndex: 0,
      pageSize: 500,
      rows: const [],
      error: null,
    );
  }

  InventoryOrderDetailsState copyWith({
    InventoryOrderDetailsStatus? status,
    String? runDate,
    int? pageIndex,
    int? pageSize,
    List<Map<String, dynamic>>? rows,
    String? error,
  }) {
    return InventoryOrderDetailsState(
      status: status ?? this.status,
      runDate: runDate ?? this.runDate,
      pageIndex: pageIndex ?? this.pageIndex,
      pageSize: pageSize ?? this.pageSize,
      rows: rows ?? this.rows,
      error: error,
    );
  }
}
