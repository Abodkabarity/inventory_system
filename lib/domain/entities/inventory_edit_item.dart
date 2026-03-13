class InventoryEditItem {
  final String itemCode;
  final String itemName;
  final num oldQty;
  final num newQty;
  final num diff;
  final String reason;
  final String branch;
  final DateTime createdAt;

  InventoryEditItem({
    required this.itemCode,
    required this.itemName,
    required this.oldQty,
    required this.newQty,
    required this.diff,
    required this.reason,
    required this.branch,
    required this.createdAt,
  });
}
