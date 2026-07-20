import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

class AvailabilityKpiRemoteDs {
  static const _batchSize = 2000;
  static const statusCoveredIds = <int>{1, 2, 5, 7, 8, 34};

  final SupabaseClient client;
  Future<Map<String, _PurchaseStatus>>? _purchaseStatusesFuture;

  AvailabilityKpiRemoteDs(this.client);

  void invalidatePurchaseStatuses() => _purchaseStatusesFuture = null;

  static const _masterColumns = '''
branch_name,item_code,item_name,master_source,in_pareto,in_consistent,
recent_sales,recent_sales_share,cumulative_sales_share,total_sales,
branch_recent_sales,
selling_months,total_months,month_consistency,recent_selling_months,
weekly_need,analysis_start,recent_start,as_of_date
''';
  static const _summaryColumns = '''
branch_name,item_code,in_pareto,in_consistent,recent_sales,weekly_need
''';

  /// Uses the newest stock snapshot that actually exists in daily_order.
  /// The dashboard operational date can lag behind the generated stock file.
  Future<String> fetchLatestStockDate({required String fallback}) async {
    final response = await client
        .from('daily_order')
        .select('run_date')
        .order('run_date', ascending: false)
        .limit(1);
    final rows = List<Map<String, dynamic>>.from(response as List);
    if (rows.isEmpty) return fallback;
    final latest = _text(rows.first['run_date']);
    return latest.isEmpty ? fallback : latest;
  }

