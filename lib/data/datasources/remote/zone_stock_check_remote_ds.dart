import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/entities/stock_check_task.dart';

/// Complete, validated reads for the zone's Stock Check reports and alerts.
class ZoneStockCheckRemoteDs {
  static const batchSize = 5000;
  final SupabaseClient client;

  ZoneStockCheckRemoteDs(this.client);

  Future<List<StockCheckTask>> load(
    Iterable<String> branches, {
    bool pendingOnly = false,
  }) async {
    // A manager can own several zones. Query each raw branch identity once,
    // including when repeated names would otherwise cross chunk boundaries.
    final names =
        branches.where((name) => name.trim().isNotEmpty).toSet().toList()
          ..sort();
    final result = <StockCheckTask>[];
    for (var start = 0; start < names.length; start += 20) {
      final end = (start + 20).clamp(0, names.length);
      result.addAll(await _loadChunk(names.sublist(start, end), pendingOnly));
    }
    return result;
  }

  PostgrestFilterBuilder<List<Map<String, dynamic>>> _query(
    List<String> branches,
    bool pendingOnly, {
    String columns = '*',
  }) {
    var query = client
        .from('stock_check_tasks')
        .select(columns)
        .inFilter('branch_name', branches);
    if (pendingOnly) query = query.eq('status', 'pending');
    return query;
  }

  Future<({int count, String version})> _snapshot(
    List<String> branches,
    bool pendingOnly,
  ) async {
    final response =
        await _query(branches, pendingOnly, columns: 'id,updated_at')
            .order('updated_at', ascending: false)
            .order('id', ascending: true)
            .limit(1)
            .count(CountOption.exact);
    return (
      count: response.count,
      version: response.data.isEmpty
          ? ''
          : '${response.data.first['id']}|${response.data.first['updated_at']}',
    );
  }

  Future<List<StockCheckTask>> _loadChunk(
    List<String> branches,
    bool pendingOnly,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final before = await _snapshot(branches, pendingOnly);
      final rows = <StockCheckTask>[];
      final ids = <String>{};
      String? cursor;
      var invalid = false;
      while (rows.length < before.count) {
        var query = _query(branches, pendingOnly);
        if (cursor != null) query = query.gt('id', cursor);
        // Dates are shared by whole campaigns. Paging by the unique ID avoids
        // unstable OFFSET pages duplicating one branch and omitting another.
        final page = await query.order('id', ascending: true).limit(batchSize);
        if (page.isEmpty) break;
        for (final data in page) {
          final row = StockCheckTask.fromMap(data);
          if (row.id.isEmpty ||
              !ids.add(row.id) ||
              !branches.contains(row.branchName) ||
              (pendingOnly && !row.isPending)) {
            invalid = true;
            break;
          }
          rows.add(row);
        }
        if (invalid) break;
        cursor = rows.last.id;
        // Continue even if the server returned fewer than 5,000 rows: its API
        // cap can be smaller than the requested batch size.
      }
      final after = await _snapshot(branches, pendingOnly);
      if (!invalid && before == after && rows.length == before.count) {
        return rows;
      }
    }
    throw StateError(
      'Stock Check changed while loading. Refresh and try again.',
    );
  }
}
