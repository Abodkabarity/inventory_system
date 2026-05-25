class ProductMovement {
  final String branch;

  final String itemCode;

  final String itemName;

  final String barcode;

  final String movementType;

  final num qty;

  final DateTime createdAt;

  ProductMovement({
    required this.branch,
    required this.itemCode,
    required this.itemName,
    required this.barcode,
    required this.movementType,
    required this.qty,
    required this.createdAt,
  });
}
