class StockManagementQuery {
  final String search, status, category, supplier, sort;
  final String? receivedFrom, receivedTo;
  final int offset, limit;

  const StockManagementQuery({
    this.search = '',
    this.status = '',
    this.category = '',
    this.supplier = '',
    this.sort = 'latest_mrn',
    this.receivedFrom,
    this.receivedTo,
    this.offset = 0,
    this.limit = 50,
  });

  Map<String, dynamic> get params => {
    'p_search': search.trim(),
    'p_status': status,
    'p_category': category,
    'p_supplier': supplier,
    'p_sort': sort,
    'p_received_from': receivedFrom,
    'p_received_to': receivedTo,
    'p_offset': offset,
    'p_limit': limit,
  };
}

double stockNumber(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
Map<String, dynamic> stockMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};

class StockManagementItem {
  final Map<String, dynamic> data;
  const StockManagementItem(this.data);
  String text(String key) => data[key]?.toString() ?? '';
  double number(String key) => stockNumber(data[key]);
  String get code => text('item_code');
  String get name => text('item_name');
  bool get isCdReceipt => text('receipt_source') == 'mrn_cd_apg_2026';
  String get warehouse => text('warehouse');
  String get registerKey =>
      text('register_key').isEmpty ? code : text('register_key');
  double get receiptTotal => data.containsKey('total_qty')
      ? number('total_qty')
      : stockNumber(data['received_quantity'] ?? data['last_mrn_qty']);
  double get receiptBonus => number('bonus');
  String get purchaseStatus {
    final value = text('purchase_status_items').trim();
    return value.isEmpty ? 'Not assigned' : value;
  }

  String get status => text('stock_status');
  bool get stockAvailable => data['stock_unavailable'] != true;
  double? get storeTotalPercent => stockAvailable && number('total_stock') > 0
      ? number('store_stock') / number('total_stock') * 100
      : null;
  double? get stockSalesPercent => stockAvailable && number('recent_sales') > 0
      ? number('total_stock').clamp(0, double.infinity) /
            number('recent_sales') *
            100
      : null;
  double? get days =>
      data['days_on_hand'] == null ? null : number('days_on_hand');
  double? get ratio => data['store_branches_ratio'] == null
      ? null
      : number('store_branches_ratio');
  Map<String, dynamic> year(int year) =>
      stockMap(stockMap(data['years'])['$year']);
  List<Map<String, dynamic>> list(String key) =>
      (data[key] as List? ?? []).map(stockMap).toList();
}

/// Sales years shared by all Stock Management views and exports.
List<int> stockSalesYears(StockManagementItem item) {
  var last = 2026;
  final meta = stockMap(item.data['meta']);
  final through = DateTime.tryParse('${meta['monthly_sales_through']}');
  if (through != null && through.year > last) last = through.year;
  for (final key in stockMap(item.data['years']).keys) {
    final year = int.tryParse(key);
    if (year != null && year > last && year <= 2099) last = year;
  }
  return [for (var year = 2025; year <= last; year++) year];
}

class StockManagementResult {
  final List<StockManagementItem> rows;
  final Map<String, dynamic> summary, meta;
  final List<String> categories, suppliers;
  const StockManagementResult({
    required this.rows,
    required this.summary,
    required this.meta,
    this.categories = const [],
    this.suppliers = const [],
  });
  factory StockManagementResult.fromMap(Map<String, dynamic> map) =>
      StockManagementResult(
        rows: (map['rows'] as List? ?? [])
            .map((row) => StockManagementItem(stockMap(row)))
            .toList(),
        summary: stockMap(map['summary']),
        meta: stockMap(map['meta']),
        categories: (map['categories'] as List? ?? [])
            .map((e) => '$e')
            .toList(),
        suppliers: (map['suppliers'] as List? ?? []).map((e) => '$e').toList(),
      );
  int get total => stockNumber(summary['items']).toInt();
}
