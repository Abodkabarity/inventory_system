class AdditionalRequestGroup {
  final String groupId;
  final String branchName;
  final DateTime createdAt;
  final int itemsCount;

  final String status;
  final String? storeStatus;
  final String itemNames;
  final String contactLogistic;
  final num? requestQty;
  final String itemCodes;
  final num? branchStock;
  final num? storeStock;
  final num? sales;
  final num? finalReorder;

  AdditionalRequestGroup({
    required this.groupId,
    required this.branchName,
    required this.createdAt,
    required this.itemsCount,
    required this.status,
    required this.itemNames,
    required this.itemCodes,
    this.storeStatus,
    required this.contactLogistic,
    this.requestQty,
    this.branchStock,
    this.storeStock,
    this.sales,
    this.finalReorder,
  });
}
