import 'package:equatable/equatable.dart';

import '../../../domain/entities/additional_request_group.dart';
import '../../../domain/entities/daily_order_row.dart';
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
  final List<DailyOrderRow> allOrders;
  final bool isOrdersLoading;
  final String mismatchBranch;
  final String mismatchDate;
  final int additionalCount;
  final InventoryPageType currentPage;
  final int additionalPendingCount;
  final num mismatchDiffSum;
  final int additionalSentToStoreCount;
  final int mismatchTotalCount;
  final int additionalTodayCount;
  final List<String> visibleColumns;
  final List<String> columnOrder;
  final int additionalMonthCount;
  final List<Map<String, dynamic>> mismatchTracker;
  final List<Map<String, dynamic>> allChanges;
  final String trackerSearch;
  final String trackerBranch;
  final Map<String, int> editsCount;

  final Map<String, int> additionalTodayBranchCount;
  final bool isBulkLoading;
  final List<String> submittedBranches;
  final String? bulkMessage;
  final bool? bulkSuccess;
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
    required this.isBulkLoading,
    this.bulkMessage,
    this.bulkSuccess,
    required this.allOrders,
    required this.isOrdersLoading,
    required this.visibleColumns,
    required this.columnOrder,
    required this.allChanges,
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
      isBulkLoading: false,
      mismatch: [],
      bulkMessage: null,
      bulkSuccess: null,
      filteredMismatch: [],
      mismatchSearch: '',
      mismatchBranch: 'ALL',
      mismatchTodayCount: 0,
      mismatchMonthCount: 0,
      mismatchDiffSum: 0,
      mismatchDate: 'today',
      mismatchTotalCount: 0,
      allOrders: [],
      isOrdersLoading: false,
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
      visibleColumns: [],
      columnOrder: [],
      allChanges: [],
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
    bool? isBulkLoading,
    int? additionalMonthCount,
    List<Map<String, dynamic>>? mismatchTracker,
    String? trackerSearch,
    String? trackerBranch,
    String? bulkMessage,
    List<String>? visibleColumns,
    List<String>? columnOrder,
    List<DailyOrderRow>? allOrders,
    bool? isOrdersLoading,
    bool? bulkSuccess,
    List<Map<String, dynamic>>? allChanges,
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
      isBulkLoading: isBulkLoading ?? this.isBulkLoading,
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
      bulkMessage: bulkMessage,
      bulkSuccess: bulkSuccess,
      allOrders: allOrders ?? this.allOrders,
      isOrdersLoading: isOrdersLoading ?? this.isOrdersLoading,
      visibleColumns: visibleColumns ?? this.visibleColumns,
      columnOrder: columnOrder ?? this.columnOrder,
      allChanges: allChanges ?? this.allChanges,
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
    bulkMessage,
    bulkSuccess,
    isBulkLoading,
    allOrders,
    isOrdersLoading,
    columnOrder,
    visibleColumns,
    allChanges,
  ];
}
