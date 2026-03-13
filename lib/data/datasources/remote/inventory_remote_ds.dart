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
        .select()
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
}
