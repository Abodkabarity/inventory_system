// orders_event.dart
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

class OrdersToggleColumn extends OrdersEvent {
  final String columnKey;
  final bool visible;
  const OrdersToggleColumn({required this.columnKey, required this.visible});

  @override
  List<Object?> get props => [columnKey, visible];
}

class OrdersResetColumns extends OrdersEvent {
  const OrdersResetColumns();
}

// Filters
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

// Save / Reset edit
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