  Future<List<String>> fetchActiveBranches() async {
    final response = await client
        .from('branches')
        .select('branch_name')
        .eq('is_active', true)
        .order('branch_name');

    final branches = List<Map<String, dynamic>>.from(response as List)
        .map((row) => _text(row['branch_name']))
        .where((branch) => branch.isNotEmpty)
        .toSet()
        .toList();
    branches.sort(
      (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
    );
    return branches;
  }

  /// Loads two simple, indexed datasets and calculates the KPI locally.
  ///
  /// No database RPC, JOIN, GROUP BY, or window calculation is executed while
  /// opening the page. This keeps the request below PostgREST's statement
  /// timeout even when the overall daily_order table is very large.
  Future<AvailabilityBranchData> fetchBranchData({
    required String runDate,
    required String branch,
  }) async {
    final masterRows = await _fetchMasterRows(branch);
    if (masterRows.isEmpty) {
      return AvailabilityBranchData(
        summary: AvailabilityBranchSummary.empty(branch),
        items: const [],
      );
    }

    final purchaseStatuses = await _fetchPurchaseStatuses();
    final inventory = await _fetchInventoryMap(
      runDate: runDate,
      branch: branch,
    );
    if (inventory.isEmpty) {
      throw StateError(
        'No stock snapshot found for $branch on $runDate in daily_order.',
      );
    }
    return _buildBranchData(
      branch: branch,
      masterRows: masterRows,
      inventory: inventory,
      purchaseStatuses: purchaseStatuses,
    );
  }

  /// Loads the remaining branch summaries from two paged result sets instead
  /// of issuing separate master and stock requests for every branch.
  Future<Map<String, AvailabilityBranchSummary>> fetchBranchSummaries({
    required String runDate,
    required Iterable<String> branches,
  }) async {
    final requested = branches.map((value) => value.trim()).toSet();
    if (requested.isEmpty) return const {};

    final results = await Future.wait<dynamic>([
      _fetchAllMasterRows(requested),
      _fetchAllInventory(runDate: runDate, branches: requested),
      _fetchPurchaseStatuses(),
    ]);
    final masterByBranch =
        results[0] as Map<String, List<Map<String, dynamic>>>;
    final inventoryByBranch =
        results[1] as Map<String, Map<String, _ItemInventory>>;
    final purchaseStatuses = results[2] as Map<String, _PurchaseStatus>;
    final summaries = <String, AvailabilityBranchSummary>{};

    for (final branch in requested) {
      final masterRows = masterByBranch[branch] ?? const [];
      final inventory = inventoryByBranch[branch] ?? const {};
      if (masterRows.isEmpty || inventory.isEmpty) continue;
      summaries[branch] = _buildBranchSummary(
        branch: branch,
        masterRows: masterRows,
        inventory: inventory,
        purchaseStatuses: purchaseStatuses,
      );
    }
    return summaries;
  }

  AvailabilityBranchSummary _buildBranchSummary({
    required String branch,
    required List<Map<String, dynamic>> masterRows,
    required Map<String, _ItemInventory> inventory,
    required Map<String, _PurchaseStatus> purchaseStatuses,
  }) {
    num totalCoverage = 0;
    num totalNeed = 0;
    num totalStock = 0;
    num coveredNeed = 0;
    var fullyCovered = 0;
    var paretoItems = 0;
    var consistentItems = 0;

    for (final row in masterRows) {
      final itemCode = _text(row['item_code']);
      final stock = inventory[itemCode]?.stock ?? 0;
      final rawNeed = math.max(_number(row['weekly_need']), 0);
      final rawShortage = math.max(rawNeed - stock, 0);
      final need =
          stock > 0 && rawShortage <= AvailabilityKpiItem.stockTolerance
          ? math.min(rawNeed, stock)
          : rawNeed;
      final status = purchaseStatuses[itemCode];
      final statusCovered =
          status != null && statusCoveredIds.contains(status.id);
      final coverage = statusCovered
          ? 100
          : need > 0
          ? math.min(stock / need, 1) * 100
          : 100;
      totalCoverage += coverage;
      totalNeed += need;
      totalStock += stock;
      coveredNeed += statusCovered ? need : math.min(stock, need);
      if (coverage >= 100) fullyCovered++;
      if (row['in_pareto'] == true) paretoItems++;
      if (row['in_consistent'] == true) consistentItems++;
    }

    return AvailabilityBranchSummary(
      branchName: branch,
      masterItems: masterRows.length,
      fullyAvailableItems: fullyCovered,
      shortageItems: masterRows.length - fullyCovered,
      paretoItems: paretoItems,
      consistentItems: consistentItems,
      weeklyNeed: totalNeed,
      branchStock: totalStock,
      coveredWeeklyNeed: coveredNeed,
      stockShortage: math.max(totalNeed - coveredNeed, 0),
      availabilityRate: masterRows.isEmpty
          ? 0
          : totalCoverage / masterRows.length,
    );
  }

  AvailabilityBranchData _buildBranchData({
    required String branch,
    required List<Map<String, dynamic>> masterRows,
    required Map<String, _ItemInventory> inventory,
    required Map<String, _PurchaseStatus> purchaseStatuses,
  }) {
    final items =
        masterRows
            .map((row) {
              final itemCode = _text(row['item_code']);
              final itemInventory =
                  inventory[itemCode] ?? const _ItemInventory();
              return AvailabilityKpiItem.fromMasterMap(
                row,
                branchStock: itemInventory.stock,
                extraQtyMoreThanMonth: itemInventory.extraQtyMoreThanMonth,
                purchaseStatusId: purchaseStatuses[itemCode]?.id,
                purchaseStatusName: purchaseStatuses[itemCode]?.name ?? '',
              );
            })
            .toList(growable: false)
          ..sort((a, b) {
            final rate = a.availabilityRate.compareTo(b.availabilityRate);
            if (rate != 0) return rate;
            final sales = b.recentSales.compareTo(a.recentSales);
            if (sales != 0) return sales;
            return a.itemCode.compareTo(b.itemCode);
          });

    return AvailabilityBranchData(
      summary: AvailabilityBranchSummary.fromItems(branch, items),
      items: items,
    );
  }

  /// Adds exact sold-month numbers for the branch currently opened by the
  /// user. This reads only that branch and avoids slowing down the automatic
  /// all-branch summary preload.
  Future<AvailabilityBranchData> enrichSellingMonths(
    AvailabilityBranchData data,
  ) async {
    final itemsByCode = <String, AvailabilityKpiItem>{
      for (final item in data.items)
        if (item.sellingMonthNumbers.isEmpty &&
            item.sellingMonths > 0 &&
            item.sellingMonths < item.totalMonths)
          item.itemCode: item,
    };
    if (itemsByCode.isEmpty) return data;

    final monthsByItem = <String, Set<int>>{};
    var offset = 0;
    while (true) {
      final response = await client
          .from('sales_history')
          .select('item_code,month,cash,online,insurance')
          .eq('branch_name', data.summary.branchName.trim())
          .order('item_code')
          .order('month')
          .range(offset, offset + _batchSize - 1);
      final batch = List<Map<String, dynamic>>.from(response as List);
      for (final row in batch) {
        final itemCode = _text(row['item_code']);
        final item = itemsByCode[itemCode];
        if (item == null) continue;
        final soldQty =
            _number(row['cash']) +
            _number(row['online']) +
            _number(row['insurance']);
        if (soldQty <= 0) continue;
        final monthStart = _parseMonth(_text(row['month']));
        if (monthStart == null || !_isInStudyPeriod(monthStart, item)) {
          continue;
        }
        (monthsByItem[itemCode] ??= <int>{}).add(monthStart.month);
      }
      if (batch.length < _batchSize) break;
      offset += _batchSize;
    }

    final enrichedItems = data.items
        .map((item) {
          final months = monthsByItem[item.itemCode];
          if (months == null || months.isEmpty) return item;
          final sortedMonths = months.toList()..sort();
          return item.withSellingMonthNumbers(sortedMonths);
        })
        .toList(growable: false);
    return AvailabilityBranchData(summary: data.summary, items: enrichedItems);
  }

  Future<List<Map<String, dynamic>>> _fetchMasterRows(String branch) async {
    final rows = <Map<String, dynamic>>[];
    var offset = 0;

    while (true) {
      final response = await client
          .from('availability_branch_master_cache')
          .select(_masterColumns)
          .eq('branch_name', branch.trim())
          .order('item_code')
          .range(offset, offset + _batchSize - 1);
      final batch = List<Map<String, dynamic>>.from(response as List);
      rows.addAll(batch);
      if (batch.length < _batchSize) break;
      offset += _batchSize;
    }
    return rows;
  }

  Future<Map<String, List<Map<String, dynamic>>>> _fetchAllMasterRows(
    Set<String> branches,
  ) async {
    final rowsByBranch = <String, List<Map<String, dynamic>>>{};
    var offset = 0;
    while (true) {
      final response = await client
          .from('availability_branch_master_cache')
          .select(_summaryColumns)
          .inFilter('branch_name', branches.toList(growable: false))
          .order('branch_name')
          .order('item_code')
          .range(offset, offset + _batchSize - 1);
      final batch = List<Map<String, dynamic>>.from(response as List);
      for (final row in batch) {
        final branch = _text(row['branch_name']);
        if (branches.contains(branch)) {
          (rowsByBranch[branch] ??= <Map<String, dynamic>>[]).add(row);
        }
      }
      if (batch.length < _batchSize) break;
      offset += _batchSize;
    }
    return rowsByBranch;
  }

  Future<Map<String, _ItemInventory>> _fetchInventoryMap({
    required String runDate,
    required String branch,
  }) async {
    final inventory = <String, _ItemInventory>{};
    var offset = 0;

    while (true) {
      final response = await client
          .from('daily_order')
          .select(
            'item_code,branch_stock,total_final_reorder_today,'
            'extra_qty_more_than_month',
          )
          .eq('run_date', runDate)
          .eq('branch', branch.trim())
          .order('item_code')
          .range(offset, offset + _batchSize - 1);
      final batch = List<Map<String, dynamic>>.from(response as List);
      for (final row in batch) {
        final itemCode = _text(row['item_code']);
        if (itemCode.isEmpty) continue;
        final stock = math.max(
          _number(row['branch_stock']) +
              _number(row['total_final_reorder_today']),
          0,
        );
        final previous = inventory[itemCode];
        inventory[itemCode] = _ItemInventory(
          stock: math.max(previous?.stock ?? 0, stock),
          extraQtyMoreThanMonth:
              (previous?.extraQtyMoreThanMonth ?? 0) +
              math.max(_number(row['extra_qty_more_than_month']), 0),
        );
      }
      if (batch.length < _batchSize) break;
      offset += _batchSize;
    }
    return inventory;
  }

  Future<Map<String, Map<String, _ItemInventory>>> _fetchAllInventory({
    required String runDate,
    required Set<String> branches,
  }) async {
    final inventoryByBranch = <String, Map<String, _ItemInventory>>{};
    var offset = 0;
    while (true) {
      final response = await client
          .from('daily_order')
          .select('branch,item_code,branch_stock,total_final_reorder_today')
          .eq('run_date', runDate)
          .inFilter('branch', branches.toList(growable: false))
          .order('branch')
          .order('item_code')
          .range(offset, offset + _batchSize - 1);
      final batch = List<Map<String, dynamic>>.from(response as List);
      for (final row in batch) {
        final branch = _text(row['branch']);
        final itemCode = _text(row['item_code']);
        if (!branches.contains(branch) || itemCode.isEmpty) continue;
        final branchInventory = inventoryByBranch[branch] ??=
            <String, _ItemInventory>{};
        final previous = branchInventory[itemCode];
        final stock = math.max(
          _number(row['branch_stock']) +
              _number(row['total_final_reorder_today']),
          0,
        );
        branchInventory[itemCode] = _ItemInventory(
          stock: math.max(previous?.stock ?? 0, stock),
        );
      }
      if (batch.length < _batchSize) break;
      offset += _batchSize;
    }
    return inventoryByBranch;
  }

  Future<Map<String, _PurchaseStatus>> _fetchPurchaseStatuses() {
    return _purchaseStatusesFuture ??= _loadPurchaseStatuses();
  }

  Future<Map<String, _PurchaseStatus>> _loadPurchaseStatuses() async {
    final statuses = <String, _PurchaseStatus>{};
    var offset = 0;
    while (true) {
      final response = await client
          .from('availability_kpi_purchase_status')
          .select('item_code,status_id,status_name')
          .order('item_code')
          .range(offset, offset + _batchSize - 1);
      final batch = List<Map<String, dynamic>>.from(response as List);
      for (final row in batch) {
        final itemCode = _text(row['item_code']);
        if (itemCode.isEmpty) continue;
        statuses[itemCode] = _PurchaseStatus(
          id: _integer(row['status_id']),
          name: _text(row['status_name']),
        );
      }
      if (batch.length < _batchSize) break;
      offset += _batchSize;
    }
    return statuses;
  }
}

class _PurchaseStatus {
  final int id;
  final String name;

