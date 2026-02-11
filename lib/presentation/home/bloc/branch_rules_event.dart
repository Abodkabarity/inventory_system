import 'package:equatable/equatable.dart';

sealed class BranchRulesEvent extends Equatable {
  const BranchRulesEvent();

  @override
  List<Object?> get props => [];
}

class LoadBranchRules extends BranchRulesEvent {
  final String branchName;
  const LoadBranchRules(this.branchName);

  @override
  List<Object?> get props => [branchName];
}
