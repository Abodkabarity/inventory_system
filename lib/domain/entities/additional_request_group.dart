class AdditionalRequestGroup {
  final String groupId;
  final String branchName;
  final DateTime createdAt;
  final int itemsCount;

  final String status;
  final String? storeStatus;
  final String itemNames;
  final String itemCodes;

  AdditionalRequestGroup({
    required this.groupId,
    required this.branchName,
    required this.createdAt,
    required this.itemsCount,
    required this.status,
    required this.itemNames,
    required this.itemCodes,
    this.storeStatus,
  });
}