  const _PurchaseStatus({required this.id, required this.name});
}

class _ItemInventory {
  final num stock;
  final num extraQtyMoreThanMonth;

  const _ItemInventory({this.stock = 0, this.extraQtyMoreThanMonth = 0});
}

class AvailabilityBranchData {
  final AvailabilityBranchSummary summary;
  final List<AvailabilityKpiItem> items;

  const AvailabilityBranchData({required this.summary, required this.items});
}

class AvailabilityBranchSummary {
  final String branchName;
  final int masterItems;
  final int fullyAvailableItems;
  final int shortageItems;
  final int paretoItems;
  final int consistentItems;
  final num weeklyNeed;
  final num branchStock;
  final num coveredWeeklyNeed;
  final num stockShortage;
  final num availabilityRate;

  const AvailabilityBranchSummary({
    required this.branchName,
    required this.masterItems,
    required this.fullyAvailableItems,
    required this.shortageItems,
    required this.paretoItems,
    required this.consistentItems,
    required this.weeklyNeed,
    required this.branchStock,
    required this.coveredWeeklyNeed,
    required this.stockShortage,
    required this.availabilityRate,
  });

  factory AvailabilityBranchSummary.empty(String branchName) {
    return AvailabilityBranchSummary(
      branchName: branchName,
      masterItems: 0,
      fullyAvailableItems: 0,
      shortageItems: 0,
      paretoItems: 0,
      consistentItems: 0,
      weeklyNeed: 0,
      branchStock: 0,
      coveredWeeklyNeed: 0,
      stockShortage: 0,
      availabilityRate: 0,
    );
  }

