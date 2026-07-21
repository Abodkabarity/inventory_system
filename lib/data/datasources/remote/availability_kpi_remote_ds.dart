import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

class AvailabilityKpiRemoteDs {
  static const _batchSize = 2000;
  static const statusCoveredIds = <int>{1, 2, 5, 7, 8, 34};

  final SupabaseClient client;
  Future<Map<String, _PurchaseStatus>>? _purchaseStatusesFuture;
  Future<Map<String, num>>? _retailPricesFuture;
  Future<Map<String, num>>? _globalExtraQuantitiesFuture;
  String? _globalExtraRunDate;

  AvailabilityKpiRemoteDs(this.client);

  void invalidatePurchaseStatuses() {
    _purchaseStatusesFuture = null;
    _retailPricesFuture = null;
    _globalExtraQuantitiesFuture = null;
    _globalExtraRunDate = null;
  }

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
  static const _exportCacheColumns = '''
branch_name,item_code,item_name,master_source,in_pareto,in_consistent,
recent_sales,recent_sales_share,cumulative_sales_share,total_sales,
branch_recent_sales,selling_months,total_months,month_consistency,
recent_selling_months,weekly_need,analysis_start,recent_start,as_of_date,
branch_stock,extra_qty_more_than_month,status_id,status_name,retail,
store_stock,decrease_demand_30_days
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

  Future<List<AvailabilityAllocationRow>> fetchAllocation({
    required String runDate,
  }) async {
    final results = await Future.wait<dynamic>([
      client.rpc(
        'get_availability_allocation_v1',
        params: {'p_run_date': runDate, 'p_force_refresh': false},
      ),
      client
          .from('branches')
          .select('branch_name,branch_group')
          .eq('is_active', true),
    ]);
    final rows = List<Map<String, dynamic>>.from(
      results[0] as List,
    ).map(AvailabilityAllocationRow.fromMap).toList(growable: false);
    final eligibleBranches = List<Map<String, dynamic>>.from(results[1] as List)
        .where((row) => _text(row['branch_group']).toUpperCase() == 'APG')
        .map((row) => _text(row['branch_name']))
        .where((branch) => branch.isNotEmpty)
        .toSet();
    if (rows.any(
      (row) =>
          !eligibleBranches.contains(row.fromBranch) ||
          !eligibleBranches.contains(row.toBranch),
    )) {
      throw StateError(
        'The allocation cache contains a branch outside the active APG group.',
      );
    }
    return rows;
  }

  Future<Map<String, AvailabilityAllocationImpact>> fetchAllocationImpact({
    required String runDate,
  }) async {
    final response = await client.rpc(
      'get_availability_allocation_impact_v1',
      params: {'p_run_date': runDate},
    );
    final impacts = <String, AvailabilityAllocationImpact>{};
    for (final row in List<Map<String, dynamic>>.from(response as List)) {
      final impact = AvailabilityAllocationImpact.fromMap(row);
      if (impact.branchName.isNotEmpty) {
        impacts[impact.branchName] = impact;
      }
    }
    return impacts;
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

    final results = await Future.wait<dynamic>([
      _fetchPurchaseStatuses(),
      _fetchInventoryMap(runDate: runDate, branch: branch),
      _fetchGlobalExtraQuantities(runDate),
      _fetchRetailPrices(),
      _fetchMaxAdjDecrease(branch),
    ]);
    final purchaseStatuses = results[0] as Map<String, _PurchaseStatus>;
    final inventory = results[1] as Map<String, _ItemInventory>;
    final globalExtraQuantities = results[2] as Map<String, num>;
    final retailPrices = results[3] as Map<String, num>;
    final decreaseDemandByItem = results[4] as Map<String, num>;
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
      globalExtraQuantities: globalExtraQuantities,
      retailPrices: retailPrices,
      decreaseDemandByItem: decreaseDemandByItem,
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

  Future<List<AvailabilityKpiItem>> fetchAllBranchItemsForExport({
    required String runDate,
    required Iterable<String> branches,
    void Function(double progress, String message)? onProgress,
  }) async {
    final requested = branches.map((value) => value.trim()).toSet();
    if (requested.isEmpty) return const [];

    try {
      return await _fetchAllBranchItemsFromExportCache(
        runDate: runDate,
        branches: requested,
        onProgress: onProgress,
      );
    } catch (_) {
      onProgress?.call(
        .04,
        'Fast export cache is unavailable; loading source tables...',
      );
    }

    onProgress?.call(.06, 'Loading all branch item lists...');
    final results = await Future.wait<dynamic>([
      _fetchAllMasterDetailRows(requested),
      _fetchAllInventory(runDate: runDate, branches: requested),
      _fetchPurchaseStatuses(),
      _fetchGlobalExtraQuantities(runDate),
      _fetchRetailPrices(),
      _fetchAllMaxAdjDecrease(requested),
    ]);
    final masterByBranch =
        results[0] as Map<String, List<Map<String, dynamic>>>;
    final inventoryByBranch =
        results[1] as Map<String, Map<String, _ItemInventory>>;
    final purchaseStatuses = results[2] as Map<String, _PurchaseStatus>;
    final globalExtraQuantities = results[3] as Map<String, num>;
    final retailPrices = results[4] as Map<String, num>;
    final decreaseDemandByBranch = results[5] as Map<String, Map<String, num>>;
    onProgress?.call(.55, 'Building the combined item table...');

    final sortedBranches = requested.toList()
      ..sort(
        (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
      );
    final items = <AvailabilityKpiItem>[];
    for (var index = 0; index < sortedBranches.length; index++) {
      final branch = sortedBranches[index];
      final masterRows = masterByBranch[branch] ?? const [];
      final inventory = inventoryByBranch[branch] ?? const {};
      if (masterRows.isNotEmpty) {
        items.addAll(
          _buildBranchData(
            branch: branch,
            masterRows: masterRows,
            inventory: inventory,
            purchaseStatuses: purchaseStatuses,
            globalExtraQuantities: globalExtraQuantities,
            retailPrices: retailPrices,
            decreaseDemandByItem: decreaseDemandByBranch[branch] ?? const {},
          ).items,
        );
      }
      onProgress?.call(
        .55 + ((index + 1) / sortedBranches.length) * .17,
        'Preparing ${index + 1} of ${sortedBranches.length} branches...',
      );
      if (index % 4 == 0) await Future<void>.delayed(Duration.zero);
    }
    return items;
  }

  Future<List<AvailabilityKpiItem>> _fetchAllBranchItemsFromExportCache({
    required String runDate,
    required Set<String> branches,
    void Function(double progress, String message)? onProgress,
  }) async {
    onProgress?.call(.04, 'Preparing the fast export cache...');
    final response = await client.rpc(
      'ensure_availability_kpi_export_cache_v1',
      params: {'p_run_date': runDate},
    );
    final rowCount = _integer(response);
    if (rowCount <= 0) return const [];

    const pageSize = 1000;
    const parallelPages = 6;
    final pageCount = (rowCount / pageSize).ceil();
    final rows = <Map<String, dynamic>>[];
    for (var startPage = 0; startPage < pageCount; startPage += parallelPages) {
      final endPage = math.min(startPage + parallelPages, pageCount);
      final pages = await Future.wait<dynamic>([
        for (var page = startPage; page < endPage; page++)
          client
              .from('availability_kpi_export_cache_v1')
              .select(_exportCacheColumns)
              .eq('run_date', runDate)
              .order('branch_name')
              .order('item_code')
              .range(page * pageSize, (page + 1) * pageSize - 1),
      ]);
      for (final page in pages) {
        rows.addAll(List<Map<String, dynamic>>.from(page as List));
      }
      onProgress?.call(
        .12 + (endPage / pageCount) * .5,
        'Downloaded ${rows.length} of $rowCount items...',
      );
      await Future<void>.delayed(Duration.zero);
    }

    rows.sort((left, right) {
      final branchCompare = _text(
        left['branch_name'],
      ).toLowerCase().compareTo(_text(right['branch_name']).toLowerCase());
      if (branchCompare != 0) return branchCompare;
      return _text(left['item_code']).compareTo(_text(right['item_code']));
    });
    final items = <AvailabilityKpiItem>[];
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      if (!branches.contains(_text(row['branch_name']))) continue;
      items.add(
        AvailabilityKpiItem.fromMasterMap(
          row,
          branchStock: _number(row['branch_stock']),
          extraQtyMoreThanMonth: _number(row['extra_qty_more_than_month']),
          purchaseStatusId: row['status_id'] == null
              ? null
              : _integer(row['status_id']),
          purchaseStatusName: _text(row['status_name']),
          retailPrice: _number(row['retail']),
          storeStock: _number(row['store_stock']),
          decreaseDemand30Days: row['decrease_demand_30_days'] == null
              ? null
              : _number(row['decrease_demand_30_days']),
        ),
      );
      if (index % 1000 == 0) {
        onProgress?.call(
          .62 + ((index + 1) / rows.length) * .1,
          'Preparing the combined Excel table...',
        );
        await Future<void>.delayed(Duration.zero);
      }
    }
    return items;
  }

  /// Uses the server-side aggregate and transfers only one row per branch.
  Future<Map<String, AvailabilityBranchSummary>> fetchAllBranchSummariesFast({
    required String runDate,
  }) async {
    try {
      var cachedResponse = await client
          .from('availability_branch_summary_cache_v2')
          .select('''
branch_name,master_items,fully_available_items,shortage_items,pareto_items,
consistent_items,weekly_need,branch_stock,covered_weekly_need,stock_shortage,
availability_rate
''')
          .eq('run_date', runDate)
          .order('branch_name');
      var cached = _parseBranchSummaries(cachedResponse);
      if (cached.isNotEmpty) return cached;

      // A new operational date may not have a summary snapshot yet. Build it
      // once on the server, then keep subsequent page loads cache-only.
      await client.rpc(
        'ensure_availability_branch_summary_cache_v2',
        params: {'p_run_date': runDate},
      );
      cachedResponse = await client
          .from('availability_branch_summary_cache_v2')
          .select('''
branch_name,master_items,fully_available_items,shortage_items,pareto_items,
consistent_items,weekly_need,branch_stock,covered_weekly_need,stock_shortage,
availability_rate
''')
          .eq('run_date', runDate)
          .order('branch_name');
      cached = _parseBranchSummaries(cachedResponse);
      if (cached.isNotEmpty) return cached;
    } catch (_) {
      // The cache migration may not be installed yet. Try the direct RPC.
    }

    final response = await client.rpc(
      'get_availability_branch_summaries_v2',
      params: {'p_run_date': runDate},
    );
    return _parseBranchSummaries(response);
  }

  Map<String, AvailabilityBranchSummary> _parseBranchSummaries(
    dynamic response,
  ) {
    final summaries = <String, AvailabilityBranchSummary>{};
    for (final row in List<Map<String, dynamic>>.from(response as List)) {
      final branch = _text(row['branch_name']);
      if (branch.isEmpty) continue;
      summaries[branch] = AvailabilityBranchSummary(
        branchName: branch,
        masterItems: _integer(row['master_items']),
        fullyAvailableItems: _integer(row['fully_available_items']),
        shortageItems: _integer(row['shortage_items']),
        paretoItems: _integer(row['pareto_items']),
        consistentItems: _integer(row['consistent_items']),
        weeklyNeed: _number(row['weekly_need']),
        branchStock: _number(row['branch_stock']),
        coveredWeeklyNeed: _number(row['covered_weekly_need']),
        stockShortage: _number(row['stock_shortage']),
        availabilityRate: AvailabilityBranchSummary.normalizeRate(
          _number(row['availability_rate']),
        ),
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
    var includedItems = 0;

    for (final row in masterRows) {
      final itemCode = _text(row['item_code']);
      final storeStock = inventory[itemCode]?.storeStock ?? 0;
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
      if (storeStock > 4 && coverage < 100) continue;

      includedItems++;
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
      masterItems: includedItems,
      fullyAvailableItems: fullyCovered,
      shortageItems: includedItems - fullyCovered,
      paretoItems: paretoItems,
      consistentItems: consistentItems,
      weeklyNeed: totalNeed,
      branchStock: totalStock,
      coveredWeeklyNeed: coveredNeed,
      stockShortage: math.max(totalNeed - coveredNeed, 0),
      availabilityRate: AvailabilityBranchSummary.normalizeRate(
        includedItems == 0 ? 0 : totalCoverage / includedItems,
      ),
    );
  }

  AvailabilityBranchData _buildBranchData({
    required String branch,
    required List<Map<String, dynamic>> masterRows,
    required Map<String, _ItemInventory> inventory,
    required Map<String, _PurchaseStatus> purchaseStatuses,
    required Map<String, num> globalExtraQuantities,
    required Map<String, num> retailPrices,
    required Map<String, num> decreaseDemandByItem,
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
                extraQtyMoreThanMonth: globalExtraQuantities[itemCode] ?? 0,
                purchaseStatusId: purchaseStatuses[itemCode]?.id,
                purchaseStatusName: purchaseStatuses[itemCode]?.name ?? '',
                retailPrice: retailPrices[itemCode],
                storeStock: itemInventory.storeStock,
                decreaseDemand30Days: decreaseDemandByItem[itemCode],
              );
            })
            .where(
              (item) => item.storeStock <= 4 || item.availabilityRate >= 100,
            )
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
      if (batch.isEmpty) break;
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
      offset += batch.length;
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
      if (batch.isEmpty) break;
      rows.addAll(batch);
      offset += batch.length;
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
          .order('branch_name')
          .order('item_code')
          .range(offset, offset + _batchSize - 1);
      final batch = List<Map<String, dynamic>>.from(response as List);
      if (batch.isEmpty) break;
      for (final row in batch) {
        final branch = _text(row['branch_name']);
        if (branches.contains(branch)) {
          (rowsByBranch[branch] ??= <Map<String, dynamic>>[]).add(row);
        }
      }
      offset += batch.length;
    }
    return rowsByBranch;
  }

  Future<Map<String, List<Map<String, dynamic>>>> _fetchAllMasterDetailRows(
    Set<String> branches,
  ) async {
    final rowsByBranch = <String, List<Map<String, dynamic>>>{};
    var offset = 0;
    while (true) {
      final response = await client
          .from('availability_branch_master_cache')
          .select(_masterColumns)
          .order('branch_name')
          .order('item_code')
          .range(offset, offset + _batchSize - 1);
      final batch = List<Map<String, dynamic>>.from(response as List);
      if (batch.isEmpty) break;
      for (final row in batch) {
        final branch = _text(row['branch_name']);
        if (branches.contains(branch)) {
          (rowsByBranch[branch] ??= <Map<String, dynamic>>[]).add(row);
        }
      }
      offset += batch.length;
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
          .select('''
item_code,branch_stock,total_final_reorder_today,store_stock,total_reorder_today
''')
          .eq('run_date', runDate)
          .eq('branch', branch.trim())
          .order('item_code')
          .range(offset, offset + _batchSize - 1);
      final batch = List<Map<String, dynamic>>.from(response as List);
      if (batch.isEmpty) break;
      for (final row in batch) {
        final itemCode = _text(row['item_code']);
        if (itemCode.isEmpty) continue;
        final stock = math.max(
          _number(row['branch_stock']) +
              _number(row['total_final_reorder_today']),
          0,
        );
        final previous = inventory[itemCode];
        final storeStock =
            _number(row['store_stock']) - _number(row['total_reorder_today']);
        inventory[itemCode] = _ItemInventory(
          stock: math.max(previous?.stock ?? 0, stock),
          storeStock: previous == null
              ? storeStock
              : math.max(previous.storeStock, storeStock),
        );
      }
      offset += batch.length;
    }
    return inventory;
  }

  Future<Map<String, num>> _fetchGlobalExtraQuantities(String runDate) {
    if (_globalExtraRunDate != runDate ||
        _globalExtraQuantitiesFuture == null) {
      _globalExtraRunDate = runDate;
      _globalExtraQuantitiesFuture = _loadGlobalExtraQuantities(runDate);
    }
    return _globalExtraQuantitiesFuture!;
  }

  Future<Map<String, num>> _loadGlobalExtraQuantities(String runDate) async {
    final quantities = <String, num>{};
    var offset = 0;
    while (true) {
      final response = await client
          .from('daily_order')
          .select('item_code,extra_qty_more_than_month')
          .eq('run_date', runDate)
          .gt('extra_qty_more_than_month', 0)
          .order('item_code')
          .range(offset, offset + _batchSize - 1);
      final batch = List<Map<String, dynamic>>.from(response as List);
      if (batch.isEmpty) break;
      for (final row in batch) {
        final itemCode = _text(row['item_code']);
        if (itemCode.isEmpty) continue;
        quantities[itemCode] =
            (quantities[itemCode] ?? 0) +
            math.max(_number(row['extra_qty_more_than_month']), 0);
      }
      offset += batch.length;
    }
    return quantities;
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
          .select('''
branch,item_code,branch_stock,total_final_reorder_today,store_stock,total_reorder_today
''')
          .eq('run_date', runDate)
          .order('branch')
          .order('item_code')
          .range(offset, offset + _batchSize - 1);
      final batch = List<Map<String, dynamic>>.from(response as List);
      if (batch.isEmpty) break;
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
        final storeStock =
            _number(row['store_stock']) - _number(row['total_reorder_today']);
        branchInventory[itemCode] = _ItemInventory(
          stock: math.max(previous?.stock ?? 0, stock),
          storeStock: previous == null
              ? storeStock
              : math.max(previous.storeStock, storeStock),
        );
      }
      offset += batch.length;
    }
    return inventoryByBranch;
  }

  Future<Map<String, _PurchaseStatus>> _fetchPurchaseStatuses() {
    return _purchaseStatusesFuture ??= _loadPurchaseStatuses();
  }

  Future<Map<String, num>> _fetchMaxAdjDecrease(String branch) async {
    final response = await client
        .from('max_adj')
        .select('item_code,qty')
        .eq('branch_name', branch.trim())
        .eq('adjustment_type', 'DECREASE')
        .gt('qty', 0);
    return {
      for (final row in List<Map<String, dynamic>>.from(response as List))
        if (_text(row['item_code']).isNotEmpty)
          _text(row['item_code']): _number(row['qty']),
    };
  }

  Future<Map<String, Map<String, num>>> _fetchAllMaxAdjDecrease(
    Set<String> branches,
  ) async {
    final result = <String, Map<String, num>>{};
    var offset = 0;
    while (true) {
      final response = await client
          .from('max_adj')
          .select('branch_name,item_code,qty')
          .eq('adjustment_type', 'DECREASE')
          .gt('qty', 0)
          .order('branch_name')
          .order('item_code')
          .range(offset, offset + _batchSize - 1);
      final batch = List<Map<String, dynamic>>.from(response as List);
      if (batch.isEmpty) break;
      for (final row in batch) {
        final branch = _text(row['branch_name']);
        final itemCode = _text(row['item_code']);
        if (!branches.contains(branch) || itemCode.isEmpty) continue;
        (result[branch] ??= <String, num>{})[itemCode] = _number(row['qty']);
      }
      offset += batch.length;
    }
    return result;
  }

  Future<Map<String, num>> _fetchRetailPrices() {
    return _retailPricesFuture ??= _loadRetailPrices();
  }

  Future<Map<String, num>> _loadRetailPrices() async {
    final prices = <String, num>{};
    var offset = 0;
    while (true) {
      final response = await client
          .from('item_report')
          .select('item_code,retail')
          .eq('item_status', '1#NORMAL PURCHASE')
          .order('item_code')
          .range(offset, offset + _batchSize - 1);
      final batch = List<Map<String, dynamic>>.from(response as List);
      if (batch.isEmpty) break;
      for (final row in batch) {
        final itemCode = _text(row['item_code']);
        if (itemCode.isEmpty) continue;
        prices[itemCode] = math.max(
          prices[itemCode] ?? 0,
          math.max(_number(row['retail']), 0),
        );
      }
      offset += batch.length;
    }
    return prices;
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
      if (batch.isEmpty) break;
      for (final row in batch) {
        final itemCode = _text(row['item_code']);
        if (itemCode.isEmpty) continue;
        statuses[itemCode] = _PurchaseStatus(
          id: _integer(row['status_id']),
          name: _text(row['status_name']),
        );
      }
      offset += batch.length;
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
  final num storeStock;

  const _ItemInventory({this.stock = 0, this.storeStock = 0});
}

class AvailabilityBranchData {
  final AvailabilityBranchSummary summary;
  final List<AvailabilityKpiItem> items;

  const AvailabilityBranchData({required this.summary, required this.items});
}

class AvailabilityAllocationRow {
  final int order;
  final String fromBranch;
  final String itemCode;
  final String itemName;
  final int qty;
  final String toBranch;

  const AvailabilityAllocationRow({
    required this.order,
    required this.fromBranch,
    required this.itemCode,
    required this.itemName,
    required this.qty,
    required this.toBranch,
  });

  factory AvailabilityAllocationRow.fromMap(Map<String, dynamic> map) {
    return AvailabilityAllocationRow(
      order: _integer(map['allocation_order']),
      fromBranch: _text(map['from_branch']),
      itemCode: _text(map['item_code']),
      itemName: _text(map['item_name']),
      qty: _integer(map['qty']),
      toBranch: _text(map['to_branch']),
    );
  }
}

class AvailabilityAllocationImpact {
  final String branchName;
  final num currentRate;
  final num projectedRate;
  final num rateChange;
  final int incomingQty;
  final int outgoingQty;

  const AvailabilityAllocationImpact({
    required this.branchName,
    required this.currentRate,
    required this.projectedRate,
    required this.rateChange,
    required this.incomingQty,
    required this.outgoingQty,
  });

  factory AvailabilityAllocationImpact.fromMap(Map<String, dynamic> map) {
    return AvailabilityAllocationImpact(
      branchName: _text(map['branch_name']),
      currentRate: _number(map['current_rate']),
      projectedRate: _number(map['projected_rate']),
      rateChange: _number(map['rate_change']),
      incomingQty: _integer(map['incoming_qty']),
      outgoingQty: _integer(map['outgoing_qty']),
    );
  }
}

class AvailabilityBranchSummary {
  static const num targetRate = 97;
  static const num targetRateTolerance = 0.2;

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

  static num normalizeRate(num value) {
    final difference = targetRate - value;
    if (value < targetRate &&
        difference >= 0 &&
        difference <= targetRateTolerance + 0.0000001) {
      return targetRate;
    }
    return value;
  }

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
      availabilityRate: normalizeRate(availability),
    );
  }

  AvailabilityBranchSummary withAvailabilityRate(num value) {
    return AvailabilityBranchSummary(
      branchName: branchName,
      masterItems: masterItems,
      fullyAvailableItems: fullyAvailableItems,
      shortageItems: shortageItems,
      paretoItems: paretoItems,
      consistentItems: consistentItems,
      weeklyNeed: weeklyNeed,
      branchStock: branchStock,
      coveredWeeklyNeed: coveredWeeklyNeed,
      stockShortage: stockShortage,
      availabilityRate: normalizeRate(value),
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
  final num storeStock;
  final num? decreaseDemand30Days;
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
    required this.storeStock,
    required this.decreaseDemand30Days,
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
      storeStock: storeStock,
      decreaseDemand30Days: decreaseDemand30Days,
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
    num? retailPrice,
    num storeStock = 0,
    num? decreaseDemand30Days,
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
    final retail = retailPrice != null
        ? math.max(retailPrice, 0)
        : recentSales > 0
        ? recentSalesValue / recentSales
        : 0;
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
      storeStock: storeStock,
      decreaseDemand30Days: decreaseDemand30Days,
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
