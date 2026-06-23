class AllocationResultRow {
  final String fromBranch;
  final String itemCode;
  final String itemName;
  final num qty;
  final String toBranch;
  final String category;

  const AllocationResultRow({
    required this.fromBranch,
    required this.itemCode,
    required this.itemName,
    required this.qty,
    required this.toBranch,
    required this.category,
  });

  Map<String, dynamic> toMap() {
    return {
      'from_branch': fromBranch,
      'item_code': itemCode,
      'item_name': itemName,
      'qty': qty,
      'to_branch': toBranch,
      'category': category,
    };
  }

  factory AllocationResultRow.fromMap(Map<String, dynamic> map) {
    return AllocationResultRow(
      fromBranch: (map['from_branch'] ?? '').toString(),
      itemCode: (map['item_code'] ?? '').toString(),
      itemName: (map['item_name'] ?? '').toString(),
      qty: map['qty'] is num
          ? map['qty'] as num
          : num.tryParse((map['qty'] ?? '0').toString()) ?? 0,
      toBranch: (map['to_branch'] ?? '').toString(),
      category: (map['category'] ?? '').toString(),
    );
  }
}
