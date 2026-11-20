import 'stock_catalog.dart';
import 'stock_management.dart';

enum OnlineSalesScope {
  onlineOnly('Online sales'),
  allChannels('All branch sales');

  final String label;
  const OnlineSalesScope(this.label);
}

enum OnlineRank {
  a('A', 'High-priority online sales'),
  b('B', 'Intermediate or concentrated local demand'),
  c('C', 'Low observed online demand'),
  n(
    'N',
    'New within 6 months of first MRN, with STORE stock and zero online stock',
  ),
  m('M', 'Zero online stock and no online sales in either year'),
  t('T', 'Online stock with no sales in the last 6 full months'),
  s('S', 'Sales Orientation is INHOUSE'),
  review('Review', 'Current stock needs checking');

  final String label, description;
  const OnlineRank(this.label, this.description);
}

String onlineKey(String value) => value.trim().toUpperCase();
DateTime onlineDay(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

class OnlineBranch {
  final String name, group;
  const OnlineBranch(this.name, this.group);
}

class OnlineSalesMonth {
  final String code, branch;
  final DateTime month;
  final double online, cash, insurance;
  const OnlineSalesMonth({
    required this.code,
    required this.branch,
    required this.month,
    this.online = 0,
    this.cash = 0,
    this.insurance = 0,
  });

  factory OnlineSalesMonth.fromMap(Map<String, dynamic> row, int year) {
    final parts = '${row['month']}'.split('/');
    final month = parts.length == 2 ? int.tryParse(parts[0]) : null;
    final sourceYear = parts.length == 2 ? int.tryParse(parts[1]) : null;
    if (month == null || month < 1 || month > 12 || sourceYear != year) {
      throw StateError('Invalid $year sales month: ${row['month']}');
    }
    double quantity(String key) {
      final value = row[key];
      if (value == null) return 0;
      final parsed = num.tryParse('$value');
      if (parsed == null || !parsed.isFinite) {
        throw StateError('Invalid sales quantity for ${row['item_code']}');
      }
      return parsed.toDouble();
    }

    return OnlineSalesMonth(
      code: '${row['item_code'] ?? ''}'.trim(),
      branch: '${row['branch_name'] ?? ''}'.trim(),
      month: DateTime.utc(year, month),
      online: quantity('online'),
      cash: quantity('cash'),
      insurance: quantity('insurance'),
    );
  }

  String get identity => '$branch\u0000$code\u0000${month.toIso8601String()}';
  double quantity(OnlineSalesScope scope) =>
      online + (scope == OnlineSalesScope.allChannels ? cash + insurance : 0);
}

/// Derived solely from the existing, permission-checked product evidence RPC.
/// Reconciliation and complete history are required before counting stock days.
class OnlineBranchAudit {
  final String branch;
  final bool verified, estimated;
  final int stockedDays, emptyDays;
  final double? currentStock;
  final DateTime through;
  final String note;
  const OnlineBranchAudit({
    required this.branch,
    required this.through,
    this.verified = false,
    this.estimated = false,
    this.stockedDays = 0,
    this.emptyDays = 0,
    this.currentStock,
    this.note = 'Stock history has not been checked.',
  });

  factory OnlineBranchAudit.fromEvidence(
    Map<String, dynamic> row,
    DateTime through,
    DateTime stockDay,
  ) {
    final branch = '${row['branch_name'] ?? ''}';
    double? finite(Object? value) {
      final number = num.tryParse('$value');
      return number != null && number.isFinite ? number.toDouble() : null;
    }

    final current = stockNumber(row['current_rows']) == 1
        ? finite(row['current_qty'])
        : null;
    OnlineBranchAudit unknown(String note) => OnlineBranchAudit(
      branch: branch,
      through: through,
      currentStock: current,
      note: note,
    );
    if (row['reconciled'] != true || current == null) {
      return unknown('Incomplete or unreconciled stock history.');
    }
    if (through.year != 2026 || stockDay.isBefore(through)) {
      return unknown('Stock and analysis dates do not agree.');
    }
    final movements = <DateTime, Map<String, dynamic>>{};
    for (final raw in row['movements'] as List? ?? []) {
      final movement = stockMap(raw);
      final parsed = DateTime.tryParse('${movement['day']}');
      if (parsed == null) return unknown('Invalid movement date.');
      final day = onlineDay(parsed);
      if (movements.containsKey(day) ||
          !day.isAfter(DateTime.utc(2026)) ||
          day.isAfter(stockDay) ||
          movement['bad'] == true) {
        return unknown('Duplicate, out-of-range or invalid movements.');
      }
      movements[day] = movement;
    }
    var balance = finite(row['opening_qty']);
    if (balance == null || balance < 0) {
      return unknown('Opening stock is invalid.');
    }
    var stocked = 0, empty = 0;
    // The January 1 opening is a closing balance; never count it as a full day.
    for (
      var day = DateTime.utc(2026, 1, 2);
      !day.isAfter(stockDay);
      day = day.add(const Duration(days: 1))
    ) {
      final movement = movements[day];
      final net = movement == null ? 0.0 : finite(movement['net']);
      final incoming = movement == null ? 0.0 : finite(movement['incoming']);
      final outgoing = movement == null ? 0.0 : finite(movement['outgoing']);
      if (net == null ||
          incoming == null ||
          outgoing == null ||
          incoming < 0 ||
          outgoing < 0 ||
          (net - (incoming - outgoing)).abs() > .000001) {
        return unknown('Invalid signed movement totals.');
      }
      final before = balance!;
      balance = before + net;
      if (balance < -.000001) {
        return unknown('Negative reconstructed balance.');
      }
      if (day.isAfter(through)) continue;
      // Conservative: even all outgoing before incoming must leave stock.
      // An adjustment day cannot establish a full stocked or empty day.
      if (movement?['adjustment'] == true) continue;
      if (before - outgoing > .000001 && balance > .000001) stocked++;
      if (before.abs() < .000001 &&
          balance.abs() < .000001 &&
          incoming == 0 &&
          outgoing == 0) {
        empty++;
      }
    }
    if ((balance! - current).abs() > .000001) {
      return unknown('Reconstructed balance does not match current stock.');
    }
    final estimated =
        row['assumed_opening'] == true || row['current_assumed_zero'] == true;
    return OnlineBranchAudit(
      branch: branch,
      through: through,
      verified: true,
      estimated: estimated,
      stockedDays: stocked,
      emptyDays: empty,
      currentStock: current,
      note: estimated
          ? 'Reconciled system-stock estimate; an omitted balance was assumed zero.'
          : 'Reconciled system-stock history. Shelf listing is not verified.',
    );
  }
}

class OnlineProductAudit {
  final Map<String, OnlineBranchAudit> branches;
  final DateTime through;
  final Map<String, dynamic> latestMrn;
  const OnlineProductAudit({
    required this.branches,
    required this.through,
    this.latestMrn = const {},
  });
  factory OnlineProductAudit.fromMap(
    Map<String, dynamic> data, {
    DateTime? exposureThrough,
  }) {
    final sourceThrough = DateTime.tryParse('${data['through']}');
    final stockDay = DateTime.tryParse('${data['stock_day']}');
    if (data['status'] != 'ready' ||
        sourceThrough == null ||
        stockDay == null) {
      throw StateError('Stock history is not ready.');
    }
    final through =
        exposureThrough != null && exposureThrough.isBefore(sourceThrough)
        ? exposureThrough
        : sourceThrough;
    final branches = <String, OnlineBranchAudit>{};
    for (final raw in data['branches'] as List? ?? []) {
      final row = stockMap(raw);
      final key = onlineKey('${row['branch_name'] ?? ''}');
      if (branches.containsKey(key)) {
        throw StateError('Ambiguous branch in stock history.');
      }
      branches[key] = OnlineBranchAudit.fromEvidence(
        row,
        onlineDay(through),
        onlineDay(stockDay),
      );
    }
    return OnlineProductAudit(
      branches: branches,
      through: onlineDay(through),
      latestMrn: stockMap(data['latest_mrn']),
    );
  }
}

class OnlineOverviewSnapshot {
  final StockCatalogResult catalog;
  final List<OnlineBranch> branches;
  final List<OnlineSalesMonth> sales;
  final Map<String, String> purchaseStatuses;
  final DateTime loadedAt;

  /// Non-null for the server register; the page must not recalculate these rows.
  final List<OnlineOverviewRow>? preparedRows;
  final String generation, refreshStatus;
  final Map<String, dynamic> serverMeta;
  const OnlineOverviewSnapshot({
    required this.catalog,
    required this.branches,
    required this.sales,
    required this.loadedAt,
    this.purchaseStatuses = const {},
    this.preparedRows,
    this.generation = '',
    this.refreshStatus = 'complete',
    this.serverMeta = const {},
  });
}

class OnlineOverviewRow {
  final StockCatalogItem item;
  final OnlineRank rank;
  final String reason, purchaseStatus, supply, action;
  final double sales25, comparable25, sales26, recentQty, retail;
  final int sellingMonths;
  final bool priceKnown;
  final double? onlineStock;
  final int? stockedDays;
  final List<String> branchNames;
  final double? knownOnlineStock;
  final int? reportedBranches, stockedBranches;
  final List<String> missingBranches;
  final Map<String, dynamic> classification;
  const OnlineOverviewRow({
    required this.item,
    required this.rank,
    required this.reason,
    required this.purchaseStatus,
    required this.supply,
    required this.action,
    required this.sales25,
    required this.comparable25,
    required this.sales26,
    required this.recentQty,
    required this.retail,
    required this.sellingMonths,
    required this.priceKnown,
    required this.onlineStock,
    required this.stockedDays,
    required this.branchNames,
    this.knownOnlineStock,
    this.reportedBranches,
    this.stockedBranches,
    this.missingBranches = const [],
    this.classification = const {},
  });
  double? get estimatedValue => priceKnown ? sales26 * retail : null;
  double? get displayedStock => knownOnlineStock ?? onlineStock;
  double get otherBranchStock {
    final quantity = stockNumber(item.data['other_branch_stock']);
    return quantity.isFinite ? quantity : 0;
  }

  double? get storeStock =>
      item.stockAvailable && item.data['store_stock'] is num
      ? item.number('store_stock')
      : null;
  double? get combinedStock => onlineStock == null || storeStock == null
      ? null
      : onlineStock! + storeStock!;
  int? get reportCount =>
      reportedBranches ?? (onlineStock == null ? null : branchNames.length);
  bool get partialStock =>
      reportCount != null && reportCount! < branchNames.length;
  String get stockCoverage => reportCount == null
      ? 'Reports not checked'
      : '$reportCount / ${branchNames.length} branches reported';
  String get stockCaption =>
      partialStock ? 'Partial total · $stockCoverage' : stockCoverage;
  int? get branchesWithStock {
    final stock = displayedStock;
    return stockedBranches ??
        (branchNames.length == 1 && stock != null ? (stock > 0 ? 1 : 0) : null);
  }

  String get availability {
    if ((reportCount ?? 0) == 0) return 'Stock reports unavailable';
    final count = branchesWithStock;
    if (count == null) return 'Branch stock count unavailable';

    final total = branchNames.length;
    final branchLabel = total == 1 ? 'branch' : 'branches';
    final status = 'Stock in $count of $total $branchLabel';
    if (count == 0 && (displayedStock ?? 0) < 0) {
      return '$status · negative balance';
    }
    return partialStock ? '$status · partial reports' : status;
  }

  bool get hasAbcmt => classification['version'] == 'abcmt-online-v2';
  Map<String, dynamic> get classThresholds =>
      stockMap(classification['thresholds']);
  int? get stockCoverSalesWindowDays {
    final through = DateTime.tryParse('${classThresholds['through']}');
    if (through == null) return null;
    final end = DateTime.utc(through.year, through.month + 1);
    final start = DateTime.utc(end.year, end.month - 3);
    return end.difference(start).inDays;
  }

  double? get stockCoverDays =>
      stockCoverFor(stock: partialStock ? null : onlineStock, sales: recentQty);

  double? stockCoverFor({required double? stock, required double? sales}) {
    final windowDays = stockCoverSalesWindowDays;
    if (stock == null ||
        stock < 0 ||
        sales == null ||
        sales <= 0 ||
        windowDays == null) {
      return null;
    }
    return stock * windowDays / sales;
  }

  Map<String, dynamic> get salesForecast =>
      stockMap(classification['forecast']);
  Map<String, dynamic> get actualSales =>
      stockMap(classification['actual_sales']);
  bool get usesActualSales => actualSales.isNotEmpty;
  Map<String, dynamic> get productAge =>
      stockMap(classification['product_age'] ?? salesForecast['product_age']);
  bool get hasSalesForecast =>
      salesForecast['status'] == 'ready' &&
      (rank == OnlineRank.a || rank == OnlineRank.b || rank == OnlineRank.c);
  List<String> get forecastBranches =>
      (salesForecast['suggested_branches'] as List? ?? const [])
          .whereType<String>()
          .toList();
  Map<String, dynamic> get modelPrediction =>
      rank == OnlineRank.m ||
          rank == OnlineRank.n ||
          rank == OnlineRank.t ||
          rank == OnlineRank.s ||
          rank == OnlineRank.review
      ? const {'status': 'business_rule', 'use': 'withheld'}
      : stockMap(classification['ml']);
  String get evidenceStatus =>
      '${classification['evidence_status'] ?? 'Not supplied'}';
  String get evidenceNote => '${classification['evidence_note'] ?? ''}';
  double get networkSales26 => stockNumber(classification['sales_2026']);
  int get sellingBranches26 =>
      stockNumber(classification['selling_branches_2026']).toInt();
  int get networkBranchCount =>
      stockNumber(classification['total_branches']).toInt();
  double get networkCoverage => stockNumber(classification['coverage_2026']);
  String? get aRouteLabel => switch (classification['priority_route']) {
    'wide_branch_sales' => 'Sales in many branches',
    'high_sales_qty' => 'High Qty sold',
    'high_sales_value' => 'High sales value',
    'forecast_quantity' => 'High expected Qty',
    'forecast_value' => 'High expected sales value',
    'forecast_sales' => 'Expected online sales',
    'network_quantity' => 'Network demand',
    'concentrated_quantity' => 'Concentrated demand',
    'sales_value' => 'High sales value',
    'premium_repeat' => 'Regular sales, high price',
    _ => null,
  };
  List<String> get priorityBranches =>
      (classification['priority_branches'] as List? ?? const [])
          .whereType<String>()
          .toList();
  String get aQualification =>
      aRouteLabel ?? (rank == OnlineRank.a ? 'Earlier A rule' : '—');
  String get repeatEvidence => usesActualSales
      ? '${actualSales['selling_months']} months with sales in the last 6 full months'
      : classification['priority_route'] == 'premium_repeat'
      ? '${classification['selling_periods_last_12']} of the last 4 three-month periods with online sales'
      : '${classification['selling_months_2026'] ?? sellingMonths} positive-selling months in 2026';
  String get cExplanation => usesActualSales
      ? reason
      : hasAbcmt
      ? '$reason. $evidenceNote'
      : 'Rebuild the prepared data to use ABCMT.';

  factory OnlineOverviewRow.fromPreparedMap(
    Map<String, dynamic> map,
    List<String> branches,
  ) {
    final item = StockCatalogItem(stockMap(map['item']));
    final rank = OnlineRank.values
        .where((rank) => rank.name == map['rank'])
        .firstOrNull;
    if (item.code.isEmpty || rank == null || map['code'] != item.code) {
      throw StateError('Invalid prepared online product. Reload the register.');
    }
    return OnlineOverviewRow(
      item: item,
      rank: rank,
      reason: '${map['reason'] ?? ''}',
      purchaseStatus: '${map['purchase_status'] ?? 'Not assigned'}',
      supply: '${map['supply'] ?? ''}',
      action: '${map['action'] ?? ''}',
      sales25: stockNumber(map['sales25']),
      comparable25: stockNumber(map['comparable25']),
      sales26: stockNumber(map['sales26']),
      recentQty: stockNumber(map['recent_qty']),
      retail: stockNumber(map['retail']),
      sellingMonths: stockNumber(map['selling_months']).toInt(),
      priceKnown: map['price_known'] == true,
      onlineStock: map['online_stock'] == null
          ? null
          : stockNumber(map['online_stock']),
      stockedDays: map['stocked_days'] == null
          ? null
          : stockNumber(map['stocked_days']).toInt(),
      branchNames: List.unmodifiable(branches),
      knownOnlineStock: map['known_online_stock'] == null
          ? null
          : stockNumber(map['known_online_stock']),
      reportedBranches: map['reported_branches'] == null
          ? null
          : stockNumber(map['reported_branches']).toInt(),
      stockedBranches: map['stocked_branches'] == null
          ? null
          : stockNumber(map['stocked_branches']).toInt(),
      missingBranches: (map['missing_branches'] as List? ?? [])
          .map((name) => '$name')
          .toList(),
      classification: stockMap(map['classification']),
    );
  }
}
