class ItemsTrackerRoles {
  static const inventory = 'inventory';
  static const purchase = 'purchase';
  static const category = 'category';

  static const allowed = <String>{inventory, purchase, category};

  static String normalize(String value) => value.trim().toLowerCase();

  static bool isAllowed(String value) => allowed.contains(normalize(value));

  static bool canEditInventoryFields(String value) =>
      normalize(value) == inventory;

  static bool canComment(String value) => isAllowed(value);

  static String defaultFollowUpForCategory(String value) =>
      value.trim().toUpperCase() == 'MEDICINE' ? purchase : category;

  static String label(String value) {
    return switch (normalize(value)) {
      inventory => 'Inventory',
      purchase => 'Purchase',
      category => 'Category',
      _ => value.trim().isEmpty ? 'Unknown' : value.trim(),
    };
  }
}

class ItemsTrackerCaseStatuses {
  static const pending = 'pending';
  static const done = 'done';

  static const values = <String>[pending, done];

  static String label(String value) {
    return switch (value.trim().toLowerCase()) {
      pending => 'Pending',
      done => 'Done',
      _ => value,
    };
  }
}

double? calculateItemsTrackerValue(num? unitCost, num? requiredQty) {
  if (unitCost == null || requiredQty == null) return null;
  if (unitCost < 0 || requiredQty <= 0) return null;
  return (unitCost * requiredQty * 100).round() / 100;
}

class ItemsTrackerProduct {
  final String itemCode;
  final String itemName;
  final String category;
  final String supplier;
  final String company;
  final String itemStatus;
  final double? retailPrice;

  const ItemsTrackerProduct({
    required this.itemCode,
    required this.itemName,
    required this.category,
    required this.supplier,
    required this.company,
    required this.itemStatus,
    required this.retailPrice,
  });

  factory ItemsTrackerProduct.fromMap(Map<String, dynamic> map) {
    return ItemsTrackerProduct(
      itemCode: (map['item_code'] ?? '').toString(),
      itemName: (map['item_name'] ?? '').toString(),
      category: (map['category'] ?? '').toString(),
      supplier: (map['supplier'] ?? '').toString(),
      company: (map['company'] ?? '').toString(),
      itemStatus: (map['item_status'] ?? map['source_item_status'] ?? '')
          .toString(),
      retailPrice: _asDouble(map['retail'] ?? map['retail_snapshot']),
    );
  }

  String get searchLabel => '$itemCode — $itemName';
}

class ItemsTrackerRecord {
  final String id;
  final DateTime escalatedDate;
  final String itemCode;
  final String itemName;
  final String category;
  final String supplier;
  final String company;
  final String sourceItemStatus;
  final double? retailSnapshot;
  final double? unitCost;
  final String inventoryNote;
  final double requiredQty;
  final double? requiredValue;
  final String statusUpdatedTo;
  final String followUpRole;
  final String caseStatus;
  final String latestActivityType;
  final String latestActivityBody;
  final DateTime? latestActivityDate;
  final DateTime? latestActivityCreatedAt;
  final String latestActivityByRole;
  final String latestActivityAttachmentId;
  final String latestActivityAttachmentPath;
  final String latestActivityAttachmentName;
  final String latestActivityAttachmentMimeType;
  final int? latestActivityAttachmentSize;
  final String lastActionBody;
  final DateTime? lastActionDate;
  final String lastActionByRole;
  final String lastFollowUpBody;
  final DateTime? lastFollowUpDate;
  final String lastFollowUpToRole;
  final String latestComment;
  final String commentByRole;
  final DateTime? latestCommentAt;
  final int commentCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int rowVersion;

