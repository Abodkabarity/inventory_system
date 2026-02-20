import 'package:equatable/equatable.dart';

enum BranchEntryStatus { initial, loading, success, failure }

class BranchEntryState extends Equatable {
  final BranchEntryStatus status;
  final String? branchName;
  final String? error;

  const BranchEntryState({required this.status, this.branchName, this.error});

  factory BranchEntryState.initial() =>
      const BranchEntryState(status: BranchEntryStatus.initial);

  BranchEntryState copyWith({
    BranchEntryStatus? status,
    String? branchName,
    String? error,
  }) {
    return BranchEntryState(
      status: status ?? this.status,
      branchName: branchName ?? this.branchName,
      error: error,
    );
  }

  @override
  List<Object?> get props => [status, branchName, error];
}
