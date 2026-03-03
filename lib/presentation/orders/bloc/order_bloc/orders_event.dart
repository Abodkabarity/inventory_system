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

  const OrdersApplyAdditionalRequest({
    required this.itemCode,
    required this.itemName,
    required this.requestQty,
    required this.reason,
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
