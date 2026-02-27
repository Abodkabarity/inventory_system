import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class OrdersRemoteDs {
  final SupabaseClient client;
  OrdersRemoteDs(this.client);

  // ==========================
  // ✅ Fetch ALL rows for a branch (batched + progress)
  // - Uses keyset pagination (item_code > lastItemCode) to avoid OFFSET timeouts
  // - Includes simple retry on Postgres timeout (57014)
  // ==========================
  Future<List<Map<String, dynamic>>> fetchOrdersAll({
    required String runDate,
    required String branchName,
    int batchSize = 2000,
    void Function(int loaded)? onProgress,
  }) async {
    final out = <Map<String, dynamic>>[];

    const cols = '''
run_date, branch, item_code, item_name,
goods_received_last_7_days,
branch_stock, mismatch_stock, store_stock, pending_stock_received,
extra_qty_more_than_month, max_adjustment_30d, demand_for_30_days,
reorder_point_min, reorder_max, reorder_qty_num, reorder_qty,
final_reorder_qty_store_stock_gt_0, date_of_last_qty_received_in_branch,
qty_30_days_from_last_45d,
branch_formulary, assortment_qty_base_stock, assortment_by, reason, assortment_start, assortment_end,
tma_qty, tma_start, tma_end,
item_purchase_type, sales_orientation, category, sub_category, company, supplier, indication, active_ingredient,
pack_size, concentration, product_type_form, retail_price, vat,
is_upp,
item_minimum_order_unit,
barcode,
store_item_classifications
''';

    String lastItemCode = '';

    while (true) {
      final list = await _retryOnTimeout<List<Map<String, dynamic>>>(() async {
        PostgrestFilterBuilder q = client
            .from('daily_order')
            .select(cols)
            .eq('run_date', runDate);

        if (branchName != '__ALL__') {
          q = q.eq('branch', branchName);
        }

        // ✅ Keyset pagination: only fetch rows after the last item_code
        if (lastItemCode.isNotEmpty) {
          q = q.gt('item_code', lastItemCode);
        }

        final res = await q
            .order('item_code', ascending: true)
            .limit(batchSize);

        return (res as List).cast<Map<String, dynamic>>();
      });

      if (list.isEmpty) break;

      out.addAll(list);
      onProgress?.call(out.length);

      // update cursor
      lastItemCode = (list.last['item_code'] ?? '').toString().trim();
      if (lastItemCode.isEmpty) break;

      if (list.length < batchSize) break;
    }

    return out;
  }

  // ==========================
  // ✅ Fetch product info in safe chunks (avoid huge IN queries)
  // ==========================
  Future<List<Map<String, dynamic>>> fetchProductInfoBatch({
    required List<String> itemCodes,
  }) async {
    if (itemCodes.isEmpty) return [];

    const chunkSize = 300;
    final out = <Map<String, dynamic>>[];

    for (var i = 0; i < itemCodes.length; i += chunkSize) {
      final end = (i + chunkSize > itemCodes.length)
          ? itemCodes.length
          : i + chunkSize;
      final part = itemCodes.sublist(i, end);

      final list = await _retryOnTimeout<List<Map<String, dynamic>>>(() async {
        final res = await client
            .from('v_item_filters_for_orders')
            .select()
            .inFilter('item_code', part);

        return (res as List).cast<Map<String, dynamic>>();
      });

      out.addAll(list);
    }

    return out;
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

  // ==========================
  // Helpers
  // ==========================
  Future<T> _retryOnTimeout<T>(
    Future<T> Function() fn, {
    int maxAttempts = 3,
  }) async {
    Object? lastErr;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await fn();
      } catch (e) {
        lastErr = e;

        final isTimeout = _isStatementTimeout(e);
        if (!isTimeout || attempt == maxAttempts) rethrow;

        // Backoff: 250ms, 600ms, 1100ms ...
        final waitMs = 200 + (attempt * attempt * 200);
        await Future.delayed(Duration(milliseconds: waitMs));
      }
    }

    throw lastErr ?? Exception('Unknown error');
  }

  bool _isStatementTimeout(Object e) {
    final s = e.toString();
    return s.contains('57014') ||
        s.contains('statement timeout') ||
        s.contains('canceling statement due to statement timeout');
  }
}
