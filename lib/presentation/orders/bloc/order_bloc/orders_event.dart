import 'package:equatable/equatable.dart';

abstract class OrdersEvent extends Equatable {
  const OrdersEvent();

  @override
  List<Object?> get props => [];
}

class OrdersPressedGenerate extends OrdersEvent {
  const OrdersPressedGenerate();
}

class OrdersLoadAll extends OrdersEvent {
  const OrdersLoadAll();
}

class OrdersSearchChanged extends OrdersEvent {
  final String search;
  const OrdersSearchChanged(this.search);

  @override
  List<Object?> get props => [search];
}

// Columns
class OrdersSetColumnVisible extends OrdersEvent {
  final String columnKey;
  final bool visible;
  const OrdersSetColumnVisible({
    required this.columnKey,
    required this.visible,
  });

  @override
  List<Object?> get props => [columnKey, visible];
}

class OrdersReorderColumns extends OrdersEvent {
  final int oldIndex;
  final int newIndex;
  const OrdersReorderColumns({required this.oldIndex, required this.newIndex});

  @override
  List<Object?> get props => [oldIndex, newIndex];
}

class OrdersResetColumnsToDefault extends OrdersEvent {
  const OrdersResetColumnsToDefault();
}

// Filters
class OrdersCategoryChanged extends OrdersEvent {
  final String category;
  const OrdersCategoryChanged(this.category);

  @override
  List<Object?> get props => [category];
}

class OrdersFormularyChanged extends OrdersEvent {
  final String formulary;
  const OrdersFormularyChanged(this.formulary);

  @override
  List<Object?> get props => [formulary];
}

class OrdersNonWithSales45Toggled extends OrdersEvent {
  final bool value;
  const OrdersNonWithSales45Toggled(this.value);

  @override
  List<Object?> get props => [value];
}

class OrdersNumericFinalOnlyToggled extends OrdersEvent {
  final bool value;
  const OrdersNumericFinalOnlyToggled(this.value);

  @override
  List<Object?> get props => [value];
}

class OrdersAdditionalOnlyToggled extends OrdersEvent {
  final bool value;
  const OrdersAdditionalOnlyToggled(this.value);

  @override
  List<Object?> get props => [value];
}

class OrdersClearAllFilters extends OrdersEvent {
  const OrdersClearAllFilters();
}

// Side panel selection
class OrdersSelectItemForEdit extends OrdersEvent {
  final String itemCode;
  const OrdersSelectItemForEdit(this.itemCode);

  @override
  List<Object?> get props => [itemCode];
}

class OrdersClearSelection extends OrdersEvent {
  const OrdersClearSelection();
}

// Final edits
class OrdersApplyFinalEdit extends OrdersEvent {
  final String itemCode;
  final int oldQty;
  final int newQty;
  final String reason;

  const OrdersApplyFinalEdit({
    required this.itemCode,
    required this.oldQty,
    required this.newQty,
    required this.reason,
  });

  @override
  List<Object?> get props => [itemCode, oldQty, newQty, reason];
}

class OrdersResetFinalEdit extends OrdersEvent {
  final String itemCode;
  const OrdersResetFinalEdit(this.itemCode);

  @override
  List<Object?> get props => [itemCode];
}

class OrdersClearAllEdits extends OrdersEvent {
  const OrdersClearAllEdits();
}

class OrdersColumnResized extends OrdersEvent {
  final String columnKey;
  final double width;

  const OrdersColumnResized({required this.columnKey, required this.width});

  @override
  List<Object?> get props => [columnKey, width];
}

// NEW: additional request edits
class OrdersApplyAdditionalRequest extends OrdersEvent {
  final String itemCode;
  final String itemName;
  final num requestQty;
  final String reason;
  final bool isUrgent;
  const OrdersApplyAdditionalRequest({
    required this.itemCode,
    required this.itemName,
    required this.requestQty,
    required this.reason,
    required this.isUrgent,
  });

