import '../../../../domain/usecases/apply_ordering_calculations.dart';
import '../../../../domain/usecases/calc_demand30.dart';
import '../../../../domain/usecases/calc_reorder_max.dart';
import '../../../../domain/usecases/calc_reorder_min.dart';
import '../../../../domain/usecases/calc_reorder_qty.dart';
import 'ordering_calc_bloc.dart';

class OrderingCalcBlocFactory {
  static OrderingCalcBloc create() {
    final apply = ApplyOrderingCalculations(
      calcDemand30: const CalcDemand30(),
      calcReorderMin: const CalcReorderMin(),
      calcReorderMax: const CalcReorderMax(),
      calcReorderQty: const CalcReorderQty(),
    );

    return OrderingCalcBloc(apply: apply);
  }
}
