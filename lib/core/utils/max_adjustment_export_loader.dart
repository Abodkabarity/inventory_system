import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/data_batch_config.dart';

/// Read only through the signed-in client's existing RLS policies. An indexed
/// ID cursor avoids ever-growing OFFSET scans and tolerates API row caps.
Future<List<Map<String, dynamic>>> loadMaxAdjustmentExport({
  required SupabaseClient client,
  required bool history,
  void Function(int loaded, int total)? onProgress,
}) async {
  final table = history ? 'max_adj_log' : 'max_adj';
  const columns =
      'id,branch_name,item_code,item_name,current_demand_30d,'
      'max_adjustment_30d,adjustment_type,reason,update_date,qty,created_at,'
      'added_by,end_date';
  final selected = history ? '$columns,action_type,moved_at' : columns;
  const requestTimeout = Duration(seconds: 45);
  // Pin the upper ID and exact row count before reading data. If the roster
  // changes, fail visibly rather than download a silently incomplete workbook.
  final header = await client
      .from(table)
      .select('id')
      .order('id', ascending: false)
      .limit(1)
      .count(CountOption.exact)
      .timeout(requestTimeout);
  final total = header.count;
  onProgress?.call(0, total);
  if (total == 0) return [];
  if (header.data.isEmpty) {
    throw StateError('Export records are unavailable. Please retry.');
  }
  final upperId = header.data.first['id'];
  final rows = <Map<String, dynamic>>[];
  final ids = <Object>{};
  Object? after;
  var batchSize = DataBatchConfig.batchSize;
  while (rows.length < total) {
    var query = client.from(table).select(selected).lte('id', upperId);
    if (after != null) query = query.gt('id', after);
    dynamic response;
    try {
      response = await query
          .order('id', ascending: true)
          .limit(batchSize)
          .timeout(requestTimeout);
    } on PostgrestException catch (error) {
      // A cold history index can exceed the database's statement timeout.
      // Retry this read at the SAME cursor with fewer rows; never retry writes.
      if (error.code != '57014' ||
          batchSize <= DataBatchConfig.batchSize ~/ 8) {
        rethrow;
      }
      batchSize ~/= 2;
      continue;
    } on TimeoutException {
      if (batchSize <= DataBatchConfig.batchSize ~/ 8) rethrow;
      batchSize ~/= 2;
      continue;
    }
    final batch = List<Map<String, dynamic>>.from(response);
    if (batch.isEmpty) {
      throw StateError('Export records changed during loading. Please retry.');
    }
    for (final row in batch) {
      final id = row['id'];
      if (id == null || !ids.add(id)) {
        throw StateError(
          'Export records changed during loading. Please retry.',
        );
      }
    }
    rows.addAll(batch);
    if (rows.length > total) {
      throw StateError('Export records changed during loading. Please retry.');
    }
    after = batch.last['id'];
    onProgress?.call(rows.length, total);
    // Allow progress and input to paint between response decoding tasks.
    await Future<void>.delayed(Duration.zero);
  }
  if (after != upperId) {
    throw StateError('Export records changed during loading. Please retry.');
  }
  return rows;
}
