import 'package:equatable/equatable.dart';

class StoreEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadStoreDashboard extends StoreEvent {
  final String runDate;
  final bool silent;

  LoadStoreDashboard(this.runDate, {this.silent = false});

  @override
  List<Object?> get props => [runDate, silent];
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

class LoadAdditionalHistory extends StoreEvent {
  final DateTime from;
  final DateTime to;

  LoadAdditionalHistory({required this.from, required this.to});

  @override
  List<Object?> get props => [from, to];
}

class CollectAndPrintAdditional extends StoreEvent {}

class CollectAdditionalAndPrint extends StoreEvent {}

class CollectAndOpenDialogAdditional extends StoreEvent {}

class ClearProcessingBatch extends StoreEvent {}

class ClearPrintBatch extends StoreEvent {}

class SearchProcessingItems extends StoreEvent {
  final String query;

  SearchProcessingItems({required this.query});
  @override
  List<Object?> get props => [query];
}
