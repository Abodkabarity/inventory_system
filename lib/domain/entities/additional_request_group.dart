class AdditionalRequestGroup {
  final String groupId;
  final String branchName;
  final DateTime createdAt;
  final int itemsCount;
  final bool done;

  AdditionalRequestGroup({
    required this.groupId,
    required this.branchName,
    required this.createdAt,
    required this.itemsCount,
    required this.done,
  });
}
