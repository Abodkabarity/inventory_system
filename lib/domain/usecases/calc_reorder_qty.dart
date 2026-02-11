import '../entities/calc_input.dart';

class CalcReorderQty {
  const CalcReorderQty();

  String call({
    required CalcInput input,
    required int demand30,
    required int reorderMin,
    required int reorderMax,
  }) {
    final reason = input.reason.trim();
    final formulary = input.formulary.trim();
    final branchStock = input.branchStock.toDouble();
    final bl = input.itemMinOrderUnit.toDouble();
    final tmaQtyRaw = input.tmaQty;

    final hasTma = _hasValue(tmaQtyRaw);
    final isNewItem = reason == 'New Item';

    if (bl <= 0 || !bl.isFinite) return '';

    final canOrder = demand30 > 0 && branchStock <= reorderMin;

    if (isNewItem || hasTma) {
      if (!canOrder) return '';
      return _qtyToMultiple(reorderMax - branchStock, bl);
    } else {
      if (formulary == 'NON') return 'NON FORMULARY';
      if (!canOrder) return '';
      return _qtyToMultiple(reorderMax - branchStock, bl);
    }
  }

  bool _hasValue(num v) {
    return v.toDouble() != 0;
  }

  String _qtyToMultiple(double needed, double bl) {
    if (!needed.isFinite) return '';
    if (needed <= 0) return '';
    final mult = (needed / bl).ceil();
    final qty = mult * bl;
    final intQty = qty.round();
    return intQty.toString();
  }
}
