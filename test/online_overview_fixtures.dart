import 'package:daily_order/data/datasources/remote/online_overview_remote_ds.dart';
import 'package:daily_order/domain/entities/online_overview.dart';
import 'package:daily_order/domain/entities/stock_catalog.dart';

StockCatalogItem onlineItem(
  String code, {
  double retail = 10,
  String status = '1#NORMAL PURCHASE',
  String purchase = 'AVAILABLE',
  Map<String, dynamic> extra = const {},
}) => StockCatalogItem({
  'item_code': code,
  'item_name': '$code Product',
  'item_status': status,
  'purchase_status_items': purchase,
  'retail': retail,
  'store_stock': 40,
  'supplier': 'Example Supplier',
  'category': 'General',
  'years': <String, dynamic>{},
  ...extra,
});

OnlineSalesMonth onlineSale(
  String code,
  int year,
  int month,
  double qty, {
  String branch = 'Web Shop',
  double cash = 0,
  double insurance = 0,
}) => OnlineSalesMonth(
  code: code,
  branch: branch,
  month: DateTime.utc(year, month),
  online: qty,
  cash: cash,
  insurance: insurance,
);

OnlineOverviewSnapshot onlineSnapshot({
  List<StockCatalogItem>? items,
  List<OnlineSalesMonth>? sales,
  List<OnlineBranch> branches = const [OnlineBranch('Web Shop', '71')],
  DateTime? loadedAt,
  Map<String, String> purchaseStatuses = const {},
  Map<String, dynamic> serverMeta = const {},
}) => OnlineOverviewSnapshot(
  catalog: StockCatalogResult(
    rows:
        items ??
        [
          onlineItem('FAST'),
          onlineItem('EXPENSIVE', retail: 2000),
          onlineItem('HISTORICAL', purchase: 'OOS'),
          onlineItem('SLOW'),
          onlineItem('NEW', extra: {'added_date_time': '2026-10-20'}),
          onlineItem('UNTESTED'),
        ],
    summary: {'items': items?.length ?? 6},
    meta: const {
      'refreshed_at': '2026-10-30T06:00:00Z',
      'reference_version': 'v1',
    },
  ),
  sales:
      sales ??
      [
        onlineSale('FAST', 2026, 8, 100),
        onlineSale('FAST', 2026, 9, 100),
        onlineSale('FAST', 2026, 10, 10),
        onlineSale('EXPENSIVE', 2026, 8, 1),
        onlineSale('EXPENSIVE', 2026, 9, 1),
        onlineSale('HISTORICAL', 2025, 8, 80),
        onlineSale('HISTORICAL', 2025, 9, 60),
      ],
  branches: branches,
  purchaseStatuses: purchaseStatuses,
  serverMeta: serverMeta,
  loadedAt: loadedAt ?? DateTime.utc(2026, 10, 30, 6),
);

OnlineProductAudit onlineAudit({
  int stocked = 200,
  int empty = 0,
  double stock = 2,
  String branch = 'Web Shop',
  bool verified = true,
}) => OnlineProductAudit(
  through: DateTime.utc(2026, 10, 28),
  branches: {
    onlineKey(branch): OnlineBranchAudit(
      branch: branch,
      through: DateTime.utc(2026, 10, 28),
      verified: verified,
      stockedDays: stocked,
      emptyDays: empty,
      currentStock: stock,
    ),
  },
);

