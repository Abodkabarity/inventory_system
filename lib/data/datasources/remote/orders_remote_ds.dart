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
max_type,
item_minimum_order_unit,
barcode,
total_reorder_today,
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
  Future<Map<String, dynamic>> fetchBranchInfo({
    required String branchName,
  }) async {
    final branch = await client
        .from('branches')
        .select('''
zone,
submit_start_hour,
submit_end_hour,
max_adj_limit,
order_increase_limit,
order_edit_limit,
additional_order_limit
''')
        .eq('branch_name', branchName)
        .single();

    final usage = await client
        .from('vw_max_adj_usage')
        .select('''
used_slots,
remaining_slots,
next_available_date,
days_until_next_slot
''')
        .eq('branch_name', branchName)
        .single();

    return {...branch, ...usage};
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
        for (final row in part) {
          await client.rpc(
            'create_additional_request',
            params: {
              'p_request_group_id': row['request_group_id'],
              'p_run_date': row['run_date'],
              'p_zone': row['zone'],
              'p_branch_name': row['branch_name'],
              'p_item_code': row['item_code'],
              'p_item_name': row['item_name'],
              'p_request_qty': row['request_qty'],
              'p_reason': row['reason'],

              'p_branch_stock': row['branch_stock'],
              'p_store_stock': row['store_stock'],
              'p_sales_45d': row['sales_45d'],
              'p_final_reorder_qty': row['final_reorder_qty'],
              'p_item_purchase_type': row['item_purchase_type'],
              'p_max_type': row['max_type'],

              'p_contact_logistic': row['contact_logistic'],
            },
          );
        }
        final ids = part
            .map((e) => e['draft_id'])
            .where((e) => e != null)
            .toList();

        if (ids.isNotEmpty) {
          await client
              .from('additional_request_drafts')
              .delete()
              .inFilter('id', ids);
        }
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

  /// ==========================
  /// MAX ADJ UPSERT FROM FINAL REORDER
  /// ==========================
  Future<void> upsertMaxAdjFromFinalReorder({
    required String branchName,
    required String itemCode,
    required String itemName,
    required num oldQty,
    required num newQty,
    required num currentDemand,
    required String reason,
  }) async {
    final now = DateTime.now().toIso8601String();

    /// calculate real decrease amount
    final adjustment = (oldQty - newQty);

    /// do nothing if no decrease
    if (adjustment <= 0) return;

    /// check if record already exists
    final existing = await client
        .from('max_adj')
        .select()
        .eq('branch_name', branchName)
        .eq('item_code', itemCode)
        .maybeSingle();

    if (existing != null) {
      /// ==========================
      /// 1) move old record to log
      /// ==========================
      await client.from('max_adj_log').insert({
        'branch_name': existing['branch_name'],
        'item_code': existing['item_code'],
        'item_name': existing['item_name'],

        'current_demand_30d': existing['current_demand_30d'],
        'max_adjustment_30d': existing['max_adjustment_30d'],
        'qty': existing['qty'],
        'update_date': existing['update_date'],
        'adjustment_type': existing['adjustment_type'],
        'reason': existing['reason'],
        'added_by': existing['added_by'],

        /// audit fields
        'action_type': 'update_by_branch',
        'moved_at': now,
        'original_id': existing['id'],
      });

      /// ==========================
      /// 2) update main table
      /// ==========================
      await client
          .from('max_adj')
          .update({
            /// correct columns
            'current_demand_30d': currentDemand,
            'max_adjustment_30d': adjustment,
            'qty': adjustment,

            'adjustment_type': 'DECREASE',
            'reason': reason,
            'added_by': 'branch',

            'update_date': now.split('T')[0],
            'created_at': now,
          })
          .eq('branch_name', branchName)
          .eq('item_code', itemCode);
    } else {
      /// ==========================
      /// 3) insert new record
      /// ==========================
      await client.from('max_adj').insert({
        'branch_name': branchName,
        'item_code': itemCode,
        'item_name': itemName,

        /// correct columns
        'current_demand_30d': currentDemand,
        'max_adjustment_30d': adjustment,

        'adjustment_type': 'DECREASE',
        'qty': adjustment,

        'reason': reason,
        'added_by': 'branch',

        'update_date': now.split('T')[0],
        'created_at': now,
      });
    }
  }

  Future<void> upsertFinalReorderDraft({
    required String runDate,
    required String branchName,
    required String itemCode,
    required String itemName,
    required int oldQty,
    required int newQty,
    required String reason,
  }) async {
    await client.from('order_edits_draft').upsert({
      'run_date': runDate,
      'branch_name': branchName,
      'item_code': itemCode,
      'item_name': itemName,
      'old_qty': oldQty,
      'new_qty': newQty,
      'reason': reason,
      'status': 'draft',
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'run_date,branch_name,item_code');
  }

  Future<List<Map<String, dynamic>>> fetchFinalReorderDrafts({
    required String runDate,
    required String branchName,
  }) async {
    final res = await client
        .from('order_edits_draft')
        .select()
        .eq('run_date', runDate)
        .eq('branch_name', branchName);

    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> upsertAdditionalRequestDraft({
    required String runDate,
    required String branchName,
    required String itemCode,
    required String itemName,
    required num requestQty,
    required String reason,
    required bool isUrgent,
  }) async {
    await client.from('additional_request_drafts').upsert({
      'run_date': runDate,
      'branch_name': branchName,
      'item_code': itemCode,
      'item_name': itemName,
      'request_qty': requestQty,
      'reason': reason,
      'contact_logistic': isUrgent ? 'urgent' : null,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'run_date,branch_name,item_code');
  }

  Future<List<Map<String, dynamic>>> fetchAdditionalRequestDrafts({
    required String runDate,
    required String branchName,
  }) async {
    final res = await client
        .from('additional_request_drafts')
        .select()
        .eq('run_date', runDate)
        .eq('branch_name', branchName);

    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> deleteAdditionalRequestDraft({required String id}) async {
    await client.from('additional_request_drafts').delete().eq('id', id);
  }

  Future<bool> isOperationalOrderReady({required String runDate}) async {
    final row = await client
        .from('daily_order_job_state')
        .select('phase')
        .eq('run_date', runDate)
        .maybeSingle();

    if (row == null) {
      return false;
    }

    final phase = (row['phase'] ?? '').toString().trim();

    return phase == 'done';
  }
  // ==========================
  // ITEMS TO ORDER
  // ==========================

  Future<void> createItemToOrder({
    required String runDate,
    required String branchName,
    required String itemCode,
    required String itemName,
    required num qty,
    required String reason,
  }) async {
    await client.from('items_to_order').insert({
      'run_date': runDate,
      'branch_name': branchName,
      'item_code': itemCode,
      'item_name': itemName,
      'qty': qty,
      'reason': reason,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> fetchItemsToOrder({
    required String runDate,
    required String branchName,
  }) async {
    final res = await client
        .from('items_to_order')
        .select()
        .eq('run_date', runDate)
        .eq('branch_name', branchName)
        .eq('status', 'pending')
        .order('created_at');

    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<void> deleteItemToOrder({required String id}) async {
    await client.from('items_to_order').delete().eq('id', id);
  }

  Future<void> markItemToOrderProcessed({required String id}) async {
    await client
        .from('items_to_order')
        .update({'status': 'added_to_order'})
        .eq('id', id);
  }

  Future<void> clearProcessedItemsToOrder({
    required String runDate,
    required String branchName,
  }) async {
    await client
        .from('items_to_order')
        .delete()
        .eq('run_date', runDate)
        .eq('branch_name', branchName)
        .inFilter('status', ['added_to_order', 'ignored']);
  }

  Future<List<Map<String, dynamic>>> searchItemsToOrderSuggestions(
    String query,
  ) async {
    if (query.trim().isEmpty) return [];

    final res = await client
        .from('item_report')
        .select('item_code,item_name')
        .or('item_code.ilike.%$query%,item_name.ilike.%$query%')
        .limit(20);

    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<void> updateItemToOrderStatus({
    required String id,
    required String status,
  }) async {
    await client.from('items_to_order').update({'status': status}).eq('id', id);
  }

  Future<int> fetchAdditionalRequestsCount({
    required String runDate,
    required String branchName,
  }) async {
    final drafts = await client
        .from('additional_request_drafts')
        .select('id')
        .eq('run_date', runDate)
        .eq('branch_name', branchName);

    final sent = await client
        .from('additional_requests')
        .select('id')
        .eq('run_date', runDate)
        .eq('branch_name', branchName);

    return drafts.length + sent.length;
  }
}
