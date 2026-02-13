abstract class InventoryOrdersEvent {
  const InventoryOrdersEvent();
}

class SetRunDate extends InventoryOrdersEvent {
  final String runDate; // yyyy-mm-dd
  const SetRunDate(this.runDate);
}

class LoadHeaders extends InventoryOrdersEvent {
  final int pageIndex;
  const LoadHeaders({required this.pageIndex});
}

class GenerateAll extends InventoryOrdersEvent {
  const GenerateAll();
}