  const ItemsTrackerRecord({
    required this.id,
    required this.escalatedDate,
    required this.itemCode,
    required this.itemName,
    required this.category,
    required this.supplier,
    required this.company,
    required this.sourceItemStatus,
    required this.retailSnapshot,
    required this.unitCost,
    required this.inventoryNote,
    required this.requiredQty,
    required this.requiredValue,
    required this.statusUpdatedTo,
    required this.followUpRole,
    required this.caseStatus,
    required this.latestActivityType,
    required this.latestActivityBody,
    required this.latestActivityDate,
    required this.latestActivityCreatedAt,
    required this.latestActivityByRole,
    required this.latestActivityAttachmentId,
    required this.latestActivityAttachmentPath,
    required this.latestActivityAttachmentName,
    required this.latestActivityAttachmentMimeType,
    required this.latestActivityAttachmentSize,
    required this.lastActionBody,
    required this.lastActionDate,
    required this.lastActionByRole,
    required this.lastFollowUpBody,
    required this.lastFollowUpDate,
    required this.lastFollowUpToRole,
    required this.latestComment,
    required this.commentByRole,
    required this.latestCommentAt,
    required this.commentCount,
    required this.createdAt,
    required this.updatedAt,
    required this.rowVersion,
  });

  bool canAct(String role) =>
      ItemsTrackerRoles.normalize(role) ==
      ItemsTrackerRoles.normalize(followUpRole);

  bool canEditInventoryFields(String role) =>
      ItemsTrackerRoles.canEditInventoryFields(role);

  // The grid shows whichever operational event was added most recently:
  // Action or Follow-up. Creation and file-upload events are excluded by the
  // database view, while the complete timeline still keeps them permanently.
  String get displayedLastActivity => latestActivityBody.trim();

  DateTime? get displayedLastActivityDate => latestActivityDate;

  String get displayedLastActivityRole => latestActivityByRole.trim();

  String get displayedLastActivityType =>
      latestActivityType.trim().toLowerCase();

  bool get displayedLastActivityHasAttachment =>
      latestActivityAttachmentId.trim().isNotEmpty &&
      latestActivityAttachmentPath.trim().isNotEmpty;

  // Backward-compatible aliases for older grid code.
  String get displayedLastAction => displayedLastActivity;

  DateTime? get displayedLastActionDate => displayedLastActivityDate;

  String get displayedLastActionRole => displayedLastActivityRole;

  factory ItemsTrackerRecord.fromMap(Map<String, dynamic> map) {
    final createdAt = _asDateTime(map['created_at']) ?? DateTime(1970);
    return ItemsTrackerRecord(
      id: (map['id'] ?? '').toString(),
      escalatedDate:
          _asDateTime(map['escalated_date']) ??
          DateTime(createdAt.year, createdAt.month, createdAt.day),
      itemCode: (map['item_code'] ?? '').toString(),
      itemName: (map['item_name'] ?? '').toString(),
      category: (map['category'] ?? '').toString(),
      supplier: (map['supplier'] ?? '').toString(),
      company: (map['company'] ?? '').toString(),
      sourceItemStatus: (map['source_item_status'] ?? '').toString(),
      retailSnapshot: _asDouble(map['retail_snapshot']),
      unitCost: _asDouble(map['unit_cost_snapshot'] ?? map['unit_cost']),
      inventoryNote: (map['inventory_note'] ?? '').toString(),
      requiredQty: _asDouble(map['required_qty']) ?? 0,
      requiredValue:
          _asDouble(map['required_value']) ??
          calculateItemsTrackerValue(
            _asDouble(map['unit_cost_snapshot'] ?? map['unit_cost']),
            _asDouble(map['required_qty']),
          ),
      statusUpdatedTo: (map['status_updated_to'] ?? '').toString(),
      followUpRole: (map['follow_up_role'] ?? '').toString().toLowerCase(),
      caseStatus: (map['case_status'] ?? ItemsTrackerCaseStatuses.pending)
          .toString()
          .toLowerCase(),
      latestActivityType: (map['latest_activity_type'] ?? '').toString(),
      latestActivityBody:
          (map['latest_activity_body'] ?? map['latest_activity'] ?? '')
              .toString(),
      latestActivityDate: _asDateTime(map['latest_activity_date']),
      latestActivityCreatedAt: _asDateTime(
        map['latest_activity_created_at'] ?? map['latest_activity_added_at'],
      ),
      latestActivityByRole: (map['latest_activity_by_role'] ?? '').toString(),
      latestActivityAttachmentId: (map['latest_activity_attachment_id'] ?? '')
          .toString(),
      latestActivityAttachmentPath:
          (map['latest_activity_attachment_path'] ?? '').toString(),
      latestActivityAttachmentName:
          (map['latest_activity_attachment_name'] ?? '').toString(),
      latestActivityAttachmentMimeType:
          (map['latest_activity_attachment_mime_type'] ?? '').toString(),
      latestActivityAttachmentSize: _asInt(
        map['latest_activity_attachment_size'],
      ),
      lastActionBody: (map['last_action_body'] ?? map['last_action'] ?? '')
          .toString(),
      lastActionDate: _asDateTime(map['last_action_date']),
      lastActionByRole: (map['last_action_by_role'] ?? '').toString(),
      lastFollowUpBody:
          (map['last_follow_up_body'] ?? map['last_follow_up_note'] ?? '')
              .toString(),
      lastFollowUpDate: _asDateTime(map['last_follow_up_date']),
      lastFollowUpToRole:
          (map['last_follow_up_to_role'] ?? map['last_follow_up_role'] ?? '')
              .toString(),
      latestComment: (map['latest_comment'] ?? map['last_comment'] ?? '')
          .toString(),
      commentByRole: (map['comment_by_role'] ?? '').toString(),
      latestCommentAt: _asDateTime(
        map['latest_comment_at'] ?? map['last_comment_at'],
      ),
      commentCount: _asInt(map['comment_count']) ?? 0,
      createdAt: createdAt,
      updatedAt: _asDateTime(map['updated_at']) ?? createdAt,
      rowVersion: _asInt(map['row_version']) ?? 1,
    );
  }
}

