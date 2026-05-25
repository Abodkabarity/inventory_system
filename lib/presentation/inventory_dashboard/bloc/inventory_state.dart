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

  final bool isHistoryLoading;

  final bool isMismatchRealtimeStarted;

  final List<Map<String, dynamic>> formulary;

  final List<Map<String, dynamic>> filteredFormulary;
  final bool hasMorePages;
  final String formularySearch;

  final List<Map<String, dynamic>> formularyHistory;

  final List<MismatchItem> mismatch;

  final List<MismatchItem> filteredMismatch;

  final int mismatchTodayCount;

  final int mismatchMonthCount;

  final List<Map<String, dynamic>> tma;

  final List<Map<String, dynamic>> filteredTma;

  final String tmaSearch;

  final List<Map<String, dynamic>> tmaHistory;

  final String mismatchSearch;

  final bool isImporting;

  final double importProgress;

  final bool isExporting;

  final String? exportMessage;

  final String? importMessage;

  final bool importSuccess;

  final List<Map<String, dynamic>> assortment;

  final List<Map<String, dynamic>> filteredAssortment;

  final String assortmentSearch;

  final List<Map<String, dynamic>> assortmentHistory;

  final List<DailyOrderRow> allOrders;

  final bool isOrdersLoading;

  final List<DailyOrderRow> cachedOrders;

  final bool isBackgroundLoading;

  final bool allDataLoaded;

  final int loadedCount;

  final int currentOrdersPage;

  final bool isSearching;

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

  final List<Map<String, dynamic>> maxAdjustment;

  final List<Map<String, dynamic>> filteredMaxAdjustment;

  final String maxAdjSearch;

  final List<Map<String, dynamic>> maxAdjHistory;

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
    required this.additionalMonthBranchCount,
    required this.additionalTodayBranchExactCount,
    required this.additionalRequests,
    required this.mismatchColumnWidths,
    required this.submittedCount,
    required this.isHistoryLoading,
    required this.isMismatchRealtimeStarted,
    required this.formulary,
    required this.filteredFormulary,
    required this.formularySearch,
    required this.formularyHistory,
    required this.mismatch,
    required this.filteredMismatch,
    required this.mismatchTodayCount,
    required this.mismatchMonthCount,
    required this.tma,
    required this.filteredTma,
    required this.tmaSearch,
    required this.tmaHistory,
    required this.mismatchSearch,
    required this.isImporting,
    required this.importProgress,
    required this.isExporting,
    this.exportMessage,
    this.importMessage,
    required this.importSuccess,
    required this.assortment,
    required this.filteredAssortment,
    required this.assortmentSearch,
    required this.assortmentHistory,
    required this.allOrders,
    required this.isOrdersLoading,
    required this.cachedOrders,
    required this.isBackgroundLoading,
    required this.allDataLoaded,
    required this.loadedCount,
    required this.currentOrdersPage,
    required this.isSearching,
    required this.mismatchBranch,
    required this.mismatchDate,
    required this.additionalCount,
    required this.currentPage,
    required this.additionalPendingCount,
    required this.mismatchDiffSum,
    required this.additionalSentToStoreCount,
    required this.mismatchTotalCount,
    required this.additionalTodayCount,
    required this.visibleColumns,
    required this.columnOrder,
    required this.maxAdjustment,
    required this.filteredMaxAdjustment,
    required this.maxAdjSearch,
    required this.maxAdjHistory,
    required this.additionalMonthCount,
    required this.mismatchTracker,
    required this.allChanges,
    required this.trackerSearch,
    required this.trackerBranch,
    required this.editsCount,
    required this.additionalTodayBranchCount,
    required this.isBulkLoading,
    required this.submittedBranches,
    this.bulkMessage,
    this.bulkSuccess,
    required this.isLoading,
    required this.hasMorePages,
  });

  factory InventoryState.initial() {
    return const InventoryState(
      branches: [],
      selectedBranch: null,
      edits: [],
      additionalMonthBranchCount: {},
      additionalTodayBranchExactCount: {},
      additionalRequests: [],
      mismatchColumnWidths: {
        'branch': 160,
        'code': 150,
        'name': 260,
        'system': 120,

        'actual': 120,
        'diff': 120,
        'history': 140,
      },
      submittedCount: 0,
      isHistoryLoading: false,
      isMismatchRealtimeStarted: false,
      formulary: [],
      filteredFormulary: [],
      formularySearch: '',
      formularyHistory: [],
      mismatch: [],
      filteredMismatch: [],
      mismatchTodayCount: 0,
      mismatchMonthCount: 0,
      hasMorePages: true,
      tma: [],
      filteredTma: [],
      tmaSearch: '',
      tmaHistory: [],
      mismatchSearch: '',
      isImporting: false,
      importProgress: 0,
      isExporting: false,
      exportMessage: null,
      importMessage: "",
      importSuccess: false,
      assortment: [],
      filteredAssortment: [],
      assortmentSearch: '',
      assortmentHistory: [],
      allOrders: [],
      isOrdersLoading: false,
      cachedOrders: [],
      isBackgroundLoading: false,
      allDataLoaded: false,
      loadedCount: 0,
      currentOrdersPage: 0,
      isSearching: false,
      mismatchBranch: 'ALL',
      mismatchDate: 'today',
      additionalCount: 0,
      currentPage: InventoryPageType.dashboard,
      additionalPendingCount: 0,
      mismatchDiffSum: 0,
      additionalSentToStoreCount: 0,
      mismatchTotalCount: 0,
      additionalTodayCount: 0,
      visibleColumns: [],
      columnOrder: [],
      maxAdjustment: [],
      filteredMaxAdjustment: [],
      maxAdjSearch: '',
      maxAdjHistory: [],
      additionalMonthCount: 0,
      mismatchTracker: [],
      allChanges: [],
      trackerSearch: '',
      trackerBranch: 'ALL',
      editsCount: {},
      additionalTodayBranchCount: {},
      isBulkLoading: false,
      submittedBranches: [],
      bulkMessage: null,
      bulkSuccess: null,
      isLoading: false,
    );
  }

  InventoryState copyWith({
    List<String>? branches,
    String? selectedBranch,
    List<InventoryEditItem>? edits,
    Map<String, int>? additionalMonthBranchCount,
    Map<String, int>? additionalTodayBranchExactCount,
    List<AdditionalRequestGroup>? additionalRequests,
    Map<String, double>? mismatchColumnWidths,
    int? submittedCount,
    bool? isHistoryLoading,
    bool? isMismatchRealtimeStarted,
    List<Map<String, dynamic>>? formulary,
    List<Map<String, dynamic>>? filteredFormulary,
    String? formularySearch,
    List<Map<String, dynamic>>? formularyHistory,
    List<MismatchItem>? mismatch,
    List<MismatchItem>? filteredMismatch,
    int? mismatchTodayCount,
    int? mismatchMonthCount,
    List<Map<String, dynamic>>? tma,
    List<Map<String, dynamic>>? filteredTma,
    String? tmaSearch,
    List<Map<String, dynamic>>? tmaHistory,
    String? mismatchSearch,
    bool? isImporting,
    bool? hasMorePages,
    double? importProgress,
    bool? isExporting,
    String? exportMessage,
    String? importMessage,
    bool? importSuccess,
    List<Map<String, dynamic>>? assortment,
    List<Map<String, dynamic>>? filteredAssortment,
    String? assortmentSearch,
    List<Map<String, dynamic>>? assortmentHistory,
    List<DailyOrderRow>? allOrders,
    bool? isOrdersLoading,
    List<DailyOrderRow>? cachedOrders,
    bool? isBackgroundLoading,
    bool? allDataLoaded,
    int? loadedCount,
    int? currentOrdersPage,
    bool? isSearching,
    String? mismatchBranch,
    String? mismatchDate,
    int? additionalCount,
    InventoryPageType? currentPage,
    int? additionalPendingCount,
    num? mismatchDiffSum,
    int? additionalSentToStoreCount,
    int? mismatchTotalCount,
    int? additionalTodayCount,
    List<String>? visibleColumns,
    List<String>? columnOrder,
    List<Map<String, dynamic>>? maxAdjustment,
    List<Map<String, dynamic>>? filteredMaxAdjustment,
    String? maxAdjSearch,
    List<Map<String, dynamic>>? maxAdjHistory,
    int? additionalMonthCount,
    List<Map<String, dynamic>>? mismatchTracker,
    List<Map<String, dynamic>>? allChanges,
    String? trackerSearch,
    String? trackerBranch,
    Map<String, int>? editsCount,
    Map<String, int>? additionalTodayBranchCount,
    bool? isBulkLoading,
    List<String>? submittedBranches,
    String? bulkMessage,
    bool? bulkSuccess,
    bool? isLoading,
  }) {
    return InventoryState(
      branches: branches ?? this.branches,
      selectedBranch: selectedBranch ?? this.selectedBranch,
      edits: edits ?? this.edits,
      additionalMonthBranchCount:
          additionalMonthBranchCount ?? this.additionalMonthBranchCount,
      additionalTodayBranchExactCount:
          additionalTodayBranchExactCount ??
          this.additionalTodayBranchExactCount,
      additionalRequests: additionalRequests ?? this.additionalRequests,
      mismatchColumnWidths: mismatchColumnWidths ?? this.mismatchColumnWidths,
      submittedCount: submittedCount ?? this.submittedCount,
      isHistoryLoading: isHistoryLoading ?? this.isHistoryLoading,
      isMismatchRealtimeStarted:
          isMismatchRealtimeStarted ?? this.isMismatchRealtimeStarted,
      formulary: formulary ?? this.formulary,
      filteredFormulary: filteredFormulary ?? this.filteredFormulary,
      formularySearch: formularySearch ?? this.formularySearch,
      formularyHistory: formularyHistory ?? this.formularyHistory,
      mismatch: mismatch ?? this.mismatch,
      filteredMismatch: filteredMismatch ?? this.filteredMismatch,
      mismatchTodayCount: mismatchTodayCount ?? this.mismatchTodayCount,
      mismatchMonthCount: mismatchMonthCount ?? this.mismatchMonthCount,
      tma: tma ?? this.tma,
      filteredTma: filteredTma ?? this.filteredTma,
      tmaSearch: tmaSearch ?? this.tmaSearch,
      hasMorePages: hasMorePages ?? this.hasMorePages,
      tmaHistory: tmaHistory ?? this.tmaHistory,
      mismatchSearch: mismatchSearch ?? this.mismatchSearch,
      isImporting: isImporting ?? this.isImporting,
      importProgress: importProgress ?? this.importProgress,
      isExporting: isExporting ?? this.isExporting,
      exportMessage: exportMessage ?? this.exportMessage,
      importMessage: importMessage ?? this.importMessage,
      importSuccess: importSuccess ?? this.importSuccess,
      assortment: assortment ?? this.assortment,
      filteredAssortment: filteredAssortment ?? this.filteredAssortment,
      assortmentSearch: assortmentSearch ?? this.assortmentSearch,
      assortmentHistory: assortmentHistory ?? this.assortmentHistory,
      allOrders: allOrders ?? this.allOrders,
      isOrdersLoading: isOrdersLoading ?? this.isOrdersLoading,
      cachedOrders: cachedOrders ?? this.cachedOrders,
      isBackgroundLoading: isBackgroundLoading ?? this.isBackgroundLoading,
      allDataLoaded: allDataLoaded ?? this.allDataLoaded,
      loadedCount: loadedCount ?? this.loadedCount,
      currentOrdersPage: currentOrdersPage ?? this.currentOrdersPage,
      isSearching: isSearching ?? this.isSearching,
      mismatchBranch: mismatchBranch ?? this.mismatchBranch,
      mismatchDate: mismatchDate ?? this.mismatchDate,
      additionalCount: additionalCount ?? this.additionalCount,
      currentPage: currentPage ?? this.currentPage,
      additionalPendingCount:
          additionalPendingCount ?? this.additionalPendingCount,
      mismatchDiffSum: mismatchDiffSum ?? this.mismatchDiffSum,
      additionalSentToStoreCount:
          additionalSentToStoreCount ?? this.additionalSentToStoreCount,
      mismatchTotalCount: mismatchTotalCount ?? this.mismatchTotalCount,
      additionalTodayCount: additionalTodayCount ?? this.additionalTodayCount,
      visibleColumns: visibleColumns ?? this.visibleColumns,
      columnOrder: columnOrder ?? this.columnOrder,
      maxAdjustment: maxAdjustment ?? this.maxAdjustment,
      filteredMaxAdjustment:
          filteredMaxAdjustment ?? this.filteredMaxAdjustment,
      maxAdjSearch: maxAdjSearch ?? this.maxAdjSearch,
      maxAdjHistory: maxAdjHistory ?? this.maxAdjHistory,
      additionalMonthCount: additionalMonthCount ?? this.additionalMonthCount,
      mismatchTracker: mismatchTracker ?? this.mismatchTracker,
      allChanges: allChanges ?? this.allChanges,
      trackerSearch: trackerSearch ?? this.trackerSearch,
      trackerBranch: trackerBranch ?? this.trackerBranch,
      editsCount: editsCount ?? this.editsCount,
      additionalTodayBranchCount:
          additionalTodayBranchCount ?? this.additionalTodayBranchCount,
      isBulkLoading: isBulkLoading ?? this.isBulkLoading,
      submittedBranches: submittedBranches ?? this.submittedBranches,
      bulkMessage: bulkMessage ?? this.bulkMessage,
      bulkSuccess: bulkSuccess ?? this.bulkSuccess,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [
    branches,
    selectedBranch,
    edits,
    additionalMonthBranchCount,
    additionalTodayBranchExactCount,
    additionalRequests,
    mismatchColumnWidths,
    submittedCount,
    isHistoryLoading,
    isMismatchRealtimeStarted,
    formulary,
    filteredFormulary,
    formularySearch,
    formularyHistory,
    mismatch,
    filteredMismatch,
    mismatchTodayCount,
    mismatchMonthCount,
    tma,
    filteredTma,
    tmaSearch,
    tmaHistory,
    mismatchSearch,
    isImporting,
    hasMorePages,
    importProgress,
    isExporting,
    exportMessage,
    importMessage,
    importSuccess,
    assortment,
    filteredAssortment,
    assortmentSearch,
    assortmentHistory,
    allOrders,
    isOrdersLoading,
    cachedOrders,
    isBackgroundLoading,
    allDataLoaded,
    loadedCount,
    currentOrdersPage,
    isSearching,
    mismatchBranch,
    mismatchDate,
    additionalCount,
    currentPage,
    additionalPendingCount,
    mismatchDiffSum,
    additionalSentToStoreCount,
    mismatchTotalCount,
    additionalTodayCount,
    visibleColumns,
    columnOrder,
    maxAdjustment,
    filteredMaxAdjustment,
    maxAdjSearch,
    maxAdjHistory,
    additionalMonthCount,
    mismatchTracker,
    allChanges,
    trackerSearch,
    trackerBranch,
    editsCount,
    additionalTodayBranchCount,
    isBulkLoading,
    submittedBranches,
    bulkMessage,
    bulkSuccess,
    isLoading,
  ];
}
