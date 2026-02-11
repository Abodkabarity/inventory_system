import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/_norm.dart';

class StockRemoteDs {
  final SupabaseClient client;
  const StockRemoteDs(this.client);

  Future<List<Map<String, dynamic>>> _fetchAll({
    required String table,
    required String select,
    required List<_Filter> filters,
    String? orderBy1,
    String? orderBy2,
    int pageSize = 2000,
  }) async {
    final all = <Map<String, dynamic>>[];
    var from = 0;

    while (true) {
      // مهم: نخليه dynamic لأن order() يغيّر نوع الـ builder
      dynamic q = client.from(table).select(select);

      for (final f in filters) {
        q = f.apply(q);
      }

      if (orderBy1 != null) q = q.order(orderBy1, ascending: true);
      if (orderBy2 != null) q = q.order(orderBy2, ascending: true);

      final data = await q.range(from, from + pageSize - 1);
      final list = (data as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) break;

      all.addAll(list);
      from += pageSize;
      if (list.length < pageSize) break;
    }

    return all;
  }

  Future<Map<String, num>> fetchLedgerQtyMap({
    required String branchName,
  }) async {
    final rows = await _fetchAll(
      table: 'stk_ledger',
      select: 'branch_name,item_code,actual_qty',
      filters: [_eq('branch_name', branchName)],
      orderBy1: 'item_code',
    );

    final out = <String, num>{};
    for (final r in rows) {
      final code = normCode(r['item_code']);
      if (code.isEmpty) continue;
      out[code] = (out[code] ?? 0) + parseNum(r['actual_qty']);
    }
    return out;
  }

  Future<Map<String, num>> fetchMismatchDiffMap({
    required String branchName,
  }) async {
    final rows = await _fetchAll(
      table: 'stk_mismatch',
      select: 'branch_name,item_code,diff,update_date',
      filters: [_eq('branch_name', branchName)],
      orderBy1: 'update_date',
      orderBy2: 'item_code',
    );

    // إذا في أكثر من سجل لنفس item_code => آخر واحد (بسبب orderBy update_date)
    final out = <String, num>{};
    for (final r in rows) {
      final code = normCode(r['item_code']);
      if (code.isEmpty) continue;
      out[code] = parseNum(r['diff']);
    }
    return out;
  }

  Future<Map<String, num>> fetchPendingQtyMap({
    required String branchName,
  }) async {
    final rows = await _fetchAll(
      table: 'transfer',
      select: 'to_warehouse,status,completed,item_code,qty,transfer_date',
      filters: [
        _eq('to_warehouse', branchName),
        _eq('status', 'Approved'),
        _ilike('completed', '%Uncompleted%'),
      ],
      orderBy1: 'transfer_date',
      orderBy2: 'item_code',
    );

    final out = <String, num>{};
    for (final r in rows) {
      final code = normCode(r['item_code']);
      if (code.isEmpty) continue;
      out[code] = (out[code] ?? 0) + parseNum(r['qty']);
    }
    return out;
  }
}

abstract class _Filter {
  dynamic apply(dynamic q);
}

class _eq extends _Filter {
  final String col;
  final Object value;
  _eq(this.col, this.value);

  @override
  dynamic apply(dynamic q) => q.eq(col, value);
}

class _ilike extends _Filter {
  final String col;
  final String pattern;
  _ilike(this.col, this.pattern);

  @override
  dynamic apply(dynamic q) => q.ilike(col, pattern);
}
