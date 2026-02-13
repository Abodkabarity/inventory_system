import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/assortment_entry_model.dart';
import '../../models/branch_formulary_entry_model.dart';
import '../../models/tma_entry_model.dart';

class SupabaseBranchRulesRemoteDs {
  final SupabaseClient client;
  SupabaseBranchRulesRemoteDs(this.client);

  Future<List<Map<String, dynamic>>> _fetchAll({
    required String table,
    required String select,
    required String branchName,
    int pageSize = 500,
  }) async {
    final all = <Map<String, dynamic>>[];
    var from = 0;

    while (true) {
      final data = await client
          .from(table)
          .select(select)
          .ilike('branch_name', branchName.trim())
          .range(from, from + pageSize - 1);

      final list = (data as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) break;

      all.addAll(list);
      from += pageSize;
    }

    return all;
  }

  Future<List<BranchFormularyEntryModel>> getBranchFormulary(
    String branchName,
  ) async {
    final rows = await _fetchAll(
      table: 'branch_formulary',
      select:
          'branch_name,item_code,item_name,type,formulary_type,revised_branch_formulary',
      branchName: branchName,
    );
    return rows.map(BranchFormularyEntryModel.fromMap).toList();
  }

  Future<List<AssortmentEntryModel>> getAssortment(String branchName) async {
    final rows = await _fetchAll(
      table: 'assortment',
      select:
          'branch_name,item_code,item_name,reason,assortment_qty,assortment_by,assortment_start,assortment_end',
      branchName: branchName,
    );
    return rows.map(AssortmentEntryModel.fromMap).toList();
  }

  Future<List<TmaEntryModel>> getTma(String branchName) async {
    final rows = await _fetchAll(
      table: 'tma',
      select:
          'branch_name,item_code,item_name,start_date,end_date,final_qty_to_keep,qty_per_duration',
      branchName: branchName,
    );
    return rows.map(TmaEntryModel.fromMap).toList();
  }
}
