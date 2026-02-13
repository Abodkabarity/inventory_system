import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/sales_entry_model.dart';

class SalesRemoteDs {
  final SupabaseClient client;
  const SalesRemoteDs(this.client);

  Future<Map<String, num>> fetchSumQtyByItemCode({
    required String branchName,
    int pageSize = 2000,
  }) async {
    final sums = <String, num>{};
    var from = 0;

    while (true) {
      final data = await client
          .from('sales_last_45_days')
          .select('branch_name,item_code,qty,inv_date')
          .ilike('branch_name', branchName.trim())
          .order('inv_date', ascending: true)
          .order('item_code', ascending: true)
          .range(from, from + pageSize - 1);

      final list = (data as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) break;

      for (final row in list) {
        final m = SalesRowModel.fromMap(row);
        if (m.itemCode.isEmpty) continue;
        sums[m.itemCode] = (sums[m.itemCode] ?? 0) + m.qty;
      }

      from += pageSize;
      if (list.length < pageSize) break;
    }

    return sums;
  }
}
