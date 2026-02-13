enum InventoryOrdersStatus { idle, loading, generating, ready, failure }

class InventoryOrdersState {
  final InventoryOrdersStatus status;
  final String runDate;
  final int pageIndex;
  final int pageSize;
  final List<Map<String, dynamic>> headers;
  final String? jobId;
  final String? error;

  final int progress;
  final String? progressMessage;
  final int totalBranches;
  final int doneBranches;

  const InventoryOrdersState({
    required this.status,
    required this.runDate,
    required this.pageIndex,
    required this.pageSize,
    required this.headers,
    this.jobId,
    this.error,
    required this.progress,
    this.progressMessage,
    required this.totalBranches,
    required this.doneBranches,
  });

  factory InventoryOrdersState.initial() {
    final now = DateTime.now();
    final d =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';

    return InventoryOrdersState(
      status: InventoryOrdersStatus.idle,
      runDate: d,
      pageIndex: 0,
      pageSize: 100,
      headers: const [],
      jobId: null,
      error: null,
      progress: 0,
      progressMessage: null,
      totalBranches: 0,
      doneBranches: 0,
    );
  }

  InventoryOrdersState copyWith({
    InventoryOrdersStatus? status,
    String? runDate,
    int? pageIndex,
    int? pageSize,
    List<Map<String, dynamic>>? headers,
    String? jobId,
    String? error,
    int? progress,
    String? progressMessage,
    int? totalBranches,
    int? doneBranches,
  }) {
    return InventoryOrdersState(
      status: status ?? this.status,
      runDate: runDate ?? this.runDate,
      pageIndex: pageIndex ?? this.pageIndex,
      pageSize: pageSize ?? this.pageSize,
      headers: headers ?? this.headers,
      jobId: jobId ?? this.jobId,
      error: error,
      progress: progress ?? this.progress,
      progressMessage: progressMessage ?? this.progressMessage,
      totalBranches: totalBranches ?? this.totalBranches,
      doneBranches: doneBranches ?? this.doneBranches,
    );
  }
}