class ItemsTrackerTimelineEntry {
  final String id;
  final String entryType;
  final String eventType;
  final String body;
  final DateTime? actionDate;
  final DateTime createdAt;
  final String actorRole;
  final String fromRole;
  final String toRole;
  final String fromStatus;
  final String toStatus;
  final String attachmentId;
  final String storagePath;
  final String fileName;
  final String mimeType;
  final int? fileSize;

  const ItemsTrackerTimelineEntry({
    required this.id,
    required this.entryType,
    required this.eventType,
    required this.body,
    required this.actionDate,
    required this.createdAt,
    required this.actorRole,
    required this.fromRole,
    required this.toRole,
    required this.fromStatus,
    required this.toStatus,
    required this.attachmentId,
    required this.storagePath,
    required this.fileName,
    required this.mimeType,
    required this.fileSize,
  });

  bool get isComment => entryType == 'comment';

  bool get hasAttachment =>
      attachmentId.trim().isNotEmpty && storagePath.trim().isNotEmpty;

  bool get isImageAttachment => mimeType.toLowerCase().startsWith('image/');

  factory ItemsTrackerTimelineEntry.fromMap(Map<String, dynamic> map) {
    return ItemsTrackerTimelineEntry(
      id: (map['id'] ?? '').toString(),
      entryType: (map['entry_type'] ?? 'event').toString().toLowerCase(),
      eventType: (map['event_type'] ?? '').toString().toLowerCase(),
      body: (map['body'] ?? '').toString(),
      actionDate: _asDateTime(map['action_date']),
      createdAt: _asDateTime(map['created_at']) ?? DateTime(1970),
      actorRole: (map['actor_role'] ?? map['created_by_role'] ?? '').toString(),
      fromRole: (map['from_follow_up_role'] ?? '').toString(),
      toRole: (map['to_follow_up_role'] ?? '').toString(),
      fromStatus: (map['from_case_status'] ?? '').toString(),
      toStatus: (map['to_case_status'] ?? '').toString(),
      attachmentId: (map['attachment_id'] ?? '').toString(),
      storagePath: (map['storage_path'] ?? '').toString(),
      fileName: (map['file_name'] ?? '').toString(),
      mimeType: (map['mime_type'] ?? '').toString(),
      fileSize: _asInt(map['file_size']),
    );
  }
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

DateTime? _asDateTime(Object? value) {
  if (value is DateTime) return value;
  final text = value?.toString() ?? '';
  if (text.trim().isEmpty) return null;
  return DateTime.tryParse(text);
}
