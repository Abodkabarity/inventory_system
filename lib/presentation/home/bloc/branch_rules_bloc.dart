import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/usecases/calc_30d_demand_for_branch.dart';
import 'branch_rules_event.dart';
import 'branch_rules_state.dart';

class BranchRulesBloc extends Bloc<BranchRulesEvent, BranchRulesState> {
  final SupabaseClient client;
  final GetSalesDemand30Map getSalesDemand30Map;

  BranchRulesBloc({required this.getSalesDemand30Map, SupabaseClient? client})
    : client = client ?? Supabase.instance.client,
      super(BranchRulesState.initial()) {
    on<LoadBranchRules>(_onLoad);
  }

  String _norm(dynamic v) {
    if (v == null) return '';
    var s = v.toString().trim().replaceAll(' ', '');
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    return s;
  }

  Future<List<Map<String, dynamic>>> _fetchAllByBranch({
    required String table,
    required String select,
    required String branchName,
    required String branchColumn,
    int pageSize = 500,
  }) async {
    final all = <Map<String, dynamic>>[];
    var from = 0;

    while (true) {
      final data = await client
          .from(table)
          .select(select)
          .eq(branchColumn, branchName)
          .range(from, from + pageSize - 1);

      final list = (data as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) break;

      all.addAll(list);
      from += pageSize;
      if (list.length < pageSize) break;
    }

    return all;
  }

  String _inferFormularyType(Map<String, dynamic> r) {
    final v = (r['revised_branch_formulary'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    if (v.contains('ESS')) return 'ESSENTIAL';
    return 'NON';
  }

  Future<void> _onLoad(
    LoadBranchRules event,
    Emitter<BranchRulesState> emit,
  ) async {
    final branchName = event.branchName.trim();
    debugPrint('BRANCH RULES: start "$branchName"');

    try {
      emit(state.copyWith(status: BranchRulesStatus.loading, error: null));

      final formularyRows = await _fetchAllByBranch(
        table: 'branch_formulary',
        select:
            'zone_name,branch_name,item_code,item_name,revised_branch_formulary,revised_date,reason',
        branchName: branchName,
        branchColumn: 'branch_name',
      );

      final assortmentRows = await _fetchAllByBranch(
        table: 'assortment',
        select:
            'branch_name,item_code,item_name,reason,assortment_qty,assortment_by,assortment_start,assortment_end',
        branchName: branchName,
        branchColumn: 'branch_name',
      );

      final tmaRows = await _fetchAllByBranch(
        table: 'tma',
        select:
            'branch_name,item_code,item_name,start_date,end_date,final_qty_to_keep,qty_per_duration',
        branchName: branchName,
        branchColumn: 'branch_name',
      );

      final demand30ByItemCode = await getSalesDemand30Map.call(
        branchName: branchName,
      );

      debugPrint('BRANCH RULES: counts "$branchName"');
      debugPrint('formulary=${formularyRows.length}');
      debugPrint('assortment=${assortmentRows.length}');
      debugPrint('tma=${tmaRows.length}');
      debugPrint('demand30Keys=${demand30ByItemCode.length}');

      final formularyMap = <String, String>{};
      for (final r in formularyRows) {
        final code = _norm(r['item_code']);
        if (code.isEmpty) continue;
        formularyMap[code] = _inferFormularyType(r);
      }

      final assortmentMap = <String, Map<String, dynamic>>{};
      for (final r in assortmentRows) {
        final code = _norm(r['item_code']);
        if (code.isEmpty) continue;
        assortmentMap[code] = r;
      }

      final tmaMap = <String, Map<String, dynamic>>{};
      for (final r in tmaRows) {
        final code = _norm(r['item_code']);
        if (code.isEmpty) continue;
        tmaMap[code] = r;
      }

      emit(
        state.copyWith(
          status: BranchRulesStatus.loaded,
          formularyTypeByItemCode: formularyMap,
          assortmentByItemCode: assortmentMap,
          tmaByItemCode: tmaMap,
          demand30ByItemCode: demand30ByItemCode,
        ),
      );
    } catch (e) {
      debugPrint('BRANCH RULES ERROR: $e');
      emit(
        state.copyWith(status: BranchRulesStatus.failure, error: e.toString()),
      );
    }
  }
}
