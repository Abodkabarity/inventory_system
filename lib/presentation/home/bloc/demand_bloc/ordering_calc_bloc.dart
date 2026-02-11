import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/calc_input.dart';
import '../../../../domain/usecases/apply_ordering_calculations.dart';
import 'ordering_calc_event.dart';
import 'ordering_calc_state.dart';

class OrderingCalcBloc extends Bloc<OrderingCalcEvent, OrderingCalcState> {
  final ApplyOrderingCalculations apply;

  OrderingCalcBloc({required this.apply}) : super(OrderingCalcState.initial()) {
    on<CalculateOrderingColumns>(_onCalc);
  }

  Future<void> _onCalc(
    CalculateOrderingColumns event,
    Emitter<OrderingCalcState> emit,
  ) async {
    try {
      debugPrint('ORDERING CALC: event received rows=${event.rows.length}');
      if (event.rows.isNotEmpty) {
        debugPrint(
          'ORDERING CALC: sample row keys=${event.rows.first.keys.toList()}',
        );
        debugPrint(
          'ORDERING CALC: sample row item_code=${event.rows.first['item_code']}',
        );
      }

      emit(state.copyWith(status: OrderingCalcStatus.calculating));

      final outRows = <Map<String, dynamic>>[];

      var idx = 0;
      for (final r in event.rows) {
        final input = _mapRowToInput(r);

        if (idx == 0) {
          debugPrint(
            'ORDERING CALC: input[0] formulary="${input.formulary}" reason="${input.reason}" '
            'maxAdj=${input.maxAdjustment30d} assortment=${input.assortmentQtyBaseStock} '
            'sales30d=${input.sales30dFrom45d} tma=${input.tmaQty} '
            'branchStock=${input.branchStock} minUnit=${input.itemMinOrderUnit}',
          );
        }

        final out = apply(input);

        if (idx == 0) {
          debugPrint(
            'ORDERING CALC: output[0] demand30=${out.demand30} min=${out.reorderMin} '
            'max=${out.reorderMax} qty="${out.reorderQty}"',
          );
        }

        final updated = Map<String, dynamic>.from(r);

        // ✅ Use the same keys already present in your table rows
        updated['demand_for_30_days'] = out.demand30;
        updated['reorder_point_min'] = out.reorderMin;
        updated['reorder_max'] = out.reorderMax;
        updated['reorder_qty'] = out.reorderQty;

        outRows.add(updated);
        idx++;
      }

      debugPrint('ORDERING CALC: computed rows=${outRows.length}');
      if (outRows.isNotEmpty) {
        debugPrint(
          'ORDERING CALC: sample updated[0] '
          'demand_for_30_days=${outRows.first['demand_for_30_days']} '
          'reorder_point_min=${outRows.first['reorder_point_min']} '
          'reorder_max=${outRows.first['reorder_max']} '
          'reorder_qty="${outRows.first['reorder_qty']}"',
        );
      }

      emit(state.copyWith(status: OrderingCalcStatus.success, rows: outRows));
      debugPrint('ORDERING CALC: emit success');
    } catch (e) {
      debugPrint('ORDERING CALC ERROR: $e');
      emit(
        state.copyWith(status: OrderingCalcStatus.failure, error: e.toString()),
      );
    }
  }

  CalcInput _mapRowToInput(Map<String, dynamic> r) {
    return CalcInput(
      formulary: _s(r['branch_formulary']),
      reason: _s(r['reason']),
      maxAdjustment30d: _n(r['max_adjustment_30d']),
      assortmentQtyBaseStock: _n(r['assortment_qty_base_stock']),
      sales30dFrom45d: _n(r['qty_30_days_from_last_45d']),
      tmaQty: _n(r['tma_qty']),
      branchStock: _n(r['branch_stock']),
      itemMinOrderUnit: _n(r['min_order_unit']),
    );
  }

  String _s(dynamic v) => (v ?? '').toString().trim();

  num _n(dynamic v) {
    if (v == null) return 0;
    final s = v.toString().trim();
    if (s.isEmpty) return 0;
    final x = num.tryParse(s.replaceAll(',', ''));
    return x ?? 0;
  }
}
