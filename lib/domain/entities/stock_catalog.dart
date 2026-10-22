import 'stock_management.dart';
import 'stock_distribution.dart';

/// Item Report identities are preserved; calculated fields are snapshot facts.
class StockCatalogItem extends StockManagementItem {
  final StockDistributionRules distributionRules;
  const StockCatalogItem(
    super.data, {
    this.distributionRules = const StockDistributionRules(),
  });
  StockCatalogItem withDistributionRules(StockDistributionRules rules) =>
      StockCatalogItem(data, distributionRules: rules);
  StockDistribution get distributionStatus => distributionRules.evaluate(this);

  /// Item Report purchase status, separate from calculated stock signals.
  String get itemStatus => text('item_status').trim();
  bool get surge => data['demand_surge'] == true;
  bool get newDemand => data['new_demand'] == true;
  bool get salesExceedStock => number('recent_sales') > number('total_stock');
  double? get growth =>
      data['growth_percent'] == null ? null : number('growth_percent');
  String get signal => distributionStatus.needsDistribution
      ? 'New · Needs distribution'
      : surge
      ? 'Sales increase'
      : newDemand
      ? 'New demand'
      : salesExceedStock
      ? 'Sales > stock'
      : status == 'no_stock'
      ? 'No stock'
      : status == 'low_cover'
      ? 'Low cover'
      : status == 'no_sales'
      ? 'No recent sales'
      : 'Healthy';
}

class StockCatalogQuery {
  final String search, signal, category, supplier, sort;
  final int offset, limit;
  const StockCatalogQuery({
    this.search = '',
    this.signal = '',
    this.category = '',
    this.supplier = '',
    this.sort = 'name',
    this.offset = 0,
    this.limit = 50,
  });
  Map<String, dynamic> get params => {
    'p_search': search.trim(),
    'p_signal': signal,
    'p_category': category,
    'p_supplier': supplier,
    'p_sort': sort,
    'p_offset': offset,
    'p_limit': limit,
  };
}

class StockCatalogResult {
  final List<StockCatalogItem> rows;
  final Map<String, dynamic> summary, meta;
  final List<String> categories, suppliers;
  const StockCatalogResult({
    required this.rows,
    required this.summary,
    required this.meta,
    this.categories = const [],
    this.suppliers = const [],
  });
  StockCatalogResult.fromMap(Map<String, dynamic> map)
    : rows = (map['rows'] as List? ?? [])
          .map((r) => StockCatalogItem(stockMap(r)))
          .toList(),
      summary = stockMap(map['summary']),
      meta = stockMap(map['meta']),
      categories = (map['categories'] as List? ?? []).map((r) => '$r').toList(),
      suppliers = (map['suppliers'] as List? ?? []).map((r) => '$r').toList();
  int get total => stockNumber(summary['items']).toInt();
}

/// Calendar months with no recorded sales remain zero within the uploaded span.
List<Map<String, dynamic>> catalogMonthlySeries(StockCatalogItem item) {
  final raw = item.list('monthly_sales');
  final byMonth = {for (final r in raw) r['month'].toString(): r};
  final through = DateTime.tryParse(
    (stockMap(item.data['meta'])['monthly_sales_through'] ??
                stockMap(item.data['meta'])['sales_2026_through'])
            ?.toString() ??
        '',
  );
  final parsed =
      raw
          .map((r) {
            final p = '${r['month']}'.split('/');
            return p.length == 2
                ? DateTime(int.tryParse(p[1]) ?? 2025, int.tryParse(p[0]) ?? 1)
                : null;
          })
          .whereType<DateTime>()
          .toList()
        ..sort();
  if (through == null && parsed.isEmpty) return [];
  final end = through ?? parsed.last;
  return [
    for (
      var date = DateTime(2025);
      !date.isAfter(end);
      date = DateTime(date.year, date.month + 1)
    )
      byMonth['${date.month.toString().padLeft(2, '0')}/${date.year}'] ??
          {
            'month': '${date.month.toString().padLeft(2, '0')}/${date.year}',
            'total': 0,
          },
  ];
}

List<int> catalogSalesYears(StockCatalogItem item) => stockSalesYears(item);

List<double?> catalogMovingAverage(List<Map<String, dynamic>> months) => [
  for (var i = 0; i < months.length; i++)
    i < 2
        ? null
        : (stockNumber(months[i]['total']) +
                  stockNumber(months[i - 1]['total']) +
                  stockNumber(months[i - 2]['total'])) /
              3,
];

List<Map<String, dynamic>> catalogBranchRows(StockCatalogItem item) {
  final meta = stockMap(item.data['meta']);
  final baselineDays = stockNumber(meta['baseline_days']);
  final days = baselineDays + stockNumber(meta['recent_days']);
  return [
    for (final row in item.list('branches'))
      {
        ...row,
        'baseline_daily': baselineDays > 0
            ? stockNumber(row['baseline_sales']) / baselineDays
            : null,
        'cover': stockNumber(row['stock']) <= 0
            ? 0.0
            : stockNumber(row['recent_sales']) > 0 && days > 0
            ? stockNumber(row['stock']) /
                  (stockNumber(row['recent_sales']) / days)
            : null,
      },
  ];
}
