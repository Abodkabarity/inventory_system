import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StoreRemoteDs {
  final SupabaseClient client;

  StoreRemoteDs(this.client);
  Future<List<String>> fetchBranchesToday() async {
    final today = DateFormat('EEEE').format(DateTime.now());

    final res = await client
        .from('branches')
        .select('branch_name, order_days')
        .eq('is_active', true);

    final rows = List<Map<String, dynamic>>.from(res);

    final branches = rows
        .where((row) {
          final days = List<String>.from(row['order_days'] ?? []);
          return days.contains(today);
        })
        .map((e) => e['branch_name'].toString())
        .toList();

    return branches;
  }

  /// SUBMITTED BRANCHES
  Future<List<String>> fetchSubmittedBranches(String runDate) async {
    final res = await client
        .from('order_submissions')
        .select('branch_name')
        .eq('run_date', runDate)
        .eq('status', 'submitted');

    return (res as List)
        .map((e) => (e['branch_name'] ?? '').toString())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  /// GET ALL BRANCHES
  Future<List<String>> fetchAllBranches() async {
    final res = await client
        .from('branches')
        .select('branch_name')
        .eq('is_active', true)
        .order('branch_name');

    return (res as List)
        .map((e) => (e['branch_name'] ?? '').toString())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// BRANCH ITEMS
  Future<List<Map<String, dynamic>>> fetchBranchItems({
    required String runDate,
    required String branch,
  }) async {
    print("runDate: $runDate");
    print("branch: $branch");
    final res = await client
        .from('daily_order')
        .select(
          'item_code,item_name,barcode,supplier,store_item_classifications,category,final_reorder_qty_store_stock_gt_0',
        )
        .eq('branch', branch)
        .eq('run_date', runDate);

    final rows = List<Map<String, dynamic>>.from(res);

    return rows.where((e) {
      final qty = num.tryParse(
        (e['final_reorder_qty_store_stock_gt_0'] ?? '0').toString(),
      );
      return qty != null && qty > 0;
    }).toList();
  }

  /// ADDITIONAL REQUESTS
  Future<List<Map<String, dynamic>>> fetchAdditionalRequestGroups({
    required String runDate,
  }) async {
    final res = await client.rpc(
      'get_additional_request_groups',
      params: {'p_run_date': runDate},
    );

    return List<Map<String, dynamic>>.from(res);
  }

  /// APPROVE REQUEST
  Future<void> approveRequest({required String id, required num qty}) async {
    await client
        .from('additional_requests')
        .update({
          'fulfilled_qty': qty,
          'status': 'done',
          'done_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }

  Future<List<Map<String, dynamic>>> fetchAdditionalRequestItems({
    required String branch,
    required DateTime createdAt,
  }) async {
    final res = await client
        .from('additional_requests')
        .select()
        .eq('branch_name', branch)
        .eq('status', 'sent_to_store')
        .eq('created_at', createdAt.toIso8601String());

    return List<Map<String, dynamic>>.from(res);
  }
}
