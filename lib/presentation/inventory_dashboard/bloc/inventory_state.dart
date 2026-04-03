import 'package:equatable/equatable.dart';

import '../../../domain/entities/additional_request_group.dart';
import '../../../domain/entities/inventory_edit_item.dart';
import '../../../domain/entities/inventory_page.dart';
import '../../../domain/entities/mismatch_item.dart';

class InventoryState extends Equatable {
  final List<String> branches;

  final String? selectedBranch;

  final List<InventoryEditItem> edits;
  final Map<String, int> additionalMonthBranchCount;
  final Map<String, int> additionalTodayBranchExactCount;
  final List<AdditionalRequestGroup> additionalRequests;
  final Map<String, double> mismatchColumnWidths;
  final int submittedCount;
  final List<MismatchItem> mismatch;
  final List<MismatchItem> filteredMismatch;
  final int mismatchTodayCount;
  final int mismatchMonthCount;
  final String mismatchSearch;
  final String mismatchBranch;
  final String mismatchDate;
  final int additionalCount;
  final InventoryPageType currentPage;
  final int additionalPendingCount;
  final num mismatchDiffSum;
  final int additionalSentToStoreCount;
  final int mismatchTotalCount;
  final int additionalTodayCount;

  final int additionalMonthCount;
  final List<Map<String, dynamic>> mismatchTracker;
  final String trackerSearch;
  final String trackerBranch;
  final Map<String, int> editsCount;

  final Map<String, int> additionalTodayBranchCount;

  final List<String> submittedBranches;

  final bool isLoading;

  const InventoryState({
    required this.branches,
    required this.selectedBranch,
    required this.edits,
    required this.additionalRequests,
    required this.submittedCount,
    required this.additionalCount,
    required this.additionalPendingCount,
    required this.additionalSentToStoreCount,
    required this.additionalTodayCount,
    required this.additionalMonthCount,
    required this.submittedBranches,
    required this.isLoading,
    required this.editsCount,
    required this.additionalTodayBranchCount,
    required this.additionalMonthBranchCount,
    required this.additionalTodayBranchExactCount,
    required this.currentPage,
    required this.mismatch,
    required this.filteredMismatch,
    required this.mismatchSearch,
    required this.mismatchBranch,
    required this.mismatchDate,
    required this.mismatchColumnWidths,
    required this.mismatchTodayCount,
    required this.mismatchMonthCount,
    required this.mismatchTotalCount,
    required this.mismatchDiffSum,
    required this.mismatchTracker,
    required this.trackerSearch,
    required this.trackerBranch,
  });

  factory InventoryState.initial() {
    return const InventoryState(
      branches: [],
      selectedBranch: null,
      edits: [],
      editsCount: {},
      additionalMonthBranchCount: {},
      additionalTodayBranchExactCount: {},
      additionalTodayBranchCount: {},
      additionalRequests: [],
      submittedCount: 0,
      additionalCount: 0,
      additionalPendingCount: 0,
      additionalSentToStoreCount: 0,
      additionalTodayCount: 0,
      additionalMonthCount: 0,
      currentPage: InventoryPageType.dashboard,
      submittedBranches: [],
      isLoading: false,
      mismatch: [],
      filteredMismatch: [],
      mismatchSearch: '',
      mismatchBranch: 'ALL',
      mismatchTodayCount: 0,
      mismatchMonthCount: 0,
      mismatchDiffSum: 0,
      mismatchDate: 'today',
      mismatchTotalCount: 0,
      mismatchTracker: [],
      trackerSearch: '',
      trackerBranch: 'ALL',
      mismatchColumnWidths: {
        'branch': 160,
        'code': 150,
        'name': 260,
        'system': 120,
        'actual': 120,
        'diff': 120,
        'history': 140,
      },
    );
  }

