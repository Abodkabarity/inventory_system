import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/assortment_entry_model.dart';
import '../../models/branch_formulary_entry_model.dart';
import '../../models/max_adj_model.dart';
import '../../models/tma_entry_model.dart';

class BranchRulesRemoteDs {
  final SupabaseClient client;
  BranchRulesRemoteDs(this.client);

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

  Future<List<BranchFormularyEntryModel>> getFormulary(
    String branchName,
  ) async {
    final rows = await _fetchAllByBranch(
      table: 'branch_formulary',
      select:
          'zone_name,branch_name,item_code,item_name,revised_branch_formulary,revised_date,reason',
      branchName: branchName,
      branchColumn: 'branch_name',
    );
    return rows.map(BranchFormularyEntryModel.fromMap).toList();
  }

  Future<List<AssortmentEntryModel>> getAssortment(String branchName) async {
    final rows = await _fetchAllByBranch(
      table: 'assortment',
      select:
          'branch_name,item_code,item_name,reason,assortment_qty,assortment_by,assortment_start,assortment_end',
      branchName: branchName,
      branchColumn: 'branch_name',
    );
    return rows.map(AssortmentEntryModel.fromMap).toList();
  }

  Future<List<TmaEntryModel>> getTma(String branchName) async {
    final rows = await _fetchAllByBranch(
      table: 'tma',
      select:
          'branch_name,item_code,item_name,start_date,end_date,final_qty_to_keep,qty_per_duration',
      branchName: branchName,
      branchColumn: 'branch_name',
    );
    return rows.map(TmaEntryModel.fromMap).toList();
  }

  Future<List<MaxAdjModel>> getMaxAdj(String branchName) async {
    final rows = await _fetchAllByBranch(
      table: 'max_adj',
      select:
          'branch_name,item_code,item_name,current_demand_30d,max_adjustment_30d,adjustment_type,reason,update_date,qty',
      branchName: branchName,
      branchColumn: 'branch_name',
    );
    return rows.map(MaxAdjModel.fromMap).toList();
  }
}
