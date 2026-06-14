import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InventoryRemoteDs {
  final SupabaseClient client;

  InventoryRemoteDs(this.client);

  Future<List<String>> fetchBranchesToday() async {
    final today = DateFormat('EEEE').format(DateTime.now());

    final res = await client
        .from('branches')
        .select('branch_name, order_days')
        .eq('is_active', true);

    final rows = List<Map<String, dynamic>>.from(res);

    return rows
        .where((row) {
          final days = List<String>.from(row['order_days'] ?? []);
          return days.contains(today);
        })
        .map((e) => e['branch_name'].toString())
        .toList();
  }

  Future<List<String>> fetchSubmittedBranches(String runDate) async {
    final res = await client
        .from('order_submissions')
        .select('branch_name')
        .eq('run_date', runDate)
        .eq('status', 'submitted');

    return (res as List)
        .map((e) => (e['branch_name'] ?? '').toString())
        .toSet()
        .toList();
  }

  /// ===============================
  /// ORDER EDITS
  /// ===============================

  Future<List<Map<String, dynamic>>> fetchBranchEdits({
    required String runDate,
    required String branch,
  }) async {
    final res = await client
        .from('order_edits')
        .select()
        .eq('run_date', runDate)
        .eq('branch_name', branch)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  /// ===============================
  /// ADDITIONAL REQUESTS
  /// ===============================

  Future<List<Map<String, dynamic>>> fetchAdditionalRequests() async {
    final res = await client
        .from('additional_requests')
        .select('''
        id,
        request_group_id,
        run_date,
        created_at,
        branch_name,
        item_code,
        item_name,
        status,
        request_qty,
        fulfilled_qty,
        store_note,
        inventory_qty,
        inventory_note,
        contact_logistic,

        branch_stock,
        store_stock,
        sales_45d,
        final_reorder_qty,
        item_purchase_type,
        max_type
      ''')
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  /// ===============================
  /// ADDITIONAL TODAY
  /// ===============================

  Future<int> fetchAdditionalToday() async {
    final now = DateTime.now();

    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    final res = await client
        .from('additional_requests')
        .select('id')
        .gte('created_at', start.toIso8601String())
        .lt('created_at', end.toIso8601String());

    return (res as List).length;
  }

  /// ===============================
  /// ADDITIONAL MONTH
  /// ===============================

  Future<int> fetchAdditionalMonth() async {
    final now = DateTime.now();

    final start = DateTime(now.year, now.month, 1);

    final res = await client
        .from('additional_requests')
        .select('id')
        .gte('created_at', start.toIso8601String());

    return (res as List).length;
  }

  /// ===============================
  /// INVENTORY APPROVAL
  /// ===============================

  Future<void> approveInventory({required String id, required num qty}) async {
    final status = qty == 0 ? 'rejected' : 'sent_to_store';

    await client
        .from('additional_requests')
        .update({
          'inventory_qty': qty,
          'inventory_approved_at': DateTime.now().toIso8601String(),
          'status': status,
        })
        .eq('id', id);
  }

  Future<Map<String, int>> fetchBranchEditsCount(String runDate) async {
    final res = await client
        .from('order_edits')
        .select('branch_name')
        .eq('run_date', runDate);

    final rows = List<Map<String, dynamic>>.from(res);

    final Map<String, int> counts = {};

    for (var r in rows) {
      final branch = r['branch_name'].toString();

      counts[branch] = (counts[branch] ?? 0) + 1;
    }

    return counts;
  }

  Future<Map<String, int>> fetchAdditionalTodayByBranch(String runDate) async {
    final res = await client
        .from('additional_requests')
        .select('branch_name')
        .eq('run_date', runDate);

    final rows = List<Map<String, dynamic>>.from(res);

    final Map<String, int> counts = {};

    for (var r in rows) {
      final branch = (r['branch_name'] ?? '').toString();

      counts[branch] = (counts[branch] ?? 0) + 1;
    }

    return counts;
  }

  Future<int> fetchAdditionalMonthByBranch(String branch) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);

    final res = await client
        .from('additional_requests')
        .select('id')
        .eq('branch_name', branch)
        .gte('created_at', start.toIso8601String());

    return (res as List).length;
  }

  Future<int> fetchAdditionalTodayByBranchExact(String branch) async {
    final now = DateTime.now();

    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    final res = await client
        .from('additional_requests')
        .select('id')
        .eq('branch_name', branch)
        .gte('created_at', start.toIso8601String())
        .lt('created_at', end.toIso8601String());

    return (res as List).length;
  }

  Future<List<Map<String, dynamic>>> fetchMismatch() async {
    List<Map<String, dynamic>> all = [];

    int from = 0;
    const int limit = 10000;

    while (true) {
      final res = await client
          .from('stk_mismatch')
          .select()
          .order('update_date', ascending: false)
          .range(from, from + limit - 1);

      final data = List<Map<String, dynamic>>.from(res);

      if (data.isEmpty) break;

      all.addAll(data);

      if (data.length < limit) break;

      from += limit;
    }

    return all;
  }

  Future<List<Map<String, dynamic>>> fetchMismatchLog(
    String branch,
    String itemCode,
  ) async {
    final res = await client
        .from('mismatch_log')
        .select()
        .eq('branch_name', branch)
        .eq('item_code', itemCode)
        .order('changed_at', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  Future<int> fetchMismatchMonth() async {
    final res = await client.rpc('count_mismatch_month');
    return res as int;
  }

  Future<int> fetchMismatchToday() async {
    final res = await client.rpc('count_mismatch_today');
    return res as int;
  }

  Future<int> fetchMismatchTotal() async {
    final res = await client.rpc('count_mismatch_total');
    return res as int;
  }

  Future<num> fetchMismatchDiffSum() async {
    final res = await client.rpc('sum_mismatch_diff');
    return (res as num?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> fetchMismatchTracker({
    required DateTime from,
    required DateTime to,
    String? branch,
  }) async {
    final res = await client.rpc(
      'get_mismatch_tracker',
      params: {
        'p_from': from.toIso8601String(),
        'p_to': to.toIso8601String(),
        'p_branch': branch,
      },
    );

    return List<Map<String, dynamic>>.from(res);
  }

  Future<Map<String, int>> fetchTodayCounts() async {
    final now = DateTime.now().toLocal();
    final start = now.subtract(const Duration(hours: 24));

    final res = await client
        .from('additional_requests')
        .select('item_code, branch_name')
        .gte('created_at', start.toIso8601String());
    final rows = List<Map<String, dynamic>>.from(res);

    final Map<String, int> counts = {};

    for (var r in rows) {
      final key = "${r['item_code']}_${r['branch_name']}";
      counts[key] = (counts[key] ?? 0) + 1;
    }

    return counts;
  }

  Future<void> approveAllInventory(List<Map<String, dynamic>> items) async {
    await client.rpc('approve_all_inventory', params: {'p_items': items});
  }

  Future<void> storeApprove(List<Map<String, dynamic>> items) async {
    await client.rpc('store_approve_requests', params: {'p_items': items});
  }

  /// Streams ALL rows using parallel batches.
  /// [onProgress] is called after each round with (loaded, estimated total).
  Future<List<Map<String, dynamic>>> fetchOrdersAllInventory({
    required String runDate,
    void Function(int loaded)? onProgress,
  }) async {
    const cols = '''
run_date, branch, item_code, item_name,
goods_received_last_7_days,
branch_stock, mismatch_stock, store_stock, pending_stock_received,
extra_qty_more_than_month, max_adjustment_30d, demand_for_30_days,
reorder_point_min, reorder_max, reorder_qty_num, reorder_qty,
final_reorder_qty_store_stock_gt_0, date_of_last_qty_received_in_branch,
qty_30_days_from_last_45d,
branch_formulary, assortment_qty_base_stock, assortment_by, reason,
assortment_start, assortment_end,
tma_qty, tma_start, tma_end,
item_purchase_type, sales_orientation, category, sub_category, company,
supplier, indication, active_ingredient, pack_size, concentration,
product_type_form, retail_price, vat, is_upp, max_type,
item_minimum_order_unit, barcode, store_item_classifications
''';

    const int batchSize = 10000; // rows per request
    const int concurrent = 8; // simultaneous requests per round

    final all = <Map<String, dynamic>>[];
    int offset = 0;

    while (true) {
      // Fire `concurrent` requests at the same time
      final offsets = List.generate(concurrent, (i) => offset + i * batchSize);

      final results = await Future.wait(
        offsets.map(
          (from) => client
              .from('daily_order')
              .select(cols)
              .eq('run_date', runDate)
              .range(from, from + batchSize - 1),
        ),
      );

      bool anyData = false;

      for (final res in results) {
        final batch = List<Map<String, dynamic>>.from(res);
        if (batch.isEmpty) continue;
        anyData = true;
        all.addAll(batch);
      }

      onProgress?.call(all.length);

      // Stop when the last batch in this round returned fewer rows than batchSize
      // (means we reached the end of the table)
      final lastBatch = List<Map<String, dynamic>>.from(results.last);
      if (!anyData || lastBatch.length < batchSize) break;

      offset += concurrent * batchSize;
    }

    return all;
  }

  Future<List<Map<String, dynamic>>> fetchBranchAllChanges({
    required String branch,
  }) async {
    final now = DateTime.now();

    final today9pm = DateTime(now.year, now.month, now.day, 21);

    final end = now.isBefore(today9pm)
        ? today9pm
        : today9pm.add(const Duration(days: 1));

    final start = end.subtract(const Duration(days: 1));

    final res = await client.rpc(
      'get_branch_all_changes',
      params: {
        'p_branch': branch,
        'p_from': start.toIso8601String(),
        'p_to': end.toIso8601String(),
      },
    );

    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> fetchOrdersPage({
    required String runDate,

    required int from,

    required int to,
  }) async {
    const cols = '''
run_date,
branch,
item_code,
item_name,
goods_received_last_7_days,
branch_stock,
mismatch_stock,
store_stock,
pending_stock_received,
extra_qty_more_than_month,
max_adjustment_30d,
demand_for_30_days,
reorder_point_min,
reorder_max,
reorder_qty_num,
reorder_qty,
final_reorder_qty_store_stock_gt_0,
date_of_last_qty_received_in_branch,
qty_30_days_from_last_45d,
branch_formulary,
assortment_qty_base_stock,
assortment_by,
reason,
assortment_start,
assortment_end,
tma_qty,
tma_start,
tma_end,
item_purchase_type,
sales_orientation,
category,
sub_category,
company,
supplier,
indication,
active_ingredient,
pack_size,
concentration,
product_type_form,
retail_price,
vat,
is_upp,
max_type,
item_minimum_order_unit,
barcode,
store_item_classifications
''';

    final res = await client
        .from('daily_order')
        .select(cols)
        .eq('run_date', runDate)
        .order('item_code', ascending: true)
        .order('branch', ascending: true)
        .range(from, to);

    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> importAssortmentBulk(List<Map<String, dynamic>> rows) async {
    await client.rpc('import_assortment_bulk', params: {'p_rows': rows});
  }

  Future<void> deleteAssortmentBulk(List<Map<String, dynamic>> rows) async {
    await client.rpc('delete_assortment_bulk', params: {'p_rows': rows});
  }

  Future<void> importTmaBulk(List<Map<String, dynamic>> rows) async {
    await client.rpc('import_tma_bulk', params: {'p_rows': rows});
  }

  Future<void> deleteTmaBulk(List<Map<String, dynamic>> rows) async {
    await client.rpc('delete_tma_bulk', params: {'p_rows': rows});
  }

  Future<void> importMaxAdjBulk(List<Map<String, dynamic>> rows) async {
    await client.rpc('import_max_adj_bulk', params: {'p_rows': rows});
  }

  Future<void> deleteMaxAdjBulk(List<Map<String, dynamic>> rows) async {
    await client.rpc('delete_max_adj_bulk', params: {'p_rows': rows});
  }

  Future<Map<String, dynamic>> fetchMaxAdjustmentPage({
    required int from,
    required int to,
    String query = '',
  }) async {
    const cols = '''
id,
branch_name,
item_code,
item_name,
current_demand_30d,
max_adjustment_30d,
adjustment_type,
reason,
update_date,
qty,
created_at,
added_by,
end_date
''';

    final search = query.trim();
    final hasSearch = search.isNotEmpty;
    final safe = search.replaceAll(',', ' ');

    if (hasSearch) {
      final filter =
          'item_code.ilike.%$safe%,item_name.ilike.%$safe%,branch_name.ilike.%$safe%,adjustment_type.ilike.%$safe%,reason.ilike.%$safe%';

      final rowsRes = await client
          .from('max_adj')
          .select(cols)
          .or(filter)
          .order('created_at', ascending: false)
          .order('item_code', ascending: true)
          .range(from, to);

      final countRes = await client.from('max_adj').select('id').or(filter);

      return {
        'rows': List<Map<String, dynamic>>.from(rowsRes),
        'total': (countRes as List).length,
      };
    }

    final rowsRes = await client
        .from('max_adj')
        .select(cols)
        .order('created_at', ascending: false)
        .order('item_code', ascending: true)
        .range(from, to);

    final countRes = await client.from('max_adj').select('id');

    return {
      'rows': List<Map<String, dynamic>>.from(rowsRes),
      'total': (countRes as List).length,
    };
  }

  Future<List<Map<String, dynamic>>> searchOrders({
    required String runDate,
    required String query,
  }) async {
    final result = await client.rpc(
      'search_daily_orders',
      params: {'p_run_date': runDate, 'p_query': query},
    );

    return List<Map<String, dynamic>>.from(result);
  }

  Future<Map<String, dynamic>> fetchAdditionalOrderAnalysis({
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await client.rpc(
      'get_additional_order_analysis',
      params: {'p_from': from.toIso8601String(), 'p_to': to.toIso8601String()},
    );

    if (result == null) return {};

    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> fetchRequestEffectiveness({
    required DateTime from,
    required DateTime to,
    String? branch,
  }) async {
    final result = await client.rpc(
      'get_request_effectiveness',
      params: {
        'p_from': from.toIso8601String(),
        'p_to': to.toIso8601String(),
        'p_branch': branch,
      },
    );

    if (result == null) return {};
    return Map<String, dynamic>.from(result as Map);
  }

  Future<Map<String, dynamic>> fetchFormularyPage({
    required int from,
    required int to,
    String query = '',
  }) async {
    const cols = '''
branch_name,
item_code,
item_name,
revised_branch_formulary,
revised_date,
reason
''';

    final search = query.trim();
    final hasSearch = search.isNotEmpty;
    final safe = search.replaceAll(',', ' ');

    if (hasSearch) {
      final rowsRes = await client
          .from('branch_formulary')
          .select(cols)
          .or(
            'item_code.ilike.%$safe%,item_name.ilike.%$safe%,branch_name.ilike.%$safe%',
          )
          .order('revised_date', ascending: false)
          .order('item_code', ascending: true)
          .range(from, to);

      final countRes = await client
          .from('branch_formulary')
          .select('id')
          .or(
            'item_code.ilike.%$safe%,item_name.ilike.%$safe%,branch_name.ilike.%$safe%',
          );

      return {
        'rows': List<Map<String, dynamic>>.from(rowsRes),
        'total': (countRes as List).length,
      };
    }

    final rowsRes = await client
        .from('branch_formulary')
        .select(cols)
        .order('revised_date', ascending: false)
        .order('item_code', ascending: true)
        .range(from, to);

    final countRes = await client.from('branch_formulary').select('id');

    return {
      'rows': List<Map<String, dynamic>>.from(rowsRes),
      'total': (countRes as List).length,
    };
  }
}
