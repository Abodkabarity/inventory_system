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

class LoadMaxAdjustment extends InventoryEvent {
  final int page;
  final String query;
  final bool silent;

  LoadMaxAdjustment({this.page = 0, this.query = '', this.silent = false});

  @override
  List<Object?> get props => [page, query, silent];
}

class SearchMaxAdjustment extends InventoryEvent {
  final String query;
  SearchMaxAdjustment(this.query);
}

class LoadMaxAdjustmentHistory extends InventoryEvent {
  final String itemCode;
  final String branch;

  LoadMaxAdjustmentHistory(this.itemCode, this.branch);
}

class ExportMaxAdjCurrent extends InventoryEvent {}

class ExportMaxAdjWithHistory extends InventoryEvent {}

class ImportMaxAdjExcel extends InventoryEvent {
  final bool forceApply;

  ImportMaxAdjExcel({required this.forceApply});
}

class ExportMaxAdjTemplate extends InventoryEvent {}

class ResetImportState extends InventoryEvent {}

class StartMaxAdjRealtime extends InventoryEvent {}

class LoadAssortment extends InventoryEvent {
  final bool silent;
  LoadAssortment({this.silent = false});
}

class SearchAssortment extends InventoryEvent {
  final String query;
  SearchAssortment(this.query);
}

class LoadAssortmentHistory extends InventoryEvent {
  final String itemCode;
  final String branch;

  LoadAssortmentHistory(this.itemCode, this.branch);
}

class ExportAssortmentCurrent extends InventoryEvent {}

class ExportAssortmentWithHistory extends InventoryEvent {}

class ImportAssortmentExcel extends InventoryEvent {
  final bool forceApply;

  ImportAssortmentExcel({required this.forceApply});
}

class ExportAssortmentTemplate extends InventoryEvent {}

class StartAssortmentRealtime extends InventoryEvent {}

class LoadTma extends InventoryEvent {
  final bool silent;
  LoadTma({this.silent = false});
}

class SearchTma extends InventoryEvent {
  final String query;
  SearchTma(this.query);
}

class LoadTmaHistory extends InventoryEvent {
  final String itemCode;
  final String branch;

  LoadTmaHistory(this.itemCode, this.branch);
}

class StartTmaRealtime extends InventoryEvent {}

class ExportTmaCurrent extends InventoryEvent {}

class ExportTmaWithHistory extends InventoryEvent {}

class ExportTmaTemplate extends InventoryEvent {}

class ImportTmaExcel extends InventoryEvent {
  final bool forceApply;
  ImportTmaExcel({required this.forceApply});
}

class LoadFormularyHistory extends InventoryEvent {
  final String itemCode;
  final String branch;

  LoadFormularyHistory(this.itemCode, this.branch);
}

class ExportFormularyCurrent extends InventoryEvent {}

class ExportFormularyWithHistory extends InventoryEvent {}

class ExportFormularyTemplate extends InventoryEvent {}

class StartFormularyRealtime extends InventoryEvent {}

class ImportFormularyExcel extends InventoryEvent {
  final bool forceApply;
  ImportFormularyExcel({required this.forceApply});
}

class LoadMismatchStats extends InventoryEvent {
  final String branch;
  LoadMismatchStats(this.branch);
}

class ExportMismatchCurrent extends InventoryEvent {}

class ExportMismatchWithHistory extends InventoryEvent {}

class UpdateExportProgress extends InventoryEvent {
  final double progress;
  UpdateExportProgress(this.progress);
}

class ExportInventoryOrders extends InventoryEvent {
  final String runDate;
  final List<String> visibleColumns;

  ExportInventoryOrders({required this.runDate, required this.visibleColumns});
}

class UpdateExportDailyProgress extends InventoryEvent {
  final double progress;
  final String message;

  UpdateExportDailyProgress({required this.progress, required this.message});

  @override
  List<Object> get props => [progress, message];
}

class LoadMoreInventoryOrders extends InventoryEvent {}

class SearchInventoryOrders extends InventoryEvent {
  final String query;

  SearchInventoryOrders(this.query);
}

class LoadOrdersPage extends InventoryEvent {
  final String runDate;

  final int page;

  LoadOrdersPage({required this.runDate, required this.page});

  @override
  List<Object?> get props => [runDate, page];
}

class LoadAdditionalOrderAnalysis extends InventoryEvent {
  final DateTime from;
  final DateTime to;

  LoadAdditionalOrderAnalysis({required this.from, required this.to});

  @override
  List<Object?> get props => [from, to];
}

class LoadRequestEffectiveness extends InventoryEvent {
  final DateTime from;
  final DateTime to;
  final String? branch;

  LoadRequestEffectiveness({required this.from, required this.to, this.branch});

  @override
  List<Object?> get props => [from, to, branch];
}

class LoadFormulary extends InventoryEvent {
  final bool silent;
  final int page;
  final String query;

  LoadFormulary({this.silent = false, this.page = 0, this.query = ''});

  @override
  List<Object?> get props => [silent, page, query];
}

class SearchFormulary extends InventoryEvent {
  final String query;

  SearchFormulary(this.query);

  @override
  List<Object?> get props => [query];
}
