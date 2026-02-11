import '../entities/calc_input.dart';
import '../entities/calc_output.dart';
import 'calc_demand30.dart';
import 'calc_reorder_max.dart';
import 'calc_reorder_min.dart';
import 'calc_reorder_qty.dart';

class ApplyOrderingCalculations {
  final CalcDemand30 calcDemand30;
  final CalcReorderMin calcReorderMin;
  final CalcReorderMax calcReorderMax;
  final CalcReorderQty calcReorderQty;

  const ApplyOrderingCalculations({
    required this.calcDemand30,
    required this.calcReorderMin,
    required this.calcReorderMax,
    required this.calcReorderQty,
  });

  CalcOutput call(CalcInput input) {
    final m = calcDemand30(input);
    final n = calcReorderMin(m);
    final o = calcReorderMax(m);

    final qty = calcReorderQty(
      input: input,
      demand30: m,
      reorderMin: n,
      reorderMax: o,
    );

    return CalcOutput(
      demand30: m,
      reorderMin: n,
      reorderMax: o,
      reorderQty: qty,
    );
  }
}
