class AllocationSourceRow {
  final String branch;
  final String itemCode;
  final String itemName;
  final String category;
  final String itemPurchaseType;
  final num reorderQty;
  final num finalReorderQty;
  final num extraQtyMoreThanMonth;
  final num branchStock;
  final num demandFor30Days;
  final num branchStockDays;
  final String stockCoverText;

  const AllocationSourceRow({
    required this.branch,
    required this.itemCode,
    required this.itemName,
    required this.category,
    required this.itemPurchaseType,
    required this.reorderQty,
    required this.finalReorderQty,
    required this.extraQtyMoreThanMonth,
    required this.branchStock,
    required this.demandFor30Days,
    required this.branchStockDays,
    required this.stockCoverText,
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
      itemPurchaseType: _s(map['item_purchase_type']),
      reorderQty: _n(map['reorder_qty']),
      finalReorderQty: _n(
        map['final_reorder_qty_store_stock_gt_0'] ?? map['final_reorder_qty'],
      ),
      extraQtyMoreThanMonth: _n(
        map['extra_qty_more_than_month'] ?? map['extra_qty'],
      ),
      branchStock: _n(map['branch_stock']),
      demandFor30Days: _n(map['demand_for_30_days']),
      branchStockDays: _n(map['branch_stock_days']),
      stockCoverText: _s(map['stock_cover_text']),
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
