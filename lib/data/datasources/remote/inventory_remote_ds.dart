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

      daily_order:daily_order(
        branch_stock,
        store_stock,
        qty_30_days_from_last_45d,
        final_reorder_qty_store_stock_gt_0,
        item_purchase_type
      )
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
    final res = await client
        .from('stk_mismatch')
        .select()
        .order('update_date', ascending: false);

    return List<Map<String, dynamic>>.from(res);
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
}
