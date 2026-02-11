part of 'branch_bloc.dart';

sealed class BranchEvent extends Equatable {
  const BranchEvent();

  @override
  List<Object?> get props => [];
}

class LoadMyBranch extends BranchEvent {
  const LoadMyBranch();
}
