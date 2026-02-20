import 'package:supabase_flutter/supabase_flutter.dart';

class OrdersRemoteDs {
  final SupabaseClient client;
  OrdersRemoteDs(this.client);

  // ==========================
  // ✅ Fetch ALL rows for a branch (batched + progress)
  // ==========================
  Future<List<Map<String, dynamic>>> fetchOrdersAll({
    required String runDate,
    required String branchName,
    int batchSize = 5000,
    void Function(int loaded)? onProgress,
  }) async {
    final out = <Map<String, dynamic>>[];
    var from = 0;

    const cols = '''
      run_date, branch, item_code, item_name,
      branch_stock, mismatch_stock, store_stock, pending_stock_received,
      extra_qty_more_than_month, max_adjustment_30d, demand_for_30_days,
      final_reorder_qty_store_stock_gt_0, qty_30_days_from_last_45d,
      branch_formulary, assortment_qty_base_stock, assortment_by,
      item_purchase_type, category, is_upp, item_minimum_order_unit
    ''';

    while (true) {
      var q = client
          .from('v_daily_order_latest')
          .select(cols)
          .eq('run_date', runDate);

      if (branchName != '__ALL__') {
        q = q.eq('branch', branchName);
      }

      final res = await q
          .order('item_code', ascending: true)
          .range(from, from + batchSize - 1);

      final list = (res as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) break;

      out.addAll(list);

      // ✅ report progress
      onProgress?.call(out.length);

      if (list.length < batchSize) break;
      from += batchSize;
    }

    return out;
  }

  Future<List<Map<String, dynamic>>> fetchProductInfoBatch({
    required List<String> itemCodes,
  }) async {
    if (itemCodes.isEmpty) return [];

    final res = await client
        .from('v_item_filters_for_orders')
        .select()
        .inFilter('item_code', itemCodes);

    return (res as List).cast<Map<String, dynamic>>();
  }

  // ==========================
  // ✅ Generate branch order
  // ==========================
  Future<String> generateBranchOrder({
    required String runDate,
    required String branchName,
  }) async {
    final res = await client.rpc(
      'start_daily_order_job',
      params: {'p_batch_size': 2000, 'p_run_date': runDate},
    );
    return res.toString();
  }

  // ==========================
  // Existing All-branches job
  // ==========================
  Future<String> generateAllOrders({required String runDate}) async {
    final res = await client.rpc(
      'start_generate_orders_all_branches',
      params: {'order_date': runDate},
    );
    return res.toString();
  }

  Future<Map<String, dynamic>> stepGenerateAllOrders({
    required String jobId,
    int chunkSize = 10,
  }) async {
    final res = await client.rpc(
      'step_generate_orders_all_branches',
      params: {'p_job_id': jobId, 'p_chunk_size': chunkSize},
    );
    return (res as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>?> fetchJob({required String jobId}) async {
    final res = await client
        .from('inventory_generate_jobs')
        .select()
        .eq('job_id', jobId)
        .maybeSingle();

    return res == null ? null : (res as Map).cast<String, dynamic>();
  }
}
