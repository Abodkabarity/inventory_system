part of 'branch_bloc.dart';

enum BranchStatus { initial, loading, loaded, failure }

class BranchState extends Equatable {
  final BranchStatus status;
  final String? branchName;
  final String? error;

  const BranchState({required this.status, this.branchName, this.error});

  factory BranchState.initial() =>
      const BranchState(status: BranchStatus.initial);

  BranchState copyWith({
    BranchStatus? status,
    String? branchName,
    String? error,
  }) {
    return BranchState(
      status: status ?? this.status,
      branchName: branchName ?? this.branchName,
      error: error,
    );
  }

  @override
  List<Object?> get props => [status, branchName, error];
}
