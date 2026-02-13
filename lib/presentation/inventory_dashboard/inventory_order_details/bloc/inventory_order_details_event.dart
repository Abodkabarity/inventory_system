abstract class InventoryOrderDetailsEvent {
  const InventoryOrderDetailsEvent();
}

class SetRunDate extends InventoryOrderDetailsEvent {
  final String runDate;
  const SetRunDate(this.runDate);
}

class LoadItems extends InventoryOrderDetailsEvent {
  final String branchName; // branch name OR '__ALL__'
  final int pageIndex;

  const LoadItems({required this.branchName, required this.pageIndex});
}
