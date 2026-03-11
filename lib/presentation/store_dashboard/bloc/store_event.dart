import 'package:equatable/equatable.dart';

class StoreEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadStoreDashboard extends StoreEvent {
  final String runDate;

  LoadStoreDashboard(this.runDate);

  @override
  List<Object?> get props => [runDate];
}

class SelectBranch extends StoreEvent {
  final String branch;

  SelectBranch(this.branch);

  @override
  List<Object?> get props => [branch];
}

class ApproveAdditionalRequest extends StoreEvent {
  final String requestId;
  final num qty;
  final String note;

  ApproveAdditionalRequest({
    required this.requestId,
    required this.qty,
    required this.note,
  });

  @override
  List<Object?> get props => [requestId, qty, note];
}
