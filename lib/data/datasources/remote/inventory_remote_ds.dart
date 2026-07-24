import 'dart:async';

import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../domain/entities/branch_setting.dart';

class InventoryRemoteDs {
  final SupabaseClient client;

  InventoryRemoteDs(this.client);

  static const String _additionalRequestColumns = '''
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
        inventory_approved_at,
        done_at,
        contact_logistic,

        branch_stock,
        store_stock,
        sales_45d,
        final_reorder_qty,
        item_purchase_type,
        store_item_classifications,
        max_type
      ''';

  Future<List<String>> fetchBranchesToday([String? runDate]) async {
    final orderDate = DateTime.tryParse(runDate ?? '') ?? DateTime.now();
    final today = DateFormat('EEEE').format(orderDate);

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

  Future<Map<String, DateTime>> fetchSubmittedBranchTimes(
    String runDate,
  ) async {
    final res = await client
        .from('order_submissions')
        .select('branch_name, submitted_at')
        .eq('run_date', runDate)
        .eq('status', 'submitted')
        .order('submitted_at', ascending: true);

    final result = <String, DateTime>{};
    for (final row in List<Map<String, dynamic>>.from(res)) {
      final branch = (row['branch_name'] ?? '').toString();
      if (branch.isEmpty) continue;

      final submittedAt = DateTime.tryParse(
        (row['submitted_at'] ?? '').toString(),
      );
      if (submittedAt == null) continue;

      result.putIfAbsent(branch, () => submittedAt);
    }
    return result;
  }

  Future<void> submitBranchOrder({
    required String runDate,
    required String branch,
  }) async {
    final branchRow = await client
        .from('branches')
        .select('zone')
        .eq('branch_name', branch)
        .maybeSingle();

    final zone = (branchRow?['zone'] ?? '').toString();
    final now = DateTime.now().toIso8601String();

    await client.from('order_submissions').upsert({
      'run_date': runDate,
      'zone': zone,
      'branch_name': branch,
      'status': 'submitted',
      'submitted_at': now,
      'updated_at': now,
    }, onConflict: 'run_date,branch_name');
  }

  Future<void> deleteBranchSubmission({
    required String runDate,
    required String branch,
  }) async {
    await client
        .from('order_submissions')
        .delete()
        .eq('run_date', runDate)
        .eq('branch_name', branch);
  }

  Future<List<BranchSetting>> fetchBranchSettings() async {
    late final List<dynamic> res;
    try {
      res = await client
          .from('branches')
          .select('''
          branch_name,
          email,
          zone,
          zone_manager,
          zone_manager_email,
          is_active,
          order_days,
          submit_start_hour,
          submit_end_hour,
          max_adj_limit,
          order_increase_limit,
          order_edit_limit,
          additional_order_limit,
          area,
          branch_type
        ''')
          .order('branch_name', ascending: true);
    } catch (_) {
      res = await client
          .from('branches')
          .select('''
          branch_name,
          email,
          zone,
          is_active,
          order_days,
          submit_start_hour,
          submit_end_hour,
          max_adj_limit,
          order_increase_limit,
          order_edit_limit,
          additional_order_limit,
          area,
          branch_type
        ''')
          .order('branch_name', ascending: true);
    }

    return List<Map<String, dynamic>>.from(
      res,
    ).map(BranchSetting.fromMap).toList();
  }

  Future<void> saveBranchSetting({
    required BranchSetting branch,
    String? originalBranchName,
  }) async {
    final payload = branch.toMap();
    final original = (originalBranchName ?? '').trim();

    if (original.isEmpty) {
      await client.from('branches').insert(payload);
      return;
    }

    await client.from('branches').update(payload).eq('branch_name', original);
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
    final now = DateTime.now();
    final todayNinePm = DateTime(now.year, now.month, now.day, 21);
    final start = now.isBefore(todayNinePm)
        ? todayNinePm.subtract(const Duration(days: 1))
        : todayNinePm;
    final end = start.add(const Duration(days: 1));

    Future<List<Map<String, dynamic>>> query(
      PostgrestFilterBuilder builder,
    ) async {
      final rows = await builder.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows);
    }

    final pendingRows = await query(
      client
          .from('additional_requests')
          .select(_additionalRequestColumns)
          .inFilter('status', ['pending', 'pending_inventory']),
    );

    final sentToStoreRows = await query(
      client
          .from('additional_requests')
          .select(_additionalRequestColumns)
          .eq('status', 'sent_to_store'),
    );

    final createdTodayRows = await query(
      client
          .from('additional_requests')
          .select(_additionalRequestColumns)
          .inFilter('status', ['sent_to_store', 'done', 'rejected'])
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String()),
    );

    final inventoryApprovedTodayRows = await query(
      client
          .from('additional_requests')
          .select(_additionalRequestColumns)
          .inFilter('status', ['sent_to_store', 'rejected'])
          .gte('inventory_approved_at', start.toIso8601String())
          .lt('inventory_approved_at', end.toIso8601String()),
    );

    final storeCompletedTodayRows = await query(
      client
          .from('additional_requests')
          .select(_additionalRequestColumns)
          .inFilter('status', ['done', 'rejected'])
          .gte('done_at', start.toIso8601String())
          .lt('done_at', end.toIso8601String()),
    );

    final byId = <String, Map<String, dynamic>>{};
    for (final row in [
      ...pendingRows,
      ...sentToStoreRows,
      ...createdTodayRows,
      ...inventoryApprovedTodayRows,
      ...storeCompletedTodayRows,
    ]) {
      final id = (row['id'] ?? '').toString();
      if (id.isEmpty) continue;
      byId[id] = row;
    }