OnlineOverviewRow onlinePreparedRow(
  StockCatalogItem item, {
  List<String> branches = const ['Web Shop'],
  int networkBranches = 1,
  bool rebuilt = false,
  Map<String, dynamic> extra = const {},
}) {
  final code = item.code;
  final qty = code == 'FAST'
      ? 210
      : code == 'EXPENSIVE'
      ? 2
      : 0;
  final rank = onlineKey(item.text('sales_orientation')) == 'INHOUSE'
      ? 's'
      : switch (code) {
          'FAST' => 'a',
          'MEDIUM' => 'b',
          'EXPENSIVE' => 'c',
          'NEW-N' => 'n',
          'HISTORICAL' => rebuilt ? 't' : 'c',
          'SLOW' => 't',
          'NEW' => 'm',
          _ => 'review',
        };
  return OnlineOverviewRow.fromPreparedMap({
    'item': item.data,
    'code': code,
    'rank': rank,
    'reason':
        item.data['test_actual_reason'] ??
        '$rank from prepared network evidence',
    'purchase_status': item.purchaseStatus,
    'supply': 'Stock in STORE',
    'action': item.purchaseStatus == 'OOS'
        ? 'Purchase follow-up; retain demand class'
        : 'Review branch demand',
    'sales26': qty,
    'sales25': code == 'HISTORICAL' ? 140 : 0,
    'recent_qty': qty,
    'selling_months': qty > 0 ? 3 : 0,
    'retail': item.number('retail'),
    'price_known': item.number('retail') > 0,
    'online_stock': code == 'UNTESTED'
        ? null
        : code == 'NEW' || code == 'NEW-N'
        ? 0
        : 5 * branches.length,
    'known_online_stock': code == 'UNTESTED'
        ? null
        : code == 'NEW' || code == 'NEW-N'
        ? 0
        : 5 * branches.length,
    'reported_branches': code == 'UNTESTED' ? 0 : branches.length,
    'stocked_branches': code == 'UNTESTED' || code == 'NEW' || code == 'NEW-N'
        ? 0
        : branches.length,
    'classification': {
      'version': 'abcmt-online-v2',
      'rules_version': 'abcmt-s-v1',
      if (item.data['test_forecast'] != null)
        'forecast': item.data['test_forecast'],
      'sales_orientation': item.data['sales_orientation'],
      'sales_2026': qty,
      'sales_2025': code == 'HISTORICAL' ? 140 : 0,
      'selling_branches_2026': qty > 0 ? networkBranches : 0,
      'total_branches': networkBranches,
      'coverage_2026': qty > 0 ? 1 : 0,
      'selling_months_2026': qty > 0 ? 3 : 0,
      'recent_3_qty': qty,
      'evidence_status': code == 'UNTESTED' ? 'insufficient' : 'supported',
      'evidence_note': 'Prepared from online stock and sales.',
      'thresholds': {
        'low': 5,
        'median': 18,
        'high': 63,
        'minimum_A_branches': networkBranches,
        'through': '2026-09-30',
      },
      'ml': {
        'status': 'advisory',
        'class': qty > 5 ? 'a' : 'c',
        'score': .8,
        'use': 'advisory_only',
      },
      if (item.data['test_actual_sales'] != null) ...{
        'actual_sales': item.data['test_actual_sales'],
        'priority_route': 'wide_branch_sales',
        'priority_branches': branches,
      },
    },
    ...extra,
  }, branches);
}

class FakeOnlineOverviewSource implements OnlineOverviewDataSource {
  final OnlineOverviewSnapshot snapshot;
  bool fail = false;
  int audits = 0;
  int monthlyLoads = 0;
  bool failMonthly = false;
  Future<void>? monthlyWait;
  List<Map<String, dynamic>>? monthlyRows;
  bool rebuilt = false;
  int refreshes = 0;
  bool failAvailability = false;
  Map<String, dynamic>? availabilityResponse;
  final availabilityGenerations = <String>[];
  FakeOnlineOverviewSource([OnlineOverviewSnapshot? snapshot])
    : snapshot = snapshot ?? onlineSnapshot();
  @override
  Future<OnlineOverviewSnapshot> load({
    String branch = '',
    OnlineSalesScope scope = OnlineSalesScope.onlineOnly,
    bool Function()? isCancelled,
    void Function(String message)? onProgress,
  }) async {
    if (fail) throw StateError('Test connection unavailable');
    final selected = snapshot.branches
        .where((b) => branch.isEmpty || b.name == branch)
        .map((b) => b.name)
        .toList();
    final rows = [
      for (final item in snapshot.catalog.rows)
        onlinePreparedRow(
          item,
          branches: selected,
          networkBranches: snapshot.branches.length,
          rebuilt: rebuilt,
        ),
    ];
    return OnlineOverviewSnapshot(
      catalog: snapshot.catalog,
      branches: snapshot.branches,
      sales: const [],
      loadedAt: snapshot.loadedAt,
      purchaseStatuses: snapshot.purchaseStatuses,
      preparedRows: rows,
      generation: rebuilt ? 'prepared-v2' : 'prepared-v1',
      serverMeta: {
        'refreshed_at': snapshot.loadedAt.toIso8601String(),
        'classification_through': '2026-09-30',
        'thresholds': {'premium_retail_aed': 1000},
        ...snapshot.serverMeta,
      },
    );
  }

