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

  final int submittedCount;
  final List<MismatchItem> mismatch;
  final List<MismatchItem> filteredMismatch;

  final String mismatchSearch;
  final String mismatchBranch;
  final String mismatchDate;
  final int additionalCount;
  final InventoryPageType currentPage;
  final int additionalPendingCount;

  final int additionalSentToStoreCount;

  final int additionalTodayCount;

  final int additionalMonthCount;

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
      mismatchDate: 'today',
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
    Map<String, int>? additionalMonthBranchCount,
    Map<String, int>? additionalTodayBranchExactCount,
    Map<String, int>? editsCount,
    Map<String, int>? additionalTodayBranchCount,
    InventoryPageType? currentPage,
    List<String>? submittedBranches,
    bool? isLoading,
    List<MismatchItem>? mismatch,
    List<MismatchItem>? filteredMismatch,
    String? mismatchSearch,
    String? mismatchBranch,
    String? mismatchDate,
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

      additionalTodayBranchExactCount:
          additionalTodayBranchExactCount ??
          this.additionalTodayBranchExactCount,
      currentPage: currentPage ?? this.currentPage,
      mismatch: mismatch ?? this.mismatch,
      filteredMismatch: filteredMismatch ?? this.filteredMismatch,
      mismatchSearch: mismatchSearch ?? this.mismatchSearch,
      mismatchBranch: mismatchBranch ?? this.mismatchBranch,
      mismatchDate: mismatchDate ?? this.mismatchDate,
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
  ];
}
