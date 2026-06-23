class AllocationSourceRow {
  final String branch;
  final String itemCode;
  final String itemName;
  final String category;
  final num reorderQty;
  final num finalReorderQty;
  final num extraQtyMoreThanMonth;

  const AllocationSourceRow({
    required this.branch,
    required this.itemCode,
    required this.itemName,
    required this.category,
    required this.reorderQty,
    required this.finalReorderQty,
    required this.extraQtyMoreThanMonth,
  });

  num get shortage => reorderQty - finalReorderQty;

  bool get hasShortage => shortage > 0;

  bool get hasExtra => extraQtyMoreThanMonth > 0;

  factory AllocationSourceRow.fromMap(Map<String, dynamic> map) {
    return AllocationSourceRow(
      branch: _s(map['branch']),
      itemCode: _s(map['item_code']),
      itemName: _s(map['item_name']),
      category: _s(map['category']),
      reorderQty: _n(map['reorder_qty']),
      finalReorderQty: _n(map['final_reorder_qty_store_stock_gt_0']),
      extraQtyMoreThanMonth: _n(map['extra_qty_more_than_month']),
    );
  }

  static String _s(dynamic value) => (value ?? '').toString().trim();

  static num _n(dynamic value) {
    if (value is num) return value;

    final text = (value ?? '')
        .toString()
        .replaceAll(',', '')
        .replaceAll('NON FORMULARY', '')
        .replaceAll('-', '')
        .trim();

    return num.tryParse(text) ?? 0;
  }
}
