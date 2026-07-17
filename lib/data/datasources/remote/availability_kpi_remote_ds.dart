import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

class AvailabilityKpiRemoteDs {
  static const _batchSize = 2000;

  final SupabaseClient client;

  const AvailabilityKpiRemoteDs(this.client);

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

    final stocks = await _fetchStockMap(runDate: runDate, branch: branch);
    if (stocks.isEmpty) {
      throw StateError(
        'No stock snapshot found for $branch on $runDate in daily_order.',
      );
    }
    final items =
        masterRows
            .map((row) {
              final itemCode = _text(row['item_code']);
              return AvailabilityKpiItem.fromMasterMap(
                row,
                branchStock: stocks[itemCode] ?? 0,
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

  Future<List<Map<String, dynamic>>> _fetchMasterRows(String branch) async {
    const columns = '''
branch_name,item_code,item_name,master_source,in_pareto,in_consistent,
recent_sales,recent_sales_share,cumulative_sales_share,total_sales,
branch_recent_sales,
selling_months,total_months,month_consistency,recent_selling_months,
weekly_need,analysis_start,recent_start,as_of_date
''';
    final rows = <Map<String, dynamic>>[];
    var offset = 0;

    while (true) {
      final response = await client
          .from('availability_branch_master_cache')
          .select(columns)
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

  Future<Map<String, num>> _fetchStockMap({
    required String runDate,
    required String branch,
  }) async {
    final stocks = <String, num>{};
    var offset = 0;

    while (true) {
      final response = await client
          .from('daily_order')
          .select('item_code,branch_stock')
          .eq('run_date', runDate)
          .eq('branch', branch.trim())
          .order('item_code')
          .range(offset, offset + _batchSize - 1);
      final batch = List<Map<String, dynamic>>.from(response as List);
      for (final row in batch) {
        final itemCode = _text(row['item_code']);
        if (itemCode.isEmpty) continue;
        final stock = math.max(_number(row['branch_stock']), 0);
        stocks[itemCode] = math.max(stocks[itemCode] ?? 0, stock);
      }
      if (batch.length < _batchSize) break;
      offset += _batchSize;
    }
    return stocks;
  }
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
    var fullyAvailable = 0;
    var paretoItems = 0;
    var consistentItems = 0;

    for (final item in items) {
      weeklyNeed += item.weeklyNeed;
      branchStock += item.branchStock;
      coveredNeed += math.min(item.branchStock, item.weeklyNeed);
      if (item.branchStock >= item.weeklyNeed) fullyAvailable++;
      if (item.inPareto) paretoItems++;
      if (item.inConsistent) consistentItems++;
    }

    final availability = weeklyNeed > 0
        ? math.min(coveredNeed / weeklyNeed, 1) * 100
        : 100;
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
  final String branchName;
  final String itemCode;
  final String itemName;
  final String masterSource;
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
  final num availabilityRate;
  final DateTime? analysisStart;
  final DateTime? recentStart;
  final DateTime? asOfDate;

  const AvailabilityKpiItem({
    required this.branchName,
    required this.itemCode,
    required this.itemName,
    required this.masterSource,
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
    required this.availabilityRate,
    required this.analysisStart,
    required this.recentStart,
    required this.asOfDate,
  });

  factory AvailabilityKpiItem.fromMasterMap(
    Map<String, dynamic> map, {
    required num branchStock,
  }) {
    final weeklyNeed = math.max(_number(map['weekly_need']), 0);
    final stock = math.max(branchStock, 0);
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
    final availability = weeklyNeed > 0
        ? math.min(stock / weeklyNeed, 1) * 100
        : 100;
    return AvailabilityKpiItem(
      branchName: _text(map['branch_name']),
      itemCode: _text(map['item_code']),
      itemName: _text(map['item_name']),
      masterSource: sourceParts.first,
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
      stockShortage: math.max(weeklyNeed - stock, 0),
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
