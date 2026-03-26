import 'package:equatable/equatable.dart';

class InventoryEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadInventoryDashboard extends InventoryEvent {
  final String runDate;
  final bool silent;

  LoadInventoryDashboard(this.runDate, {this.silent = false});

  @override
  List<Object?> get props => [runDate, silent];
}

class SelectBranch extends InventoryEvent {
  final String branch;

  SelectBranch(this.branch);

  @override
  List<Object?> get props => [branch];
}

class ApproveInventoryRequest extends InventoryEvent {
  final String requestId;
  final num qty;

  ApproveInventoryRequest({required this.requestId, required this.qty});

  @override
  List<Object?> get props => [requestId, qty];
}

class LoadBranchAnalytics extends InventoryEvent {
  final String branch;

  LoadBranchAnalytics(this.branch);

  @override
  List<Object?> get props => [branch];
}

class LoadBranchAdditionalStats extends InventoryEvent {
  final String branch;

  LoadBranchAdditionalStats(this.branch);

  @override
  List<Object?> get props => [branch];
}