  InventoryState copyWith({
    List<String>? branches,
    String? selectedBranch,
    List<InventoryEditItem>? edits,
    List<AdditionalRequestGroup>? additionalRequests,
    int? submittedCount,
    int? additionalCount,
    int? additionalPendingCount,
    int? additionalSentToStoreCount,
    int? additionalTodayCount,
    int? additionalMonthCount,
    List<Map<String, dynamic>>? mismatchTracker,
    String? trackerSearch,
    String? trackerBranch,
    Map<String, int>? additionalMonthBranchCount,
    Map<String, int>? additionalTodayBranchExactCount,
    Map<String, int>? editsCount,
    Map<String, int>? additionalTodayBranchCount,
    InventoryPageType? currentPage,
    List<String>? submittedBranches,
    bool? isLoading,
    num? mismatchDiffSum,
    List<MismatchItem>? mismatch,
    List<MismatchItem>? filteredMismatch,
    String? mismatchSearch,
    int? mismatchTotalCount,
    String? mismatchBranch,
    String? mismatchDate,
    int? mismatchTodayCount,
    int? mismatchMonthCount,
    Map<String, double>? mismatchColumnWidths,
  }) {
    return InventoryState(
      branches: branches ?? this.branches,
      selectedBranch: selectedBranch ?? this.selectedBranch,
      edits: edits ?? this.edits,
      additionalRequests: additionalRequests ?? this.additionalRequests,
      submittedCount: submittedCount ?? this.submittedCount,
      additionalCount: additionalCount ?? this.additionalCount,
      additionalPendingCount:
          additionalPendingCount ?? this.additionalPendingCount,
      additionalSentToStoreCount:
          additionalSentToStoreCount ?? this.additionalSentToStoreCount,
      additionalTodayCount: additionalTodayCount ?? this.additionalTodayCount,
      additionalMonthCount: additionalMonthCount ?? this.additionalMonthCount,
      submittedBranches: submittedBranches ?? this.submittedBranches,
      editsCount: editsCount ?? this.editsCount,
      additionalTodayBranchCount:
          additionalTodayBranchCount ?? this.additionalTodayBranchCount,
      isLoading: isLoading ?? this.isLoading,
      additionalMonthBranchCount:
          additionalMonthBranchCount ?? this.additionalMonthBranchCount,
      mismatchDiffSum: mismatchDiffSum ?? this.mismatchDiffSum,
      additionalTodayBranchExactCount:
          additionalTodayBranchExactCount ??
          this.additionalTodayBranchExactCount,
      currentPage: currentPage ?? this.currentPage,
      mismatch: mismatch ?? this.mismatch,
      filteredMismatch: filteredMismatch ?? this.filteredMismatch,
      mismatchSearch: mismatchSearch ?? this.mismatchSearch,
      mismatchBranch: mismatchBranch ?? this.mismatchBranch,
      mismatchDate: mismatchDate ?? this.mismatchDate,
      mismatchColumnWidths: mismatchColumnWidths ?? this.mismatchColumnWidths,
      mismatchTodayCount: mismatchTodayCount ?? this.mismatchTodayCount,

      mismatchMonthCount: mismatchMonthCount ?? this.mismatchMonthCount,
      mismatchTotalCount: mismatchTotalCount ?? this.mismatchTotalCount,
      mismatchTracker: mismatchTracker ?? this.mismatchTracker,
      trackerSearch: trackerSearch ?? this.trackerSearch,
      trackerBranch: trackerBranch ?? this.trackerBranch,
    );
  }

  @override
  List<Object?> get props => [
    branches,
    selectedBranch,
    edits,
    additionalRequests,
    submittedCount,
    additionalCount,
    additionalPendingCount,
    additionalSentToStoreCount,
    additionalTodayCount,
    additionalMonthCount,
    submittedBranches,
    editsCount,
    additionalTodayBranchCount,
    isLoading,
    additionalMonthBranchCount,
    currentPage,
    additionalTodayBranchExactCount,
    filteredMismatch,
    mismatchSearch,
    mismatchBranch,
    mismatchDate,
    mismatchColumnWidths,
    mismatchTotalCount,
    mismatchDiffSum,
    trackerBranch,
    trackerSearch,
    mismatchTracker,
  ];
}
