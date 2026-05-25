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
    int retry = 0;

    while (retry < 5) {
      try {
        final orderRes = await client
            .from('daily_order')
            .select(
              'item_code,item_name,barcode,supplier,store_item_classifications,category,final_reorder_qty_store_stock_gt_0',
            )
            .eq('branch', branch)
            .eq('run_date', runDate)
            .neq('final_reorder_qty_store_stock_gt_0', 'NON FORMULARY')
            .neq('final_reorder_qty_store_stock_gt_0', '')
            .neq('final_reorder_qty_store_stock_gt_0', '0');

        final orderRows = List<Map<String, dynamic>>.from(orderRes);

        final editsRes = await client
            .from('order_edits')
            .select('item_code,new_qty')
            .eq('branch_name', branch)
            .eq('run_date', runDate);

        final edits = List<Map<String, dynamic>>.from(editsRes);

        final Map<String, num> editsMap = {
          for (var e in edits)
            e['item_code'].toString():
                num.tryParse(e['new_qty'].toString()) ?? 0,
        };

        final result = orderRows
            .map((row) {
              final itemCode = row['item_code'].toString();

              num qty;

              if (editsMap.containsKey(itemCode)) {
                qty = editsMap[itemCode]!;
              } else {
                qty =
                    num.tryParse(
                      (row['final_reorder_qty_store_stock_gt_0'] ?? '0')
                          .toString(),
                    ) ??
                    0;
              }

              return {...row, 'final_qty': qty};
            })
            .where((row) {
              final qty = row['final_qty'];

              return qty != null && qty > 0;
            })
            .toList();

        return result;
      } catch (e) {
        if (e.toString().contains('statement timeout')) {
          retry++;

          print("Retry fetchBranchItems $retry");

          await Future.delayed(const Duration(milliseconds: 500));

          continue;
        }

        rethrow;
      }
    }

    return [];
  }

  /// ADDITIONAL REQUEST GROUPS (NO RUN DATE FILTER)
  Future<List<Map<String, dynamic>>> fetchAdditionalRequestGroups() async {
    final now = DateTime.now();

    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final res = await client
        .from('additional_requests')
        .select(
          'request_group_id, branch_name, created_at, status, done_at, inventory_qty,store_status ,contact_logistic',
        )
        .or(
          'status.eq.sent_to_store,'
          'and(status.eq.done,done_at.gte.${startOfDay.toIso8601String()},done_at.lt.${endOfDay.toIso8601String()}),'
          'and(status.eq.rejected,done_at.gte.${startOfDay.toIso8601String()},done_at.lt.${endOfDay.toIso8601String()})',
        )
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  /// APPROVE REQUEST
  Future<void> approveRequest({required String id, required num qty}) async {
    final status = qty == 0 ? 'rejected' : 'done';

    await client
        .from('additional_requests')
        .update({
          'fulfilled_qty': qty,
          'status': status,
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

  Future<List<Map<String, dynamic>>> fetchAdditionalHistory({
    required DateTime from,
    required DateTime to,
  }) async {
    final res = await client
        .from('additional_requests')
        .select()
        .gte('created_at', from.toIso8601String())
        .lte('created_at', to.toIso8601String())
        .inFilter('status', ['done', 'rejected'])
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> fetchAllSentToStore() async {
    final res = await client
        .from('additional_requests')
        .select()
        .eq('status', 'sent_to_store')
        .or('store_status.is.null,store_status.eq.');
    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> markAsProcessing(List<String> ids) async {
    await client
        .from('additional_requests')
        .update({'store_status': 'processing'})
        .inFilter('id', ids);
  }

  Future<List<Map<String, dynamic>>> fetchProcessingRequests() async {
    final res = await client
        .from('additional_requests')
        .select()
        .eq('store_status', 'processing');

    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> fetchProductSuggestions({
    required String branch,
    required String query,
  }) async {
    if (query.trim().isEmpty) {
      return [];
    }

    final res = await client
        .from('product_movement_history')
        .select('item_code,item_name,barcode')
        .eq('branch', branch)
        .or(
          'item_name.ilike.%$query%,'
          'item_code.ilike.%$query%,'
          'barcode.ilike.%$query%',
        )
        .limit(20);

    final rows = List<Map<String, dynamic>>.from(res);

    final unique = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      unique[row['item_code']] = row;
    }

    return unique.values.toList();
  }

  Future<List<Map<String, dynamic>>> fetchProductMovement({
    required String branch,
    required String itemCode,
  }) async {
    final res = await client
        .from('product_movement_history')
        .select()
        .eq('branch', branch)
        .eq('item_code', itemCode)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<String>> fetchMovementBranches() async {
    final res = await client
        .from('branches')
        .select('branch_name')
        .eq('is_active', true)
        .order('branch_name');

    return List<Map<String, dynamic>>.from(
      res,
    ).map((e) => e['branch_name'].toString()).toList();
  }
}
