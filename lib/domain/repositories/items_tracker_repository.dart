import 'dart:typed_data';

import '../entities/items_tracker_record.dart';
import '../entities/items_tracker_action_import.dart';
import '../entities/items_tracker_email.dart';

abstract class ItemsTrackerRepository {
  Future<List<ItemsTrackerRecord>> fetchRecords();

  Future<List<ItemsTrackerProduct>> searchProducts(String query);

  Future<List<ItemsTrackerCompany>> searchCompanies(String query);

  Future<List<ItemsTrackerProduct>> fetchCompanyProducts(String company);

  /// Returns the distinct canonical values of item_report.item_status.
  Future<List<String>> fetchItemStatuses();

  Future<List<ItemsTrackerNotification>> fetchNotifications();

  Future<void> markNotificationRead(int notificationId);

  Future<void> markAllNotificationsRead();

  Future<String> createRecord(CreateItemsTrackerRecord input);

  /// Creates the selected products together in one database transaction.
  Future<List<String>> createRecords(List<CreateItemsTrackerRecord> inputs);

  /// Inventory only. Reserves one persistent Outlook draft per item/team.
  Future<List<ItemsTrackerEmailDraft>> prepareEmails(
    List<String> itemIds, {
    String? company,
  });

  Future<bool> openEmailDraft(String emailId, {bool reopen = false});
  Future<void> releaseEmailDraft(String emailId);
  Future<void> confirmEmailSent(String emailId);
  Future<void> cancelEmailDraft(String emailId);

  Future<List<ItemsTrackerActionImportResult>> importActions(
    List<ItemsTrackerActionImport> rows, {
    required String fileName,
    bool apply = false,
  });

  Future<void> updateInventoryFields(UpdateItemsTrackerRecord input);

  /// Updates only status_updated_to. The database RPC enforces Inventory-only
  /// access and validates the selected value against item_report.item_status.
  Future<void> updateStatusUpdatedTo(UpdateItemsTrackerStatus input);

  Future<void> updateTrackerStatus(UpdateItemsTrackerCaseStatus input);

  Future<void> addAction(AddItemsTrackerAction input);

  Future<void> changeFollowUp(ChangeItemsTrackerFollowUp input);

  Future<void> addComment({required String itemId, required String body});

  Future<List<ItemsTrackerTimelineEntry>> fetchTimeline(String itemId);

  Future<void> uploadAttachment({
    required String itemId,
    required ItemsTrackerUploadFile file,
  });

  Future<String> createAttachmentDownloadUrl(String storagePath);
}

class ItemsTrackerUploadFile {
  final String name;
  final String mimeType;
  final Uint8List bytes;

  const ItemsTrackerUploadFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  int get size => bytes.length;
}

class CreateItemsTrackerRecord {
  final DateTime escalatedDate;
  final String itemCode;
  final double? unitCost;
  final String inventoryNote;
  final double requiredQty;
  final String statusUpdatedTo;
  final String followUpRole;

  /// A tracker-only product that is absent from Item Report.
  final ItemsTrackerProduct? manualProduct;

  const CreateItemsTrackerRecord({
    required this.escalatedDate,
    required this.itemCode,
    required this.unitCost,
    required this.inventoryNote,
    required this.requiredQty,
    required this.statusUpdatedTo,
    required this.followUpRole,
    this.manualProduct,
  });
}

class ItemsTrackerCompany {
  final String name;
  final int productCount;

  const ItemsTrackerCompany({required this.name, required this.productCount});
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

class UpdateItemsTrackerCaseStatus {
  final String itemId;
  final String trackerStatus;
  final int expectedVersion;

  const UpdateItemsTrackerCaseStatus({
    required this.itemId,
    required this.trackerStatus,
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
