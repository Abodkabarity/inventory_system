import 'package:equatable/equatable.dart';

class CalcInput extends Equatable {
  final String formulary;
  final String reason;
  final num maxAdjustment30d;
  final num assortmentQtyBaseStock;
  final num sales30dFrom45d;
  final num tmaQty;
  final num branchStock;
  final num itemMinOrderUnit;

  const CalcInput({
    required this.formulary,
    required this.reason,
    required this.maxAdjustment30d,
    required this.assortmentQtyBaseStock,
    required this.sales30dFrom45d,
    required this.tmaQty,
    required this.branchStock,
    required this.itemMinOrderUnit,
  });

  @override
  List<Object?> get props => [
    formulary,
    reason,
    maxAdjustment30d,
    assortmentQtyBaseStock,
    sales30dFrom45d,
    tmaQty,
    branchStock,
    itemMinOrderUnit,
  ];
}