  @override
  Future<void> requestRefresh() async {
    refreshes++;
    rebuilt = true;
  }

  @override
  Future<Map<String, dynamic>> refreshState() async => {'status': 'complete'};

  @override
  Future<Map<String, dynamic>> branchAvailability({
    required String generation,
  }) async {
    availabilityGenerations.add(generation);
    if (failAvailability) throw StateError('Availability unavailable');
    if (availabilityResponse != null) return availabilityResponse!;
    final prepared = snapshot.catalog.rows
        .map((item) => onlinePreparedRow(item))
        .toList();
    return {
      'generation': generation,
      'stock_day': '2026-11-17',
      'rows': [
        for (final branch in snapshot.branches)
          for (final rank in [OnlineRank.a, OnlineRank.b, OnlineRank.c])
            {
              'branch_name': branch.name,
              'rank': rank.name,
              'total': prepared.where((row) => row.rank == rank).length,
              'available': prepared
                  .where(
                    (row) => row.rank == rank && (row.onlineStock ?? 0) > 0,
                  )
                  .length,
              'unknown': prepared
                  .where((row) => row.rank == rank && row.onlineStock == null)
                  .length,
            },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> forecastDetails(
    String code, {
    required String generation,
  }) async => Map<String, dynamic>.from(
    snapshot.catalog.rows
                .singleWhere((item) => item.code == code)
                .data['test_forecast']
            as Map? ??
        {},
  );

  @override
  Future<List<Map<String, dynamic>>> stockBreakdown(
    String code, {
    String? generation,
  }) async => [
    for (final branch in snapshot.branches)
      {
        'branch_name': branch.name,
        'stock': 5,
        'reported': true,
        'recent_sales': code == 'FAST' ? 210 / snapshot.branches.length : 0,
      },
    {'branch_name': 'Retail outlet', 'stock': 999, 'sales_2026': 999},
  ];

  @override
  Future<OnlineProductAudit> audit(
    String code, {
    required String generation,
  }) async {
    audits++;
    return onlineAudit(
      stocked: code == 'HISTORICAL' ? 100 : 200,
      empty: code == 'HISTORICAL' ? 40 : 0,
    );
  }

  @override
  Future<Map<String, dynamic>> recentOnlineSales(
    String code, {
    required String generation,
    required String branch,
  }) async => recentSales;

  Map<String, dynamic> recentSales = {
    'qty': 50,
    'from': '2026-09-22',
    'through': '2026-11-05',
    'stock_day': '2026-11-05',
  };

  @override
  Future<List<Map<String, dynamic>>> monthlyOnlineSales(
    String code, {
    required String generation,
    required String branch,
  }) async {
    monthlyLoads++;
    await monthlyWait;
    if (failMonthly) throw StateError('Monthly sales unavailable');
    return monthlyRows ??
        [
          {'month': '01/2025', 'total': 3},
          {'month': '01/2026', 'total': 5},
          {'month': '02/2026', 'total': -1},
        ];
  }
}