  factory AvailabilityBranchSummary.fromItems(
    String branchName,
    List<AvailabilityKpiItem> items,
  ) {
    num weeklyNeed = 0;
    num branchStock = 0;
    num coveredNeed = 0;
    num totalItemCoverage = 0;
    var fullyAvailable = 0;
    var paretoItems = 0;
    var consistentItems = 0;

    for (final item in items) {
      weeklyNeed += item.weeklyNeed;
      branchStock += item.branchStock;
      coveredNeed += item.isStatusCovered
          ? item.weeklyNeed
          : math.min(item.branchStock, item.weeklyNeed);
      totalItemCoverage += item.availabilityRate;
      if (item.availabilityRate >= 100) fullyAvailable++;
      if (item.inPareto) paretoItems++;
      if (item.inConsistent) consistentItems++;
    }

    final availability = items.isNotEmpty
        ? totalItemCoverage / items.length
        : 0;
    return AvailabilityBranchSummary(
      branchName: branchName,
      masterItems: items.length,
      fullyAvailableItems: fullyAvailable,
      shortageItems: items.length - fullyAvailable,
      paretoItems: paretoItems,
      consistentItems: consistentItems,
      weeklyNeed: weeklyNeed,
      branchStock: branchStock,
      coveredWeeklyNeed: coveredNeed,
      stockShortage: math.max(weeklyNeed - coveredNeed, 0),
      availabilityRate: availability,
    );
  }
}

class AvailabilityKpiItem {
  static const num stockTolerance = 0.16;

