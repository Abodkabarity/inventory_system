import 'package:equatable/equatable.dart';

import '../../../domain/entities/additional_request_group.dart';
import '../../../domain/entities/store_order_item.dart';

class StoreState extends Equatable {
  final List<String> branches;
  final String? selectedBranch;

  final List<StoreOrderItem> items;

  final List<AdditionalRequestGroup> additionalRequests;

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
    required this.submittedCount,
    required this.additionalCount,
    required this.additionalPendingCount,
    required this.additionalDoneCount,
    required this.fromDate,
    required this.toDate,
    required this.isLoading,
    required this.submittedBranches,
  });

  factory StoreState.initial() {
    return const StoreState(
      branches: [],
      selectedBranch: null,
      items: [],
      additionalRequests: [],
      submittedCount: 0,
      additionalCount: 0,
      additionalPendingCount: 0,
      additionalDoneCount: 0,
      submittedBranches: [],
      fromDate: null,
      toDate: null,
      isLoading: false,
    );
  }

  StoreState copyWith({
    List<String>? branches,
    String? selectedBranch,
    List<String>? submittedBranches,
    List<StoreOrderItem>? items,
    List<AdditionalRequestGroup>? additionalRequests,
    int? submittedCount,
    int? additionalCount,
    int? additionalPendingCount,
    int? additionalDoneCount,
    DateTime? fromDate,
    DateTime? toDate,
    bool? isLoading,
  }) {
    return StoreState(
      branches: branches ?? this.branches,
      selectedBranch: selectedBranch ?? this.selectedBranch,
      items: items ?? this.items,
      additionalRequests: additionalRequests ?? this.additionalRequests,
      submittedCount: submittedCount ?? this.submittedCount,
      additionalCount: additionalCount ?? this.additionalCount,
      additionalPendingCount:
          additionalPendingCount ?? this.additionalPendingCount,
      additionalDoneCount: additionalDoneCount ?? this.additionalDoneCount,
      fromDate: fromDate ?? this.fromDate,
      toDate: toDate ?? this.toDate,
      submittedBranches: submittedBranches ?? this.submittedBranches,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  List<Object?> get props => [
    branches,
    selectedBranch,
    items,
    additionalRequests,
    submittedCount,
    additionalCount,
    additionalPendingCount,
    additionalDoneCount,
    fromDate,
    toDate,
    submittedBranches,
    isLoading,
  ];
}
