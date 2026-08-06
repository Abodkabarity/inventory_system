import '../entities/items_tracker_record.dart';

abstract class ItemsTrackerRepository {
  Future<List<ItemsTrackerRecord>> fetchRecords();

  Future<List<ItemsTrackerProduct>> searchProducts(String query);

  /// Returns the distinct canonical values of item_report.item_status.
  Future<List<String>> fetchItemStatuses();

  Future<void> createRecord(CreateItemsTrackerRecord input);

  Future<void> updateInventoryFields(UpdateItemsTrackerRecord input);

  /// Updates only status_updated_to. The database RPC enforces Inventory-only
  /// access and validates the selected value against item_report.item_status.
  Future<void> updateStatusUpdatedTo(UpdateItemsTrackerStatus input);

  Future<void> addAction(AddItemsTrackerAction input);

  Future<void> changeFollowUp(ChangeItemsTrackerFollowUp input);

  Future<void> addComment({required String itemId, required String body});

  Future<List<ItemsTrackerTimelineEntry>> fetchTimeline(String itemId);
}

class CreateItemsTrackerRecord {
  final DateTime escalatedDate;
  final String itemCode;
  final double? unitCost;
  final String inventoryNote;
  final double requiredQty;
  final String statusUpdatedTo;
  final String followUpRole;

  const CreateItemsTrackerRecord({
    required this.escalatedDate,
    required this.itemCode,
    required this.unitCost,
    required this.inventoryNote,
    required this.requiredQty,
    required this.statusUpdatedTo,
    required this.followUpRole,
  });
}

class UpdateItemsTrackerRecord {
  final String itemId;
  final DateTime escalatedDate;
  final double? unitCost;
  final String inventoryNote;
  final double requiredQty;
  final String statusUpdatedTo;
  final String followUpRole;
  final int expectedVersion;

  const UpdateItemsTrackerRecord({
    required this.itemId,
    required this.escalatedDate,
    required this.unitCost,
    required this.inventoryNote,
    required this.requiredQty,
    required this.statusUpdatedTo,
    required this.followUpRole,
    required this.expectedVersion,
  });
}

class UpdateItemsTrackerStatus {
  final String itemId;
  final String statusUpdatedTo;
  final int expectedVersion;

  const UpdateItemsTrackerStatus({
    required this.itemId,
    required this.statusUpdatedTo,
    required this.expectedVersion,
  });
}

class AddItemsTrackerAction {
  final String itemId;
  final DateTime actionDate;
  final String body;
  final String caseStatus;
  final int expectedVersion;

  const AddItemsTrackerAction({
    required this.itemId,
    required this.actionDate,
    required this.body,
    required this.caseStatus,
    required this.expectedVersion,
  });
}

class ChangeItemsTrackerFollowUp {
  final String itemId;
  final String targetRole;
  final String note;
  final DateTime actionDate;
  final int expectedVersion;

  const ChangeItemsTrackerFollowUp({
    required this.itemId,
    required this.targetRole,
    required this.note,
    required this.actionDate,
    required this.expectedVersion,
  });
}