  final String branchName;
  final String itemCode;
  final String itemName;
  final String masterSource;
  final int? statusId;
  final String statusName;
  final bool isStatusCovered;
  final List<int> sellingMonthNumbers;
  final bool inPareto;
  final bool inConsistent;
  final num recentSales;
  final num retail;
  final num recentSalesValue;
  final num recentSalesShare;
  final num cumulativeSalesShare;
  final num totalSales;
  final int sellingMonths;
  final int totalMonths;
  final num monthConsistency;
  final int recentSellingMonths;
  final num weeklyNeed;
  final num branchStock;
  final num stockShortage;
  final num extraQtyMoreThanMonth;
  final num availabilityRate;
  final DateTime? analysisStart;
  final DateTime? recentStart;
  final DateTime? asOfDate;

  const AvailabilityKpiItem({
    required this.branchName,
    required this.itemCode,
    required this.itemName,
    required this.masterSource,
    required this.statusId,
    required this.statusName,
    required this.isStatusCovered,
    required this.sellingMonthNumbers,
    required this.inPareto,
    required this.inConsistent,
    required this.recentSales,
    required this.retail,
    required this.recentSalesValue,
    required this.recentSalesShare,
    required this.cumulativeSalesShare,
    required this.totalSales,
    required this.sellingMonths,
    required this.totalMonths,
    required this.monthConsistency,
    required this.recentSellingMonths,
    required this.weeklyNeed,
    required this.branchStock,
    required this.stockShortage,
    required this.extraQtyMoreThanMonth,
    required this.availabilityRate,
    required this.analysisStart,
    required this.recentStart,
    required this.asOfDate,
  });

  AvailabilityKpiItem withSellingMonthNumbers(List<int> months) {
    return AvailabilityKpiItem(
      branchName: branchName,
      itemCode: itemCode,
      itemName: itemName,
      masterSource: masterSource,
      statusId: statusId,
      statusName: statusName,
      isStatusCovered: isStatusCovered,
      sellingMonthNumbers: List<int>.unmodifiable(months),
      inPareto: inPareto,
      inConsistent: inConsistent,
      recentSales: recentSales,
      retail: retail,
      recentSalesValue: recentSalesValue,
      recentSalesShare: recentSalesShare,
      cumulativeSalesShare: cumulativeSalesShare,
      totalSales: totalSales,
      sellingMonths: sellingMonths,
      totalMonths: totalMonths,
      monthConsistency: monthConsistency,
      recentSellingMonths: recentSellingMonths,
      weeklyNeed: weeklyNeed,
      branchStock: branchStock,
      stockShortage: stockShortage,
      extraQtyMoreThanMonth: extraQtyMoreThanMonth,
      availabilityRate: availabilityRate,
      analysisStart: analysisStart,
      recentStart: recentStart,
      asOfDate: asOfDate,
    );
  }

