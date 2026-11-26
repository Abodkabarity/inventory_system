import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/data_batch_config.dart';
import '../../domain/entities/store_additional_request_status.dart';

/// Scoped operations use the existing signed-in client and table permissions.
/// Printing never changes approval, fulfillment, quantities or completed lines.
class StoreAdditionalRequestRepository {
  StoreAdditionalRequestRepository(
    this.client, {
    required this.groupId,
    required this.branch,
    required this.sourceTable,
  }) {
    if (!{
      'additional_requests',
      'additional_order_inventory',
    }.contains(sourceTable)) {
      throw ArgumentError.value(sourceTable, 'sourceTable');
    }
  }
  final SupabaseClient client;
  final String groupId, branch, sourceTable;
  static const _timeout = Duration(seconds: 45);

  Future<List<Map<String, dynamic>>> load() async {
    final rows = <Map<String, dynamic>>[];
    final ids = <String>{};
    int? expected;
    while (true) {
      var query = client
          .from(sourceTable)
          .select()
          .eq('request_group_id', groupId);
      if (sourceTable == 'additional_requests') {
        query = query.eq('branch_name', branch);
      }
      final response = await query
          .order('id', ascending: true)
          .range(rows.length, rows.length + DataBatchConfig.batchSize - 1)
          .count(CountOption.exact)
          .timeout(_timeout);
      expected ??= response.count;
      final batch = List<Map<String, dynamic>>.from(response.data);
      if (response.count != expected ||
          (batch.isEmpty && rows.length < expected)) {
        throw StateError('The request changed while loading. Please refresh.');
      }
      for (final row in batch) {
        if (row['id'] == null || !ids.add(row['id'].toString())) {
          throw StateError(
            'The request changed while loading. Please refresh.',
          );
        }
      }
      rows.addAll(batch);
      if (rows.length > expected) {
        throw StateError('Incomplete request. Please refresh.');
      }
      if (rows.length == expected) return rows;
    }
  }

  /// A compare-and-set prevents concurrent confirmations from being reopened.
  /// No automatic retry: a failed write may have committed.
  Future<int> markPrinted(List<Map<String, dynamic>> printed) async {
    final ids = printed
        .where(StoreAdditionalRequestStatus.waiting)
        .map((item) => item['id'].toString())
        .toSet()
        .toList();
    var changed = 0;
    for (
      var offset = 0;
      offset < ids.length;
      offset += DataBatchConfig.batchSize
    ) {
      var query = client
          .from(sourceTable)
          .update({'store_status': 'processing'})
          .eq('request_group_id', groupId)
          .eq('status', 'sent_to_store')
          .or('store_status.is.null,store_status.eq.')
          .inFilter(
            'id',
            ids.sublist(
              offset,
              (offset + DataBatchConfig.batchSize).clamp(0, ids.length),
            ),
          );
      if (sourceTable == 'additional_requests') {
        query = query.eq('branch_name', branch);
      }
      final updated = await query.select('id').timeout(_timeout);
      changed += updated.length;
    }
    return changed;
  }
}
