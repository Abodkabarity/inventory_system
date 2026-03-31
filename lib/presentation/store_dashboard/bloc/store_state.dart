import 'package:equatable/equatable.dart';

import '../../../domain/entities/additional_request_group.dart';
import '../../../domain/entities/store_order_item.dart';

class StoreState extends Equatable {
  final List<String> branches;

  final String? selectedBranch;

  final List<StoreOrderItem> items;
  final Map<String, List<Map<String, dynamic>>> processingBatch;

  /// CURRENT ADDITIONAL REQUESTS
  final List<AdditionalRequestGroup> additionalRequests;
  final Map<String, List<Map<String, dynamic>>> printBatch;

  /// HISTORY RESULTS
  final List<AdditionalRequestGroup> additionalHistory;
  final bool isInitialLoading;
  final Map<String, List<Map<String, dynamic>>> filteredProcessing;
  final String searchQuery;
  final int submittedCount;

  final int additionalCount;

  final int additionalPendingCount;

  final int additionalDoneCount;

  final List<String> submittedBranches;

  final DateTime? fromDate;

  final DateTime? toDate;

  final bool isLoading;

  const StoreState({
    required this.branches,
    required this.selectedBranch,
    required this.items,
    required this.additionalRequests,
    required this.additionalHistory,
    required this.submittedCount,
    required this.additionalCount,
    required this.additionalPendingCount,
    required this.additionalDoneCount,
    required this.submittedBranches,
    required this.fromDate,
    required this.toDate,
    required this.isLoading,
    required this.isInitialLoading,
    required this.processingBatch,
    required this.printBatch,
    required this.filteredProcessing,
    required this.searchQuery,
  });

  /// INITIAL STATE
  factory StoreState.initial() {
    return const StoreState(
      branches: [],
      selectedBranch: null,
      items: [],
      additionalRequests: [],
      additionalHistory: [],
      submittedCount: 0,
      additionalCount: 0,
      filteredProcessing: {},
      searchQuery: '',
      additionalPendingCount: 0,
      additionalDoneCount: 0,
      submittedBranches: [],
      fromDate: null,
      toDate: null,
      isLoading: false,
      isInitialLoading: false,
      processingBatch: {},
      printBatch: {},
    );
  }

  /// COPY WITH
  StoreState copyWith({
    List<String>? branches,
    String? selectedBranch,
    List<String>? submittedBranches,
    List<StoreOrderItem>? items,
    bool? isInitialLoading,

    List<AdditionalRequestGroup>? additionalRequests,
    List<AdditionalRequestGroup>? additionalHistory,
    int? submittedCount,
    int? additionalCount,
    int? additionalPendingCount,
    int? additionalDoneCount,
    DateTime? fromDate,
    DateTime? toDate,
    bool? isLoading,
    Map<String, List<Map<String, dynamic>>>? filteredProcessing,
    String? searchQuery,
    Map<String, List<Map<String, dynamic>>>? printBatch,
    Map<String, List<Map<String, dynamic>>>? processingBatch,
  }) {
    return StoreState(
      branches: branches ?? this.branches,
      selectedBranch: selectedBranch ?? this.selectedBranch,
      items: items ?? this.items,
      additionalRequests: additionalRequests ?? this.additionalRequests,
      additionalHistory: additionalHistory ?? this.additionalHistory,
      submittedCount: submittedCount ?? this.submittedCount,
      additionalCount: additionalCount ?? this.additionalCount,
      additionalPendingCount:
          additionalPendingCount ?? this.additionalPendingCount,
      additionalDoneCount: additionalDoneCount ?? this.additionalDoneCount,
      submittedBranches: submittedBranches ?? this.submittedBranches,
      fromDate: fromDate ?? this.fromDate,
      toDate: toDate ?? this.toDate,
      isLoading: isLoading ?? this.isLoading,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      processingBatch: processingBatch ?? this.processingBatch,
      printBatch: printBatch ?? this.printBatch,
      filteredProcessing: filteredProcessing ?? this.filteredProcessing,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  @override
  List<Object?> get props => [
    branches,
    selectedBranch,
    items,
    additionalRequests,
    additionalHistory,
    submittedCount,
    additionalCount,
    additionalPendingCount,
    additionalDoneCount,
    submittedBranches,
    fromDate,
    toDate,
    isLoading,
    isInitialLoading,
    processingBatch,
    printBatch,
  ];
}