  @override
  List<Object?> get props => [itemCode, itemName, requestQty, reason];
}

class OrdersRemoveAdditionalRequest extends OrdersEvent {
  final String itemCode;
  const OrdersRemoveAdditionalRequest(this.itemCode);

  @override
  List<Object?> get props => [itemCode];
}

class OrdersSendAdditionalRequestsPressed extends OrdersEvent {
  final String zone;
  const OrdersSendAdditionalRequestsPressed({required this.zone});

  @override
  List<Object?> get props => [zone];
}

class OrdersSubmitOrderPressed extends OrdersEvent {
  final String zone;
  const OrdersSubmitOrderPressed({required this.zone});

  @override
  List<Object?> get props => [zone];
}

// NEW: Tracking additional requests (branch dialog)
class OrdersLoadAdditionalTracking extends OrdersEvent {
  const OrdersLoadAdditionalTracking();
}
// ==========================
// MISMATCH
// ==========================

class OrdersLoadMismatch extends OrdersEvent {
  const OrdersLoadMismatch();
}

class OrdersAddMismatch extends OrdersEvent {
  final Map<String, dynamic> data;
  const OrdersAddMismatch(this.data);

  @override
  List<Object?> get props => [data];
}

class OrdersUpdateMismatch extends OrdersEvent {
  final String id;
  final num system;
  final num actual;
  final Map old;

  const OrdersUpdateMismatch({
    required this.id,
    required this.system,
    required this.actual,
    required this.old,
  });

  @override
  List<Object?> get props => [id, system, actual, old];
}

class OrdersDeleteMismatch extends OrdersEvent {
  final String id;
  const OrdersDeleteMismatch(this.id);

  @override
  List<Object?> get props => [id];
}

class OrdersSearchMismatchItems extends OrdersEvent {
  final String query;
  const OrdersSearchMismatchItems(this.query);

  @override
  List<Object?> get props => [query];
}

class OrdersToggleMismatchEdit extends OrdersEvent {
  final String id;
  const OrdersToggleMismatchEdit(this.id);

  @override
  List<Object?> get props => [id];
}

class OrdersSearchMismatchList extends OrdersEvent {
  final String query;
  const OrdersSearchMismatchList(this.query);

  @override
  List<Object?> get props => [query];
}

class OrdersSearchMismatchItemsCode extends OrdersEvent {
  final String query;
  const OrdersSearchMismatchItemsCode(this.query);
}

class OrdersSearchMismatchItemsName extends OrdersEvent {
  final String query;
  const OrdersSearchMismatchItemsName(this.query);
}

class OrdersClearMismatchResult extends OrdersEvent {}
// ==========================
// MAX ADJUSTMENT
// ==========================

class OrdersLoadMaxAdj extends OrdersEvent {
  const OrdersLoadMaxAdj();
}

class OrdersAddMaxAdj extends OrdersEvent {
  final Map<String, dynamic> data;
  const OrdersAddMaxAdj(this.data);

  @override
  List<Object?> get props => [data];
}

class OrdersDeleteMaxAdj extends OrdersEvent {
  final String id;
  const OrdersDeleteMaxAdj(this.id);

  @override
  List<Object?> get props => [id];
}

class OrdersSearchMaxAdjList extends OrdersEvent {
  final String query;

  const OrdersSearchMaxAdjList(this.query);
}

class OrdersExportPressed extends OrdersEvent {
  const OrdersExportPressed();
}

class OrdersFetchItemDemand extends OrdersEvent {
  final String itemCode;
  const OrdersFetchItemDemand(this.itemCode);
}

class OrdersToggleBranchMaxAdj extends OrdersEvent {
  final bool value;
  const OrdersToggleBranchMaxAdj(this.value);
}

class OrdersClearSelectedDemand extends OrdersEvent {
  const OrdersClearSelectedDemand();
}

class OrdersShowCreate extends OrdersEvent {}
