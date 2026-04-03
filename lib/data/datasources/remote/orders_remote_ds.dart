import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class OrdersRemoteDs {
  final SupabaseClient client;
  OrdersRemoteDs(this.client);

  // ==========================
  // Fetch ALL rows for a branch (batched + progress)
  // - Keyset pagination to avoid OFFSET timeouts
  // - Retry on Postgres timeout (57014)
  // ==========================
  Future<List<Map<String, dynamic>>> fetchOrdersAll({
    required String runDate,
    required String branchName,
    int batchSize = 1000,
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

      lastItemCode = (list.last['item_code'] ?? '').toString().trim();
      if (lastItemCode.isEmpty) break;

      if (list.length < batchSize) break;
    }

    return out;
  }

  // ==========================
  // Fetch product info in safe chunks
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
  // Generate branch order
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
  // NEW: Fetch branch zone from branches table
  // ==========================
  Future<String> fetchBranchZone({required String branchName}) async {
    final row = await _retryOnTimeout<Map<String, dynamic>?>(() async {
      final res = await client
          .from('branches')
          .select('zone')
          .eq('branch_name', branchName)
          .maybeSingle();

      if (res == null) return null;
      return (res as Map).cast<String, dynamic>();
    });

    if (row == null) {
      throw Exception('Branch not found in branches table');
    }

    final z = (row['zone'] ?? '').toString().trim();
    if (z.isEmpty) {
      throw Exception('Zone is empty for this branch');
    }

    return z;
  }

  // ==========================
  // NEW: Upsert order edits (changed items only)
  // ==========================
  Future<void> upsertOrderEdits({
    required String runDate,
    required String zone,
    required String branchName,
    required List<Map<String, dynamic>> rows,
  }) async {
    if (rows.isEmpty) return;

    const chunkSize = 500;

    for (var i = 0; i < rows.length; i += chunkSize) {
      final end = (i + chunkSize > rows.length) ? rows.length : i + chunkSize;
      final part = rows.sublist(i, end);

      await _retryOnTimeout<void>(() async {
        await client
            .from('order_edits')
            .upsert(part, onConflict: 'run_date,branch_name,item_code');
      });
    }
  }

  // ==========================
  // NEW: Submission status (draft/submitted)
  // ==========================
  Future<void> upsertSubmission({
    required String runDate,
    required String zone,
    required String branchName,
    required String status,
  }) async {
    await _retryOnTimeout<void>(() async {
      final payload = <String, dynamic>{
        'run_date': runDate,
        'zone': zone,
        'branch_name': branchName,
        'status': status,
        'submitted_at': status == 'submitted'
            ? DateTime.now().toIso8601String()
            : null,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await client
          .from('order_submissions')
          .upsert(payload, onConflict: 'run_date,branch_name');
    });
  }

  Future<String> fetchSubmissionStatus({
    required String runDate,
    required String branchName,
  }) async {
    final row = await _retryOnTimeout<Map<String, dynamic>?>(() async {
      final res = await client
          .from('order_submissions')
          .select('status')
          .eq('run_date', runDate)
          .eq('branch_name', branchName)
          .maybeSingle();

      if (res == null) return null;
      return (res as Map).cast<String, dynamic>();
    });

    if (row == null) return 'draft';
    final s = (row['status'] ?? 'draft').toString().trim();
    return s.isEmpty ? 'draft' : s;
  }

  // ==========================
  // NEW: Additional requests (history insert)
  // ==========================
  Future<void> insertAdditionalRequests({
    required String runDate,
    required String zone,
    required String branchName,
    required List<Map<String, dynamic>> rows,
  }) async {
    if (rows.isEmpty) return;

    const chunkSize = 500;
    for (var i = 0; i < rows.length; i += chunkSize) {
      final end = (i + chunkSize > rows.length) ? rows.length : i + chunkSize;
      final part = rows.sublist(i, end);

      await _retryOnTimeout<void>(() async {
        await client.from('additional_requests').insert(part);
      });
    }
  }

  Future<Map<String, num>> fetchAdditionalRequestsForBranch({
    required String runDate,
    required String branchName,
  }) async {
    final list = await _retryOnTimeout<List<Map<String, dynamic>>>(() async {
      final res = await client
          .from('additional_requests')
          .select('item_code, request_qty')
          .eq('run_date', runDate)
          .eq('branch_name', branchName);

      return (res as List).cast<Map<String, dynamic>>();
    });

    final out = <String, num>{};
    for (final r in list) {
      final code = (r['item_code'] ?? '').toString().trim();
      if (code.isEmpty) continue;

      final v = r['request_qty'];
      num qty = 0;
      if (v is num) {
        qty = v;
      } else {
        qty = num.tryParse((v ?? '').toString().trim()) ?? 0;
      }

      out[code] = (out[code] ?? 0) + qty;
    }

    return out;
  }

  Future<Map<String, List<Map<String, dynamic>>>>
  fetchAdditionalRequestsHistoryForBranch({
    required String runDate,
    required String branchName,
  }) async {
    final list = await _retryOnTimeout<List<Map<String, dynamic>>>(() async {
      final res = await client
          .from('additional_requests')
          .select('item_code, request_qty, reason, created_at')
          .eq('run_date', runDate)
          .eq('branch_name', branchName)
          .order('created_at', ascending: false);

      return (res as List).cast<Map<String, dynamic>>();
    });

    final out = <String, List<Map<String, dynamic>>>{};

    for (final r in list) {
      final code = (r['item_code'] ?? '').toString().trim();
      if (code.isEmpty) continue;

      (out[code] ??= <Map<String, dynamic>>[]).add(r);
    }

    return out;
  }

  // ==========================
  // NEW: Tracking list for branch
  // ==========================
  Future<List<Map<String, dynamic>>> fetchAdditionalRequestsTrackingForBranch({
    String? runDate,
    required String branchName,
  }) async {
    const cols = '''
id,
item_code,
item_name,
request_qty,
reason,
status,
fulfilled_qty,
store_note,
created_at,
sent_to_store_at,
done_at
''';

    final list = await _retryOnTimeout<List<Map<String, dynamic>>>(() async {
      PostgrestFilterBuilder query = client
          .from('additional_requests')
          .select(cols)
          .eq('branch_name', branchName);

      if (runDate != null) {
        query = query.eq('run_date', runDate);
      }

      final res = await query.order('created_at', ascending: false);

      return (res as List).cast<Map<String, dynamic>>();
    });

    return list;
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
  // ==========================
  // MISMATCH
  // ==========================

  Future<List<Map<String, dynamic>>> fetchMismatch({
    required String branch,
  }) async {
    final res = await client
        .from('stk_mismatch')
        .select()
        .eq('branch_name', branch)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> insertMismatch(Map<String, dynamic> data) async {
    final branch = data['branch_name'];
    final itemCode = data['item_code'];

    final system = (data['system_stock'] ?? 0) as num;
    final actual = (data['actual_stock'] ?? 0) as num;

    final diff = actual - system;

    final exists = await client
        .from('stk_mismatch')
        .select('id')
        .eq('branch_name', branch)
        .eq('item_code', itemCode)
        .maybeSingle();

    if (exists != null) {
      throw Exception('Item already exists for this branch');
    }

    final payload = {
      ...data,

      'diff': diff,

      'update_date': DateTime.now().toIso8601String().split('T')[0],
      'created_at': DateTime.now().toIso8601String(),
    };

    await client.from('stk_mismatch').insert(payload);
  }

  Future<void> updateMismatch({
    required String id,
    required num system,
    required num actual,
    required Map old,
  }) async {
    final diff = actual - system;

    await client
        .from('stk_mismatch')
        .update({'system_stock': system, 'actual_stock': actual, 'diff': diff})
        .eq('id', id);
  }

  Future<void> deleteMismatch(String id) async {
    await client.from('stk_mismatch').delete().eq('id', id);
  }

  /// 🔥 SEARCH PRODUCTS

  Future<List<Map<String, dynamic>>> searchItemsByCode(String query) async {
    final res = await client
        .from('v_item_filters_for_orders')
        .select('item_code,item_name')
        .ilike('item_code', '%$query%')
        .limit(20);

    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> searchItemsByName(String query) async {
    final res = await client
        .from('v_item_filters_for_orders')
        .select('item_code,item_name')
        .ilike('item_name', '%$query%')
        .limit(20);

    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> fetchMaxAdj({
    required String branch,
  }) async {
    final res = await client
        .from('max_adj')
        .select()
        .eq('branch_name', branch)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> insertMaxAdj(Map<String, dynamic> data) async {
    final branch = data['branch_name'];
    final itemCode = data['item_code'];

    final exists = await client
        .from('max_adj')
        .select('id')
        .eq('branch_name', branch)
        .eq('item_code', itemCode)
        .maybeSingle();

    if (exists != null) {
      throw Exception('Item already exists for this branch');
    }

    final payload = {
      ...data,

      'update_date': DateTime.now().toIso8601String().split('T')[0],
      'created_at': DateTime.now().toIso8601String(),
    };

    await client.from('max_adj').insert(payload);
  }

  Future<void> deleteMaxAdj(String id) async {
    await client.from('max_adj').delete().eq('id', id);
  }

  Future<List<String>> fetchBranchOrderDays({
    required String branchName,
  }) async {
    final res = await client
        .from('branches')
        .select('order_days')
        .eq('branch_name', branchName)
        .maybeSingle();

    if (res == null) return [];

    final list = res['order_days'] as List<dynamic>? ?? [];

    return list.map((e) => e.toString()).toList();
  }

  Future<num> fetchItemDemand({
    required String branch,
    required String itemCode,
  }) async {
    final res = await client
        .from('daily_order')
        .select('demand_for_30_days')
        .eq('branch', branch)
        .eq('item_code', itemCode)
        .order('run_date', ascending: false)
        .limit(1)
        .maybeSingle();

    if (res == null) return 0;

    final v = res['demand_for_30_days'];
    if (v is num) return v;

    return num.tryParse((v ?? '').toString()) ?? 0;
  }
}
