import 'stock_management.dart';

class StockExpiryQuery {
  final String search, reviewState, urgency;
  final int offset, limit;
  const StockExpiryQuery({
    this.search = '',
    this.reviewState = 'pending',
    this.urgency = '',
    this.offset = 0,
    this.limit = 30,
  });
  Map<String, dynamic> get params => {
    'p_search': search.trim(),
    'p_review_state': reviewState,
    'p_urgency': urgency,
    'p_offset': offset,
    'p_limit': limit,
  };
}

class StockExpiryAlert {
  final Map<String, dynamic> data;
  const StockExpiryAlert(this.data);
  String text(String key) => data[key]?.toString() ?? '';
  double number(String key) => stockNumber(data[key]);
  String get code => text('item_code');
  String get expiry => text('expiry_date');
  String get key => '$code:$expiry';
  int get days => number('days_left').toInt();
  bool get reviewed => data['is_reviewed'] == true;
  bool get newReceipts => data['new_receipts'] == true;
  String get note => text('note');
  StockManagementItem get product =>
      StockManagementItem({...data, ...stockMap(data['product_data'])});
  String? get reviewVersion => data['review_updated_at']?.toString();
  List<Map<String, dynamic>> get receipts =>
      (data['receipts'] as List? ?? []).map(stockMap).toList();
}

class StockExpiryResult {
  final List<StockExpiryAlert> rows;
  final int total;
  final Map<String, dynamic> summary, meta;
  const StockExpiryResult({
    required this.rows,
    required this.total,
    required this.summary,
    required this.meta,
  });
  factory StockExpiryResult.fromMap(Map<String, dynamic> data) =>
      StockExpiryResult(
        rows: (data['rows'] as List? ?? [])
            .map((r) => StockExpiryAlert(stockMap(r)))
            .toList(),
        total: stockNumber(data['total']).toInt(),
        summary: stockMap(data['summary']),
        meta: stockMap(data['meta']),
      );
}
