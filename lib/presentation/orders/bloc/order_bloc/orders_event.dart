// orders_event.dart
import 'package:equatable/equatable.dart';

abstract class OrdersEvent extends Equatable {
  const OrdersEvent();

  @override
  List<Object?> get props => [];
}

// =========================
// Main actions
// =========================
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

// =========================
// Columns (NEW SYSTEM)
// =========================
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

// =========================
// Filters
// =========================
class OrdersCategoryChanged extends OrdersEvent {
  final String category; // 'ALL'
  const OrdersCategoryChanged(this.category);

  @override
  List<Object?> get props => [category];
}

class OrdersFormularyChanged extends OrdersEvent {
  final String formulary; // 'ALL'/'ESSENTIAL'/'NON'
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

// ✅ NEW: numeric final reorder only
class OrdersNumericFinalOnlyToggled extends OrdersEvent {
  final bool value;
  const OrdersNumericFinalOnlyToggled(this.value);

  @override
  List<Object?> get props => [value];
}

// ✅ NEW: clear all filters
class OrdersClearAllFilters extends OrdersEvent {
  const OrdersClearAllFilters();
}

// =========================
// Side panel selection
// =========================
class OrdersSelectItemForEdit extends OrdersEvent {
  final String itemCode;
  const OrdersSelectItemForEdit(this.itemCode);

  @override
  List<Object?> get props => [itemCode];
}

class OrdersClearSelection extends OrdersEvent {
  const OrdersClearSelection();
}

// =========================
// Save / Reset edit
// =========================
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