  factory AvailabilityKpiItem.fromMasterMap(
    Map<String, dynamic> map, {
    required num branchStock,
    num extraQtyMoreThanMonth = 0,
    int? purchaseStatusId,
    String purchaseStatusName = '',
  }) {
    final rawWeeklyNeed = math.max(_number(map['weekly_need']), 0);
    final stock = math.max(branchStock, 0);
    final rawShortage = math.max(rawWeeklyNeed - stock, 0);
    final weeklyNeed = stock > 0 && rawShortage <= stockTolerance
        ? math.min(rawWeeklyNeed, stock)
        : rawWeeklyNeed;
    final recentSales = _number(map['recent_sales']);
    final recentSalesShare = _number(map['recent_sales_share']);
    final branchRecentValue = _number(map['branch_recent_sales']);
    final recentSalesValue = branchRecentValue * recentSalesShare;
    final retail = recentSales > 0 ? recentSalesValue / recentSales : 0;
    final sourceParts = _text(map['master_source']).split('|');
    final sellingMonthNumbers = sourceParts.length < 2
        ? const <int>[]
        : sourceParts[1]
              .split(',')
              .map((value) => int.tryParse(value.trim()))
              .whereType<int>()
              .where((month) => month >= 1 && month <= 12)
              .toList(growable: false);
    final isStatusCovered =
        purchaseStatusId != null &&
        AvailabilityKpiRemoteDs.statusCoveredIds.contains(purchaseStatusId);
    final availability = isStatusCovered
        ? 100
        : weeklyNeed > 0
        ? math.min(stock / weeklyNeed, 1) * 100
        : 100;
    return AvailabilityKpiItem(
      branchName: _text(map['branch_name']),
      itemCode: _text(map['item_code']),
      itemName: _text(map['item_name']),
      masterSource: sourceParts.first,
      statusId: purchaseStatusId,
      statusName: purchaseStatusName,
      isStatusCovered: isStatusCovered,
      sellingMonthNumbers: sellingMonthNumbers,
      inPareto: map['in_pareto'] == true,
      inConsistent: map['in_consistent'] == true,
      recentSales: recentSales,
      retail: retail,
      recentSalesValue: recentSalesValue,
      recentSalesShare: recentSalesShare * 100,
      cumulativeSalesShare: _number(map['cumulative_sales_share']) * 100,
      totalSales: _number(map['total_sales']),
      sellingMonths: _integer(map['selling_months']),
      totalMonths: _integer(map['total_months']),
      monthConsistency: _number(map['month_consistency']) * 100,
      recentSellingMonths: _integer(map['recent_selling_months']),
      weeklyNeed: weeklyNeed,
      branchStock: stock,
      stockShortage: isStatusCovered ? 0 : math.max(weeklyNeed - stock, 0),
      extraQtyMoreThanMonth: availability < 100
          ? math.max(extraQtyMoreThanMonth, 0)
          : 0,
      availabilityRate: availability,
      analysisStart: DateTime.tryParse(_text(map['analysis_start'])),
      recentStart: DateTime.tryParse(_text(map['recent_start'])),
      asOfDate: DateTime.tryParse(_text(map['as_of_date'])),
    );
  }
}

String _text(dynamic value) => (value ?? '').toString().trim();

num _number(dynamic value) {
  if (value is num) return value;
  return num.tryParse(_text(value)) ?? 0;
}

int _integer(dynamic value) {
  if (value is int) return value;
  return num.tryParse(_text(value))?.toInt() ?? 0;
}

DateTime? _parseMonth(String value) {
  final parts = value.split('/');
  if (parts.length != 2) return null;
  final month = int.tryParse(parts[0]);
  final year = int.tryParse(parts[1]);
  if (month == null || year == null || month < 1 || month > 12) return null;
  return DateTime(year, month);
}

bool _isInStudyPeriod(DateTime monthStart, AvailabilityKpiItem item) {
  final analysisStart = item.analysisStart;
  final asOfDate = item.asOfDate;
  if (analysisStart != null) {
    final firstMonth = DateTime(analysisStart.year, analysisStart.month);
    if (monthStart.isBefore(firstMonth)) return false;
  }
  if (asOfDate != null) {
    final lastMonth = DateTime(asOfDate.year, asOfDate.month);
    if (monthStart.isAfter(lastMonth)) return false;
  }
  return true;
}