    final rows = byId.values.toList()
      ..sort((a, b) {
        final ad =
            DateTime.tryParse((a['created_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bd =
            DateTime.tryParse((b['created_at'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });

    return rows;
  }

  Future<List<Map<String, dynamic>>> fetchAdditionalOrderHistory({
    required DateTime from,
    required DateTime to,
  }) async {
    final res = await client
        .from('additional_requests')
        .select(_additionalRequestColumns)
        .gte('created_at', from.toIso8601String())
        .lte('created_at', to.toIso8601String())
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  Future<Map<String, dynamic>> fetchOrderEditAnalysis({
    required DateTime from,
    required DateTime to,
  }) async {
    final fromDate = DateFormat('yyyy-MM-dd').format(from);
    final toDate = DateFormat('yyyy-MM-dd').format(to);

    final res = await client
        .from('order_edits')
        .select('''
          id,
          run_date,
          zone,
          branch_name,
          item_code,
          item_name,
          old_qty,
          new_qty,
          diff,
          reason,
          created_at,
          updated_at,
          updated_by
        ''')
        .gt('diff', 0)
        .gte('run_date', fromDate)
        .lte('run_date', toDate)
        .order('run_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(50000);

    final rows = List<Map<String, dynamic>>.from(
      res,
    ).map(_normalizeOrderEditRow).toList();

    // The edit rows only tell us which products changed. Keep the submission
    // history alongside them so exports can show edited orders out of all
    // submitted orders for each branch in the selected period.
    final submissionRes = await client
        .from('order_submissions')
        .select('branch_name, run_date')
        .eq('status', 'submitted')
        .gte('run_date', fromDate)
        .lte('run_date', toDate);
    final submittedOrders = List<Map<String, dynamic>>.from(submissionRes);

    final totalEdits = rows.length;
    final totalQty = rows.fold<num>(0, (sum, row) => sum + _num(row['diff']));
    final uniqueProducts = rows
        .map(
          (row) => _text(row['item_code']).isEmpty
              ? _text(row['item_name'])
              : _text(row['item_code']),
        )
        .where((value) => value.isNotEmpty)
        .toSet()
        .length;
    final uniqueBranches = rows
        .map((row) => _text(row['branch_name']))
        .where((value) => value.isNotEmpty)
        .toSet()
        .length;
    final maxAddition = rows.fold<num>(
      0,
      (max, row) => _num(row['diff']) > max ? _num(row['diff']) : max,
    );

    int activeBranches = uniqueBranches;
    try {
      final activeRes = await client
          .from('branches')
          .select('branch_name')
          .eq('is_active', true);
      activeBranches = (activeRes as List).length;
    } catch (_) {
      activeBranches = uniqueBranches;
    }

    final topBranches = _buildOrderEditBranches(rows);
    final branchExportRows = _buildOrderEditBranchExportRows(
      rows,
      submittedOrders,
    );
    final topProducts = _buildOrderEditProducts(rows);
    final reasons = _buildOrderEditReasonRows(rows);
    final dailyTrend = _buildOrderEditDailyTrend(rows);
    final zones = _buildOrderEditZoneRows(rows);

    return {
      'total_requests': totalEdits,
      'total_edits': totalEdits,
      'total_qty': totalQty,
      'unique_products': uniqueProducts,
      'unique_branches': uniqueBranches,
      'active_branch_rate': activeBranches == 0
          ? 0
          : (uniqueBranches / activeBranches) * 100,
      'avg_qty': totalEdits == 0 ? 0 : totalQty / totalEdits,
      'max_addition': maxAddition,
      'top_branches': topBranches,
      'branch_export_rows': branchExportRows,
      'top_products': topProducts,
      'branch_performance': topBranches,
      'reasons': reasons,
      'daily_trend': dailyTrend,
      'zone_analysis': zones,
      'rows': rows,
    };
  }

  Map<String, dynamic> _normalizeOrderEditRow(Map<String, dynamic> row) {
    final oldQty = _num(row['old_qty']);
    final newQty = _num(row['new_qty']);
    final diff = _num(row['diff']);

    return {
      ...row,
      'old_qty': oldQty,
      'new_qty': newQty,
      'diff': diff,
      'added_qty': diff,
      'changed_at': row['updated_at'] ?? row['created_at'],
    };
  }

  List<Map<String, dynamic>> _buildOrderEditBranches(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final branch = _text(row['branch_name']);
      if (branch.isEmpty) continue;

      final target = grouped.putIfAbsent(
        branch,
        () => {
          'branch_name': branch,
          'requests': 0,
          'total': 0,
          'qty': 0,
          'products': <String>{},
        },
      );

      target['requests'] = (target['requests'] as int) + 1;
      target['total'] = (target['total'] as int) + 1;
      target['qty'] = (target['qty'] as num) + _num(row['diff']);
      (target['products'] as Set<String>).add(_text(row['item_code']));
    }

    final result = grouped.values.map((row) {
      final products = row['products'] as Set<String>;
      return {
        ...row,
        'products': products.length,
        'avg_qty': (row['requests'] as int) == 0
            ? 0
            : (row['qty'] as num) / (row['requests'] as int),
      };
    }).toList();

    result.sort((a, b) => (_num(b['qty'])).compareTo(_num(a['qty'])));
    return result;
  }

  List<Map<String, dynamic>> _buildOrderEditBranchExportRows(
    List<Map<String, dynamic>> editRows,
    List<Map<String, dynamic>> submittedOrders,
  ) {
    final grouped = <String, Map<String, dynamic>>{};

    for (final order in submittedOrders) {
      final branch = _text(order['branch_name']);
      final runDate = _text(order['run_date']);
      if (branch.isEmpty || runDate.isEmpty) continue;

      final target = grouped.putIfAbsent(
        branch,
        () => {
          'branch_name': branch,
          'order_dates': <String>{},
          'edited_order_dates': <String>{},
          'qty': 0,
          'products': <String>{},
        },
      );
      (target['order_dates'] as Set<String>).add(runDate);
    }

    for (final edit in editRows) {
      final branch = _text(edit['branch_name']);
      final runDate = _text(edit['run_date']);
      if (branch.isEmpty) continue;

      final target = grouped.putIfAbsent(
        branch,
        () => {
          'branch_name': branch,
          'order_dates': <String>{},
          'edited_order_dates': <String>{},
          'qty': 0,
          'products': <String>{},
        },
      );
      if (runDate.isNotEmpty) {
        (target['edited_order_dates'] as Set<String>).add(runDate);
      }
      target['qty'] = (target['qty'] as num) + _num(edit['diff']);
      (target['products'] as Set<String>).add(_text(edit['item_code']));
    }

    final result = grouped.values.map((row) {
      final orderDates = row['order_dates'] as Set<String>;
      final editedOrderDates = row['edited_order_dates'] as Set<String>;
      return {
        'branch_name': row['branch_name'],
        'orders': orderDates.length,
        'edited_orders': editedOrderDates.length,
        'qty': row['qty'],
        'products': (row['products'] as Set<String>).length,
      };
    }).toList();

    result.sort((a, b) {
      final orderComparison = _num(b['orders']).compareTo(_num(a['orders']));
      return orderComparison != 0
          ? orderComparison
          : _text(a['branch_name']).compareTo(_text(b['branch_name']));
    });
    return result;
  }

  List<Map<String, dynamic>> _buildOrderEditProducts(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final itemCode = _text(row['item_code']);
      final itemName = _text(row['item_name']);
      final key = '$itemCode|$itemName';
      final branch = _text(row['branch_name']);

      final target = grouped.putIfAbsent(
        key,
        () => {
          'item_code': itemCode,
          'item_name': itemName,
          'requests': 0,
          'qty': 0,
          'product_branches': <String, Map<String, dynamic>>{},
        },
      );

      target['requests'] = (target['requests'] as int) + 1;
      target['qty'] = (target['qty'] as num) + _num(row['diff']);

      final branchMap =
          target['product_branches'] as Map<String, Map<String, dynamic>>;
      final branchRow = branchMap.putIfAbsent(
        branch,
        () => {'branch_name': branch, 'requests': 0, 'qty': 0},
      );
      branchRow['requests'] = (branchRow['requests'] as int) + 1;
      branchRow['qty'] = (branchRow['qty'] as num) + _num(row['diff']);
    }

    final result = grouped.values.map((row) {
      final branches =
          (row['product_branches'] as Map<String, Map<String, dynamic>>).values
              .toList()
            ..sort((a, b) => _num(b['qty']).compareTo(_num(a['qty'])));
      return {...row, 'product_branches': branches};
    }).toList();

    result.sort((a, b) => (_num(b['qty'])).compareTo(_num(a['qty'])));
    return result;
  }

  List<Map<String, dynamic>> _buildOrderEditReasonRows(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final reason = _text(row['reason']).isEmpty
          ? 'No reason'
          : _text(row['reason']);
      final target = grouped.putIfAbsent(
        reason,
        () => {'reason': reason, 'count': 0, 'qty': 0},
      );
      target['count'] = (target['count'] as int) + 1;
      target['qty'] = (target['qty'] as num) + _num(row['diff']);
    }

    final total = rows.length;
    final result = grouped.values.map((row) {
      return {
        ...row,
        'percent': total == 0 ? 0 : ((row['count'] as int) / total) * 100,
      };
    }).toList();

    result.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
    return result;
  }

  List<Map<String, dynamic>> _buildOrderEditDailyTrend(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final day = _text(row['run_date']);
      if (day.isEmpty) continue;

      final target = grouped.putIfAbsent(
        day,
        () => {'date': day, 'requests': 0, 'qty': 0},
      );
      target['requests'] = (target['requests'] as int) + 1;
      target['qty'] = (target['qty'] as num) + _num(row['diff']);
    }

    final result = grouped.values.toList();
    result.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    return result;
  }

  List<Map<String, dynamic>> _buildOrderEditZoneRows(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final zone = _text(row['zone']).isEmpty ? 'Unknown' : _text(row['zone']);
      final target = grouped.putIfAbsent(
        zone,
        () => {'zone': zone, 'requests': 0, 'qty': 0},
      );
      target['requests'] = (target['requests'] as int) + 1;
      target['qty'] = (target['qty'] as num) + _num(row['diff']);
    }

    final result = grouped.values.toList();
    result.sort((a, b) => _num(b['qty']).compareTo(_num(a['qty'])));
    return result;
  }

  num _num(dynamic value) {
    if (value is num) return value;
    return num.tryParse((value ?? '').toString()) ?? 0;
  }

  String _text(dynamic value) {
    return (value ?? '').toString().trim();
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
        .lt('created_at', end.toIso8601String())
        .count(CountOption.exact);

    return res.count;
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
        .gte('created_at', start.toIso8601String())
        .count(CountOption.exact);

    return res.count;
  }

  /// ===============================
  /// INVENTORY APPROVAL
  /// ===============================

  Future<void> approveInventory({
    required String id,
    required num qty,
    String note = '',
  }) async {
    final status = qty == 0 ? 'rejected' : 'sent_to_store';

    await client
        .from('additional_requests')
        .update({
          'inventory_qty': qty,
          'inventory_note': note,
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
        .gte('created_at', start.toIso8601String())
        .count(CountOption.exact);

    return res.count;
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
        .lt('created_at', end.toIso8601String())
        .count(CountOption.exact);

    return res.count;
  }

  Future<List<Map<String, dynamic>>> fetchMismatch() async {
    List<Map<String, dynamic>> all = [];

    int from = 0;
    const int limit = 10000;

    while (true) {
      final res = await client
          .from('stk_mismatch')
          .select('''
            id,
            branch_name,
            item_code,
            item_name,
            system_stock,
            actual_stock,
            update_date,
            diff,
            created_at
          ''')
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

  Future<List<Map<String, dynamic>>> fetchAllocationBranches() async {
    try {
      final res = await client
          .from('branches')
          .select('''
        branch_name,
        area,
        branch_type
      ''')
          .eq('is_active', true)
          .order('branch_name');

      return List<Map<String, dynamic>>.from(res);
    } on PostgrestException catch (e) {
      if (e.code != '42703' && !e.message.contains('brancy_type')) rethrow;

      final res = await client
          .from('branches')
          .select('''
        branch_name,
        area,
        brancy_type
      ''')
          .eq('is_active', true)
          .order('branch_name');

      return List<Map<String, dynamic>>.from(res).map((row) {
        return {...row, 'branch_type': row['brancy_type']};
      }).toList();
    }
  }

  Future<List<String>> fetchAllocationCategories(String runDate) async {
    final res = await client.rpc(
      'get_allocation_categories',
      params: {'p_run_date': runDate},
    );

    return List<dynamic>.from(res)
        .map((e) {
          if (e is Map<String, dynamic>) {
            return (e['category'] ?? '').toString();
          }
          return e.toString();
        })
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }

  Future<List<String>> fetchAllocationItemStatuses(String runDate) async {
    final res = await client.rpc(
      'get_allocation_item_statuses',
      params: {'p_run_date': runDate},
    );

    return List<dynamic>.from(res)
        .map((e) {
          if (e is Map<String, dynamic>) {
            return (e['item_status'] ?? '').toString();
          }
          return e.toString();
        })
        .where((e) => e.trim().isNotEmpty)
        .toList();
  }

  Future<List<String>> fetchAllocationStockCoverOptions(String runDate) async {
    try {
      final rpcRes = await client.rpc(
        'get_allocation_stock_cover_options',
        params: {'p_run_date': runDate},
      );
      final raw = List<dynamic>.from(rpcRes);
      if (raw.every((e) => e is! Map)) {
        final options = raw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty && !_isNoDemandStockCover(e))
            .toList();
        options.sort(_compareStockCoverLabels);
        return options;
      }
      return _stockCoverOptionsFromRows(List<Map<String, dynamic>>.from(raw));
    } catch (_) {
      // Fallback keeps the page working even before the optional RPC is added.
    }

    final res = await client
        .from('allocation_base')
        .select('stock_cover_text, branch_stock_days')
        .eq('run_date', runDate)
        .order('branch_stock_days', ascending: true)
        .limit(50000);

    return _stockCoverOptionsFromRows(List<Map<String, dynamic>>.from(res));
  }

  List<String> _stockCoverOptionsFromRows(List<Map<String, dynamic>> rows) {
    final orderMap = <String, num>{};
    for (final row in rows) {
      final label = (row['stock_cover_text'] ?? '').toString().trim();
      if (label.isEmpty || _isNoDemandStockCover(label)) continue;

      final days = row['branch_stock_days'] is num
          ? row['branch_stock_days'] as num
          : num.tryParse((row['branch_stock_days'] ?? '0').toString()) ?? 0;
      final current = orderMap[label];
      if (current == null || days < current) {
        orderMap[label] = days;
      }
    }

    final options = orderMap.keys.toList()..sort(_compareStockCoverLabels);

    return options;
  }

  bool _isNoDemandStockCover(String label) {
    return label.trim().toLowerCase() == 'no demand';
  }

  int _stockCoverGroup(String label) {
    final text = label.trim().toLowerCase();
    if (text.contains('no stock')) return 0;
    if (text.contains('less than')) return 1;
    if (text.contains('day')) return 2;
    if (text.contains('week')) return 3;
    if (text.contains('month')) return 4;
    if (text.contains('year')) return 5;
    return 9;
  }

  num _stockCoverUnitValue(String label) {
    final text = label.trim().toLowerCase();
    if (text.contains('no stock')) return 0;
    if (text.contains('less than')) return 0.5;
    return num.tryParse(
          RegExp(r'\d+(\.\d+)?').firstMatch(text)?.group(0) ?? '',
        ) ??
        0;
  }

  int _compareStockCoverLabels(String a, String b) {
    final groupCompare = _stockCoverGroup(a).compareTo(_stockCoverGroup(b));
    if (groupCompare != 0) return groupCompare;

    final valueCompare = _stockCoverUnitValue(
      a,
    ).compareTo(_stockCoverUnitValue(b));
    if (valueCompare != 0) return valueCompare;

    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  Future<List<Map<String, dynamic>>> fetchAllocationResults({
    required String runDate,
    required List<String> donorBranches,
    required List<String> receiverBranches,
    required List<String> priorityBranches,
    required List<String> categories,
    required List<String> itemStatuses,
  }) async {
    final res = await client.rpc(
      'get_inventory_allocation',
      params: {
        'p_run_date': runDate,
        'p_donor_branches': donorBranches,
        'p_receiver_branches': receiverBranches,
        'p_priority_branches': priorityBranches,
        'p_categories': categories,
        'p_item_statuses': itemStatuses,
      },
    );

    return List<Map<String, dynamic>>.from(res);
  }

  Future<void> sendBranchAllocationTasks({
    required String runDate,
    required String batchId,
    required DateTime expiresAt,
    required List<Map<String, dynamic>> rows,
  }) async {
    if (rows.isEmpty) return;

    final now = DateTime.now().toIso8601String();
    final payload = rows.map((row) {
      return {
        'batch_id': batchId,
        'run_date': runDate,
        'from_branch': (row['from_branch'] ?? '').toString(),
        'to_branch': (row['to_branch'] ?? '').toString(),
        'item_code': (row['item_code'] ?? '').toString(),
        'item_name': (row['item_name'] ?? '').toString(),
        'qty': row['qty'] ?? 0,
        'qty_send': row['qty'] ?? 0,
        'category': (row['category'] ?? '').toString(),
        'sender_status': 'pending',
        'receiver_status': 'pending',
        'sent_at': now,
        'expires_at': expiresAt.toIso8601String(),
        'updated_at': now,
      };
    }).toList();

    await client
        .from('branch_allocation_tasks')
        .delete()
        .eq('run_date', runDate);
    await client.from('branch_allocation_tasks').insert(payload);
  }

  Future<List<Map<String, dynamic>>> fetchSentBranchAllocationTasks({
    required String runDate,
  }) async {
    final res = await client
        .from('branch_allocation_tasks')
        .select()
        .eq('run_date', runDate)
        .order('sent_at', ascending: false);

    return List<Map<String, dynamic>>.from(res);
  }

  Future<List<Map<String, dynamic>>> fetchAllocationSourceRows({
    required String runDate,
    required List<String> donorBranches,
    required List<String> receiverBranches,
    required List<String> categories,
    required List<String> itemStatuses,
    void Function(int loaded)? onProgress,
  }) async {
    const cols = '''
branch,
item_code,
item_name,
category,
item_purchase_type,
extra_qty,
reorder_qty,
final_reorder_qty,
shortage,
branch_stock,
demand_for_30_days,
branch_stock_days,
stock_cover_text
''';
    const batchSize = 10000;
    final all = <Map<String, dynamic>>[];
    final neededBranches = <String>{...donorBranches, ...receiverBranches};
    const noSelection = '__NO_ALLOCATION_SELECTION__';

    if (neededBranches.contains(noSelection) ||
        categories.contains(noSelection) ||
        itemStatuses.contains(noSelection)) {
      return all;
    }

    var from = 0;

    while (true) {
      var query = client
          .from('allocation_base')
          .select(cols)
          .eq('run_date', runDate);

      if (neededBranches.isNotEmpty) {
        query = query.inFilter('branch', neededBranches.toList());
      }

      if (categories.isNotEmpty) {
        query = query.inFilter('category', categories);
      }

      if (itemStatuses.isNotEmpty) {
        query = query.inFilter('item_purchase_type', itemStatuses);
      }

      final res = await query.range(from, from + batchSize - 1);
      final rows = List<Map<String, dynamic>>.from(res);
      all.addAll(rows);
      onProgress?.call(all.length);

      if (rows.length < batchSize) break;
      from += batchSize;
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

      final response = await client
          .from('max_adj')
          .select(cols)
          .or(filter)
          .order('created_at', ascending: false)
          .order('item_code', ascending: true)
          .range(from, to)
          .count(CountOption.exact);

      return {
        'rows': List<Map<String, dynamic>>.from(response.data),
        'total': response.count,
      };
    }

    final response = await client
        .from('max_adj')
        .select(cols)
        .order('created_at', ascending: false)
        .order('item_code', ascending: true)
        .range(from, to)
        .count(CountOption.exact);

    return {
      'rows': List<Map<String, dynamic>>.from(response.data),
      'total': response.count,
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

  Future<List<String>> fetchDailyOrderExportDates() async {
    final res = await client
        .from('daily_order_exports')
        .select('run_date')
        .eq('status', 'done')
        .order('run_date', ascending: false);

    return (res as List)
        .map((e) => (e['run_date'] ?? '').toString())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<String?> fetchDailyOrderExportFileUrl({
    required String runDate,
  }) async {
    final row = await client
        .from('daily_order_exports')
        .select('storage_path')
        .eq('run_date', runDate)
        .eq('status', 'done')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (row == null) return null;

    final storagePath = row['storage_path']?.toString().trim();
    if (storagePath == null || storagePath.isEmpty) return null;

    return client.storage
        .from('daily-order-exports')
        .createSignedUrl(storagePath, 60);
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

  Future<Map<String, dynamic>> fetchOrderEditSalesPerformance({
    required DateTime from,
    required DateTime to,
    String? branch,
  }) async {
    final fromDate = DateFormat('yyyy-MM-dd').format(from);
    final toDate = DateFormat('yyyy-MM-dd').format(to);

    var query = client
        .from('order_edits')
        .select('''
          id,
          run_date,
          zone,
          branch_name,
          item_code,
          item_name,
          old_qty,
          new_qty,
          diff,
          reason,
          created_at,
          updated_at,
          updated_by
        ''')
        .gt('diff', 0)
        .gte('run_date', fromDate)
        .lte('run_date', toDate);

    final selectedBranch = _text(branch);
    if (selectedBranch.isNotEmpty && selectedBranch != 'All Branches') {
      query = query.eq('branch_name', selectedBranch);
    }

    final editRes = await query
        .order('run_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(50000);

    final edits = List<Map<String, dynamic>>.from(
      editRes,
    ).map(_normalizeOrderEditRow).toList();

    if (edits.isEmpty) {
      return _emptyOrderEditSalesPerformance();
    }

    final itemsByBranch = <String, Set<String>>{};
    for (final row in edits) {
      final rowBranch = _text(row['branch_name']);
      final itemCode = _text(row['item_code']);
      if (rowBranch.isEmpty || itemCode.isEmpty) continue;
      itemsByBranch.putIfAbsent(rowBranch, () => <String>{}).add(itemCode);
    }

    final salesRows = await _fetchOrderEditSalesRows(
      itemsByBranch: itemsByBranch,
      fromDate: fromDate,
      toDate: DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );

    final salesByPair = <String, List<Map<String, dynamic>>>{};
    for (final row in salesRows) {
      final key = _orderEditPairKey(row['branch_name'], row['item_code']);
      if (key == '|') continue;
      salesByPair.putIfAbsent(key, () => []).add(row);
    }

    for (final rows in salesByPair.values) {
      rows.sort((a, b) {
        final ad = _dateOnly(a['inv_date']);
        final bd = _dateOnly(b['inv_date']);
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });
    }

    final today = _dateOnly(DateTime.now())!;
    final enrichedRows = <Map<String, dynamic>>[];

    for (final edit in edits) {
      final requestDate =
          _dateOnly(edit['run_date']) ??
          _dateOnly(edit['changed_at']) ??
          _dateOnly(from)!;
      final requestQty = _num(edit['diff']);
      final key = _orderEditPairKey(edit['branch_name'], edit['item_code']);
      final pairSales = salesByPair[key] ?? const <Map<String, dynamic>>[];

      num totalSoldQty = 0;
      var saleCount = 0;
      DateTime? firstSaleDate;
      DateTime? lastSaleDate;
      final sellingDays = <String>{};

      for (final sale in pairSales) {
        final saleDate = _dateOnly(sale['inv_date']);
        if (saleDate == null || saleDate.isBefore(requestDate)) continue;

        final qty = _num(sale['qty']);
        if (qty <= 0) continue;

        totalSoldQty += qty;
        saleCount++;
        sellingDays.add(_formatDateOnly(saleDate));
        firstSaleDate ??= saleDate;
        lastSaleDate = saleDate;
      }

      var daysElapsed = today.difference(requestDate).inDays;
      if (daysElapsed < 0) daysElapsed = 0;

      int? daysToFirstSale;
      var daysWithoutSale = daysElapsed;
      var effectivenessStatus = 'not_sold';

      if (firstSaleDate != null) {
        daysToFirstSale = firstSaleDate.difference(requestDate).inDays;
        if (daysToFirstSale < 0) daysToFirstSale = 0;
        daysWithoutSale = daysToFirstSale;
        effectivenessStatus = daysToFirstSale <= 3
            ? 'sold_within_3d'
            : 'sold_after_3d';
      }

      var soldPct = requestQty <= 0 ? 0 : (totalSoldQty / requestQty) * 100;
      if (soldPct > 100) soldPct = 100;
      final remainingAddedQty = requestQty - totalSoldQty;
      final safeRemainingAddedQty = remainingAddedQty > 0
          ? remainingAddedQty
          : 0;
      final monitoringStatus = totalSoldQty <= 0
          ? 'not_sold'
          : safeRemainingAddedQty > 0
          ? 'partially_sold'
          : 'sold';

      enrichedRows.add({
        ...edit,
        'id': _text(edit['id']),
        'request_date': _formatDateOnly(requestDate),
        'request_qty': requestQty,
        'total_sold_qty': totalSoldQty,
        'remaining_added_qty': safeRemainingAddedQty,
        'sale_count': saleCount,
        'first_sale_date': firstSaleDate == null
            ? null
            : _formatDateOnly(firstSaleDate),
        'last_sale_date': lastSaleDate == null
            ? null
            : _formatDateOnly(lastSaleDate),
        'monitoring_status': monitoringStatus,
        'monitoring_label': _orderEditMonitoringLabel(monitoringStatus),
        'status': 'order_edit',
        'days_elapsed': daysElapsed,
        'days_to_first_sale': daysToFirstSale,
        'days_without_sale': daysWithoutSale,
        'selling_days': sellingDays.length,
        'effectiveness_status': effectivenessStatus,
        'effectiveness_label': _effectivenessLabel(effectivenessStatus),
        'sold_pct': soldPct,
      });
    }

    return {
      'summary': _buildOrderEditSalesSummary(enrichedRows),
      'rows': enrichedRows,
      'branch_effectiveness': _buildOrderEditBranchEffectiveness(enrichedRows),
      'product_effectiveness': _buildOrderEditProductEffectiveness(
        enrichedRows,
      ),
      'weekly_trend': _buildOrderEditWeeklyTrend(enrichedRows),
    };
  }

  Future<List<Map<String, dynamic>>> _fetchOrderEditSalesRows({
    required Map<String, Set<String>> itemsByBranch,
    required String fromDate,
    required String toDate,
  }) async {
    const chunkSize = 250;
    const pageSize = 5000;
    final rows = <Map<String, dynamic>>[];

    for (final entry in itemsByBranch.entries) {
      final branch = entry.key;
      final items = entry.value.where((e) => e.trim().isNotEmpty).toList();
      if (branch.trim().isEmpty || items.isEmpty) continue;

      for (var i = 0; i < items.length; i += chunkSize) {
        final end = i + chunkSize > items.length ? items.length : i + chunkSize;
        final part = items.sublist(i, end);
        var from = 0;

        while (true) {
          final res = await client
              .from('sales_last_45_days')
              .select('branch_name,item_code,qty,inv_date')
              .eq('branch_name', branch)
              .inFilter('item_code', part)
              .gte('inv_date', fromDate)
              .lte('inv_date', toDate)
              .order('inv_date', ascending: true)
              .range(from, from + pageSize - 1);

          final batch = List<Map<String, dynamic>>.from(res);
          rows.addAll(batch);
          if (batch.length < pageSize) break;
          from += pageSize;
        }
      }
    }

    return rows;
  }

  Future<List<Map<String, dynamic>>> fetchPurchaseShortage({
    required String runDate,
  }) async {
    try {
      final res = await client.rpc(
        'get_purchase_shortage',
        params: {'p_run_date': runDate},
      );
      final rows = List<Map<String, dynamic>>.from(res as List);
      rows.sort((a, b) => _num(b['shortage']).compareTo(_num(a['shortage'])));
      return rows;
    } catch (e) {
      throw Exception(
        'Purchase Shortage must use Supabase RPC only. '
        'Please run supabase/sql/purchase_shortage_rpc.sql in Supabase, '
        'especially get_purchase_shortage. Details: $e',
      );
    }
  }

  Future<int> forEachPurchaseShortageBranchStock({
    required String runDate,
    required FutureOr<void> Function(Map<String, dynamic> row) onRow,
  }) async {
    const batchSize = 50000;
    var offset = 0;
    var count = 0;

    try {
      while (true) {
        final res = await client.rpc(
          'get_purchase_shortage_branch_stock_rows',
          params: {
            'p_run_date': runDate,
            'p_limit': batchSize,
            'p_offset': offset,
          },
        );

        final batch = List<Map<String, dynamic>>.from(res as List);
        if (batch.isEmpty) break;

        for (final row in batch) {
          await onRow({
            'branch': _text(row['branch']),
            'item_code': _text(row['item_code']),
            'item_name': _text(row['item_name']),
            'branch_stock': _num(row['branch_stock']),
          });
          count++;
        }

        if (batch.length < batchSize) break;

        offset += batchSize;
        await Future<void>.delayed(Duration.zero);
      }

      return count;
    } catch (e) {
      throw Exception(
        'Purchase Shortage export must use Supabase RPC only. '
        'Please run supabase/sql/purchase_shortage_rpc.sql in Supabase, '
        'especially get_purchase_shortage_branch_stock_rows. Details: $e',
      );
    }
  }

  Future<List<Map<String, dynamic>>> fetchPurchaseShortageBranchStockMatrix({
    required String runDate,
  }) async {
    try {
      final res = await client.rpc(
        'get_purchase_shortage_branch_stock_matrix',
        params: {'p_run_date': runDate},
      );

      final rows = List<Map<String, dynamic>>.from(res as List);
      return rows.map(_mapBranchStockMatrixRow).toList();
    } catch (_) {
      return _fetchPurchaseShortageBranchStockMatrixFallback(runDate: runDate);
    }
  }

  Future<List<Map<String, dynamic>>>
  _fetchPurchaseShortageBranchStockMatrixFallback({
    required String runDate,
  }) async {
    final byItem = <String, Map<String, dynamic>>{};

    await forEachPurchaseShortageBranchStock(
      runDate: runDate,
      onRow: (row) {
        final itemCode = _text(row['item_code']);
        if (itemCode.isEmpty) return;

        final item = byItem.putIfAbsent(
          itemCode,
          () => {
            'item_code': itemCode,
            'item_name': _text(row['item_name']),
            'stocks': <String, num>{},
          },
        );

        final branch = _text(row['branch']);
        if (branch.isNotEmpty) {
          (item['stocks'] as Map<String, num>)[branch] = _num(
            row['branch_stock'],
          );
        }
      },
    );

    final rows = byItem.values.toList();
    rows.sort((a, b) => _text(a['item_code']).compareTo(_text(b['item_code'])));
    return rows;
  }

  Map<String, dynamic> _mapBranchStockMatrixRow(Map<String, dynamic> row) {
    final rawStocks = row['stock_by_branch'] ?? row['stocks'];
    final stocks = <String, num>{};

    if (rawStocks is Map) {
      rawStocks.forEach((key, value) {
        final branch = _text(key);
        if (branch.isNotEmpty) stocks[branch] = _num(value);
      });
    }

    return {
      'item_code': _text(row['item_code']),
      'item_name': _text(row['item_name']),
      'stocks': stocks,
    };
  }

  Map<String, dynamic> _emptyOrderEditSalesPerformance() {
    return {
      'summary': {
        'total_requests': 0,
        'sold_within_3d': 0,
        'sold_after_3d': 0,
        'not_sold': 0,
        'effectiveness_rate': 0,
        'quick_sell_rate': 0,
        'avg_days_to_first_sale': null,
        'avg_sold_pct': 0,
        'total_added_qty': 0,
        'total_sold_qty': 0,
        'remaining_added_qty': 0,
        'sale_count': 0,
      },
      'rows': <Map<String, dynamic>>[],
      'branch_effectiveness': <Map<String, dynamic>>[],
      'product_effectiveness': <Map<String, dynamic>>[],
      'weekly_trend': <Map<String, dynamic>>[],
    };
  }

  Map<String, dynamic> _buildOrderEditSalesSummary(
    List<Map<String, dynamic>> rows,
  ) {
    final total = rows.length;
    final soldWithin = rows
        .where((row) => row['effectiveness_status'] == 'sold_within_3d')
        .length;
    final soldAfter = rows
        .where((row) => row['effectiveness_status'] == 'sold_after_3d')
        .length;
    final notSold = rows
        .where((row) => row['effectiveness_status'] == 'not_sold')
        .length;

    final dayValues = rows
        .map((row) => row['days_to_first_sale'])
        .whereType<num>()
        .toList();
    final soldPctTotal = rows.fold<num>(
      0,
      (sum, row) => sum + _num(row['sold_pct']),
    );
    final totalAddedQty = rows.fold<num>(
      0,
      (sum, row) => sum + _num(row['request_qty']),
    );
    final totalSoldQty = rows.fold<num>(
      0,
      (sum, row) => sum + _num(row['total_sold_qty']),
    );
    final remainingAddedQty = rows.fold<num>(
      0,
      (sum, row) => sum + _num(row['remaining_added_qty']),
    );
    final saleCount = rows.fold<num>(
      0,
      (sum, row) => sum + _num(row['sale_count']),
    );

    return {
      'total_requests': total,
      'sold_within_3d': soldWithin,
      'sold_after_3d': soldAfter,
      'not_sold': notSold,
      'effectiveness_rate': total == 0
          ? 0
          : ((soldWithin + soldAfter) / total) * 100,
      'quick_sell_rate': total == 0 ? 0 : (soldWithin / total) * 100,
      'avg_days_to_first_sale': dayValues.isEmpty
          ? null
          : dayValues.fold<num>(0, (sum, value) => sum + value) /
                dayValues.length,
      'avg_sold_pct': total == 0 ? 0 : soldPctTotal / total,
      'total_added_qty': totalAddedQty,
      'total_sold_qty': totalSoldQty,
      'remaining_added_qty': remainingAddedQty,
      'sale_count': saleCount,
    };
  }

  List<Map<String, dynamic>> _buildOrderEditBranchEffectiveness(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final branch = _text(row['branch_name']);
      if (branch.isEmpty) continue;

      final target = grouped.putIfAbsent(
        branch,
        () => {
          'branch_name': branch,
          'total_requests': 0,
          'sold_within_3d': 0,
          'sold_after_3d': 0,
          'not_sold': 0,
          'total_request_qty': 0,
          'total_sold_qty': 0,
          'remaining_added_qty': 0,
          'sale_count': 0,
          'products_count': <String>{},
          'last_sale_date': null,
          'products': <Map<String, dynamic>>[],
          '_days_sum': 0,
          '_days_count': 0,
        },
      );

      target['total_requests'] = (target['total_requests'] as int) + 1;
      target['total_request_qty'] =
          (target['total_request_qty'] as num) + _num(row['request_qty']);
      target['total_sold_qty'] =
          (target['total_sold_qty'] as num) + _num(row['total_sold_qty']);
      target['remaining_added_qty'] =
          (target['remaining_added_qty'] as num) +
          _num(row['remaining_added_qty']);
      target['sale_count'] =
          (target['sale_count'] as num) + _num(row['sale_count']);
      (target['products_count'] as Set<String>).add(_text(row['item_code']));
      final lastSaleDate = _dateOnly(row['last_sale_date']);
      final currentLastSaleDate = _dateOnly(target['last_sale_date']);
      if (lastSaleDate != null &&
          (currentLastSaleDate == null ||
              lastSaleDate.isAfter(currentLastSaleDate))) {
        target['last_sale_date'] = _formatDateOnly(lastSaleDate);
      }

      final status = _text(row['effectiveness_status']);
      if (status == 'sold_within_3d') {
        target['sold_within_3d'] = (target['sold_within_3d'] as int) + 1;
      } else if (status == 'sold_after_3d') {
        target['sold_after_3d'] = (target['sold_after_3d'] as int) + 1;
      } else {
        target['not_sold'] = (target['not_sold'] as int) + 1;
      }

      final daysToFirstSale = row['days_to_first_sale'];
      if (daysToFirstSale is num) {
        target['_days_sum'] = (target['_days_sum'] as num) + daysToFirstSale;
        target['_days_count'] = (target['_days_count'] as int) + 1;
      }

      (target['products'] as List<Map<String, dynamic>>).add({
        'item_code': row['item_code'],
        'item_name': row['item_name'],
        'request_qty': row['request_qty'],
        'total_sold_qty': row['total_sold_qty'],
        'remaining_added_qty': row['remaining_added_qty'],
        'sale_count': row['sale_count'],
        'request_date': row['request_date'],
        'first_sale_date': row['first_sale_date'],
        'last_sale_date': row['last_sale_date'],
        'monitoring_label': row['monitoring_label'],
        'days_elapsed': row['days_elapsed'],
        'days_to_first_sale': row['days_to_first_sale'],
        'effectiveness_status': row['effectiveness_status'],
      });
    }

    final result = grouped.values.map((row) {
      final total = row['total_requests'] as int;
      final soldWithin = row['sold_within_3d'] as int;
      final soldAfter = row['sold_after_3d'] as int;
      final daysCount = row['_days_count'] as int;
      return {
        'branch_name': row['branch_name'],
        'total_requests': total,
        'sold_within_3d': soldWithin,
        'sold_after_3d': soldAfter,
        'not_sold': row['not_sold'],
        'total_request_qty': row['total_request_qty'],
        'total_sold_qty': row['total_sold_qty'],
        'remaining_added_qty': row['remaining_added_qty'],
        'sale_count': row['sale_count'],
        'products_count': (row['products_count'] as Set<String>).length,
        'last_sale_date': row['last_sale_date'],
        'effectiveness_rate': total == 0
            ? 0
            : ((soldWithin + soldAfter) / total) * 100,
        'quick_sell_rate': total == 0 ? 0 : (soldWithin / total) * 100,
        'avg_days_to_first_sale': daysCount == 0
            ? null
            : (row['_days_sum'] as num) / daysCount,
        'products': row['products'],
      };
    }).toList();

    result.sort(
      (a, b) => _num(
        b['effectiveness_rate'],
      ).compareTo(_num(a['effectiveness_rate'])),
    );
    return result;
  }

  List<Map<String, dynamic>> _buildOrderEditProductEffectiveness(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final itemCode = _text(row['item_code']);
      final itemName = _text(row['item_name']);
      final key = '$itemCode|$itemName';

      final target = grouped.putIfAbsent(
        key,
        () => {
          'item_code': itemCode,
          'item_name': itemName,
          'total_requests': 0,
          'total_request_qty': 0,
          'total_sold_qty': 0,
          'remaining_added_qty': 0,
          'sale_count': 0,
          'sold_within_3d': 0,
          'sold_after_3d': 0,
          'not_sold': 0,
          'branches': <String, Map<String, dynamic>>{},
        },
      );

      target['total_requests'] = (target['total_requests'] as int) + 1;
      target['total_request_qty'] =
          (target['total_request_qty'] as num) + _num(row['request_qty']);
      target['total_sold_qty'] =
          (target['total_sold_qty'] as num) + _num(row['total_sold_qty']);
      target['remaining_added_qty'] =
          (target['remaining_added_qty'] as num) +
          _num(row['remaining_added_qty']);
      target['sale_count'] =
          (target['sale_count'] as num) + _num(row['sale_count']);

      final status = _text(row['effectiveness_status']);
      if (status == 'sold_within_3d') {
        target['sold_within_3d'] = (target['sold_within_3d'] as int) + 1;
      } else if (status == 'sold_after_3d') {
        target['sold_after_3d'] = (target['sold_after_3d'] as int) + 1;
      } else {
        target['not_sold'] = (target['not_sold'] as int) + 1;
      }

      final branches = target['branches'] as Map<String, Map<String, dynamic>>;
      final branchName = _text(row['branch_name']);
      final branchRow = branches.putIfAbsent(
        branchName,
        () => {
          'branch_name': branchName,
          'request_qty': 0,
          'total_sold_qty': 0,
          'remaining_added_qty': 0,
          'sale_count': 0,
          'request_date': row['request_date'],
          'first_sale_date': row['first_sale_date'],
          'last_sale_date': row['last_sale_date'],
          'monitoring_label': row['monitoring_label'],
          'days_elapsed': 0,
          'days_to_first_sale': null,
          'effectiveness_status': 'not_sold',
        },
      );

      branchRow['request_qty'] =
          (branchRow['request_qty'] as num) + _num(row['request_qty']);
      branchRow['total_sold_qty'] =
          (branchRow['total_sold_qty'] as num) + _num(row['total_sold_qty']);
      branchRow['remaining_added_qty'] =
          (branchRow['remaining_added_qty'] as num) +
          _num(row['remaining_added_qty']);
      branchRow['sale_count'] =
          (branchRow['sale_count'] as num) + _num(row['sale_count']);
      branchRow['days_elapsed'] = _maxNum(
        branchRow['days_elapsed'],
        row['days_elapsed'],
      );
      branchRow['days_to_first_sale'] = _minNullableNum(
        branchRow['days_to_first_sale'],
        row['days_to_first_sale'],
      );
      branchRow['effectiveness_status'] = _bestEffectivenessStatus(
        _text(branchRow['effectiveness_status']),
        status,
      );
      final lastSaleDate = _dateOnly(row['last_sale_date']);
      final currentLastSaleDate = _dateOnly(branchRow['last_sale_date']);
      if (lastSaleDate != null &&
          (currentLastSaleDate == null ||
              lastSaleDate.isAfter(currentLastSaleDate))) {
        branchRow['last_sale_date'] = _formatDateOnly(lastSaleDate);
      }
    }

    final result = grouped.values.map((row) {
      final total = row['total_requests'] as int;
      final soldWithin = row['sold_within_3d'] as int;
      final soldAfter = row['sold_after_3d'] as int;
      final notSold = row['not_sold'] as int;
      final requestQty = _num(row['total_request_qty']);
      final soldQty = _num(row['total_sold_qty']);
      final effectivenessRate = total == 0
          ? 0
          : ((soldWithin + soldAfter) / total) * 100;

      final branchRows =
          (row['branches'] as Map<String, Map<String, dynamic>>).values.toList()
            ..sort(
              (a, b) => _num(
                b['total_sold_qty'],
              ).compareTo(_num(a['total_sold_qty'])),
            );

      return {
        'item_code': row['item_code'],
        'item_name': row['item_name'],
        'requests': total,
        'qty': requestQty,
        'sales_rate': effectivenessRate,
        'not_sold_rate': total == 0 ? 0 : (notSold / total) * 100,
        'total_requests': total,
        'total_request_qty': requestQty,
        'total_sold_qty': soldQty,
        'remaining_added_qty': row['remaining_added_qty'],
        'sale_count': row['sale_count'],
        'sold_within_3d': soldWithin,
        'sold_after_3d': soldAfter,
        'not_sold': notSold,
        'effectiveness_rate': effectivenessRate,
        'sold_pct': requestQty <= 0 ? 0 : (soldQty / requestQty) * 100,
        'branches': branchRows,
      };
    }).toList();

    result.sort(
      (a, b) =>
          _num(b['total_request_qty']).compareTo(_num(a['total_request_qty'])),
    );
    return result;
  }

  List<Map<String, dynamic>> _buildOrderEditWeeklyTrend(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final requestDate = _dateOnly(row['request_date']);
      if (requestDate == null) continue;

      final weekStart = requestDate.subtract(
        Duration(days: requestDate.weekday - 1),
      );
      final week = _formatDateOnly(weekStart);
      final target = grouped.putIfAbsent(
        week,
        () => {
          'week': week,
          'total': 0,
          'sold_3d': 0,
          'sold_after_3d': 0,
          'not_sold': 0,
        },
      );

      target['total'] = (target['total'] as int) + 1;
      final status = _text(row['effectiveness_status']);
      if (status == 'sold_within_3d') {
        target['sold_3d'] = (target['sold_3d'] as int) + 1;
      } else if (status == 'sold_after_3d') {
        target['sold_after_3d'] = (target['sold_after_3d'] as int) + 1;
      } else {
        target['not_sold'] = (target['not_sold'] as int) + 1;
      }
    }

    final result = grouped.values.map((row) {
      final total = row['total'] as int;
      final sold3 = row['sold_3d'] as int;
      final soldAfter = row['sold_after_3d'] as int;
      return {
        ...row,
        'effectiveness_rate': total == 0
            ? 0
            : ((sold3 + soldAfter) / total) * 100,
      };
    }).toList();

    result.sort((a, b) => _text(a['week']).compareTo(_text(b['week'])));
    return result;
  }

  String _orderEditPairKey(dynamic branch, dynamic itemCode) {
    return '${_text(branch)}|${_text(itemCode)}';
  }

  String _orderEditMonitoringLabel(String value) {
    switch (value) {
      case 'sold':
        return 'Sold';
      case 'partially_sold':
        return 'Partially Sold';
      case 'not_sold':
        return 'Not Sold';
      default:
        return 'Unknown';
    }
  }

  DateTime? _dateOnly(dynamic value) {
    if (value is DateTime) {
      return DateTime(value.year, value.month, value.day);
    }

    final parsed = DateTime.tryParse(_text(value));
    if (parsed == null) return null;
    final local = parsed.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  String _formatDateOnly(DateTime value) {
    return DateFormat('yyyy-MM-dd').format(value);
  }

  String _effectivenessLabel(String status) {
    switch (status) {
      case 'sold_within_3d':
        return 'Sold <= 3 Days';
      case 'sold_after_3d':
        return 'Sold > 3 Days';
      default:
        return 'Not Sold';
    }
  }

  num _maxNum(dynamic a, dynamic b) {
    final av = _num(a);
    final bv = _num(b);
    return av > bv ? av : bv;
  }

  num? _minNullableNum(dynamic a, dynamic b) {
    final bv = b is num ? b : num.tryParse(_text(b));
    if (bv == null) return a is num ? a : num.tryParse(_text(a));

    final av = a is num ? a : num.tryParse(_text(a));
    if (av == null) return bv;
    return av < bv ? av : bv;
  }

  String _bestEffectivenessStatus(String current, String next) {
    if (current == 'sold_within_3d' || next == 'sold_within_3d') {
      return 'sold_within_3d';
    }
    if (current == 'sold_after_3d' || next == 'sold_after_3d') {
      return 'sold_after_3d';
    }
    return 'not_sold';
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
      final response = await client
          .from('branch_formulary')
          .select(cols)
          .or(
            'item_code.ilike.%$safe%,item_name.ilike.%$safe%,branch_name.ilike.%$safe%',
          )
          .order('revised_date', ascending: false)
          .order('item_code', ascending: true)
          .range(from, to)
          .count(CountOption.exact);

      return {
        'rows': List<Map<String, dynamic>>.from(response.data),
        'total': response.count,
      };
    }

    final response = await client
        .from('branch_formulary')
        .select(cols)
        .order('revised_date', ascending: false)
        .order('item_code', ascending: true)
        .range(from, to)
        .count(CountOption.exact);

    return {
      'rows': List<Map<String, dynamic>>.from(response.data),
      'total': response.count,
    };
  }
}
