abstract class BranchOrderEvent {}

class LoadBranchOrderBranches extends BranchOrderEvent {}

class BranchOrderBranchChanged extends BranchOrderEvent {
  final String branch;

  BranchOrderBranchChanged(this.branch);
}

class BranchOrderDateChanged extends BranchOrderEvent {
  final DateTime date;

  BranchOrderDateChanged(this.date);
}

class BranchOrderSearchChanged extends BranchOrderEvent {
  final String query;

  BranchOrderSearchChanged(this.query);
}

class LoadBranchOrderRows extends BranchOrderEvent {}
