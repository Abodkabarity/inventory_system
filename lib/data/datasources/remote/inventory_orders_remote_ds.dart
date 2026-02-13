import 'package:supabase_flutter/supabase_flutter.dart';

class InventoryOrdersRemoteDs {
  final SupabaseClient client;
  InventoryOrdersRemoteDs(this.client);

  Future<String> startGenerateAllOrders({required String runDate}) async {
    final res = await client.rpc(
      'start_generate_orders_all_branches',
      params: {'order_date': runDate},
    );
    if (res == null) throw Exception('RPC returned null job id');
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

    if (res is List && res.isNotEmpty) {
      return (res.first as Map).cast<String, dynamic>();
    }
    if (res is Map) return res.cast<String, dynamic>();
    return {'status': 'running'};
  }

  Future<Map<String, dynamic>> fetchHeadersPage({
    required String runDate,
    required int pageIndex,
    required int pageSize,
  }) async {
    final from = pageIndex * pageSize;
    final to = from + pageSize - 1;

    final data = await client
        .from('daily_order_headers_v')
        .select('run_date, branch_name, total_items')
        .eq('run_date', runDate)
        .order('branch_name', ascending: true)
        .range(from, to);

    final rows = (data as List).cast<Map<String, dynamic>>();
    return {'rows': rows};
  }

  Future<Map<String, dynamic>> fetchItemsPage({
    required String branchName, // branch name OR '__ALL__'
    required String runDate,
    required int pageIndex,
    required int pageSize,
  }) async {
    final from = pageIndex * pageSize;
    final to = from + pageSize - 1;

    final base = client.from('daily_order').select('*').eq('run_date', runDate);

    final data = branchName == '__ALL__'
        ? await base
              .order('branch', ascending: true)
              .order('item_code', ascending: true)
              .range(from, to)
        : await base
              .eq('branch', branchName)
              .order('item_code', ascending: true)
              .range(from, to);

    final rows = (data as List).cast<Map<String, dynamic>>();
    return {'rows': rows};
  }

  Future<Map<String, dynamic>?> fetchJob({required String jobId}) async {
    final data = await client
        .from('order_jobs')
        .select('*')
        .eq('job_id', jobId)
        .maybeSingle();

    if (data == null) return null;
    return (data as Map).cast<String, dynamic>();
  }
}
