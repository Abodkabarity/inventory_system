import 'package:equatable/equatable.dart';

import '../../../domain/entities/inventory_page.dart';

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

class ChangeInventoryPage extends InventoryEvent {
  final InventoryPageType page;

  ChangeInventoryPage(this.page);
}

class LoadMismatch extends InventoryEvent {}

class SearchMismatch extends InventoryEvent {
  final String query;
  SearchMismatch(this.query);
}

class FilterMismatchBranch extends InventoryEvent {
  final String branch;
  FilterMismatchBranch(this.branch);
}

class FilterMismatchDate extends InventoryEvent {
  final String range;
  FilterMismatchDate(this.range);
}

class UpdateMismatchColumnWidth extends InventoryEvent {
  final String column;
  final double width;

  UpdateMismatchColumnWidth(this.column, this.width);
}

class LoadMismatchTracker extends InventoryEvent {
  final DateTime from;
  final DateTime to;
  final String? branch;

  LoadMismatchTracker({required this.from, required this.to, this.branch});
}

class StartMismatchRealtime extends InventoryEvent {}

class ApproveAllInventoryRequests extends InventoryEvent {
  final List<Map<String, dynamic>> items;

  ApproveAllInventoryRequests(this.items);
}

class StoreApproveRequests extends InventoryEvent {
  final List<Map<String, dynamic>> items;

  StoreApproveRequests(this.items);
}

class StartAdditionalRealtime extends InventoryEvent {
  StartAdditionalRealtime();
}

class LoadInventoryOrders extends InventoryEvent {
  final String runDate;

  LoadInventoryOrders(this.runDate);
}

class InventorySetColumnVisible extends InventoryEvent {
  final String columnKey;
  final bool visible;

  InventorySetColumnVisible({required this.columnKey, required this.visible});
}

class InventoryReorderColumns extends InventoryEvent {
  final int oldIndex;
  final int newIndex;

  InventoryReorderColumns({required this.oldIndex, required this.newIndex});
}

class InventoryResetColumns extends InventoryEvent {
  InventoryResetColumns();
}

class LoadBranchAllChanges extends InventoryEvent {
  final String branch;
  LoadBranchAllChanges(this.branch);
}
