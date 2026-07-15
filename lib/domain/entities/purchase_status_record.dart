class PurchaseStatusOption {
  final int id;
  final String name;

  const PurchaseStatusOption({required this.id, required this.name});

  factory PurchaseStatusOption.fromMap(Map<String, dynamic> map) {
    return PurchaseStatusOption(
      id: (map['id'] as num).toInt(),
      name: (map['name'] ?? '').toString(),
    );
  }
}

class PurchaseProductSuggestion {
  final String itemCode;
  final String itemName;
  final String purchaseStatus;
  final String category;
  final String supplier;

  const PurchaseProductSuggestion({
    required this.itemCode,
    required this.itemName,
    required this.purchaseStatus,
    required this.category,
    required this.supplier,
  });

  factory PurchaseProductSuggestion.fromMap(Map<String, dynamic> map) {
    return PurchaseProductSuggestion(
      itemCode: (map['item_code'] ?? '').toString(),
      itemName: (map['item_name'] ?? '').toString(),
      purchaseStatus: (map['item_status'] ?? '').toString(),
      category: (map['category'] ?? '').toString(),
      supplier: (map['supplier'] ?? '').toString(),
    );
  }
}

class PurchaseStatusRecord {
  final int id;
  final String itemCode;
  final String itemName;
  final int? statusId;
  final String statusName;
  final DateTime? statusDate;
  final String alternativeItemCode;
  final String alternativeItemName;
  final String note;
  final String purchaseStatus;
  final String category;
  final String supplier;
  final String workflowStatus;
  final String reviewOrigin;
  final double requiredQuantity;
  final int missingRequestCount;
  final DateTime? missingLastReportDate;
  final String source;
  final DateTime? updatedAt;

  bool get isPending => workflowStatus == 'pending';
  bool get wasAlreadyExisting => reviewOrigin == 'repeated';

  const PurchaseStatusRecord({
    required this.id,
    required this.itemCode,
    required this.itemName,
    required this.statusId,
    required this.statusName,
    required this.statusDate,
    required this.alternativeItemCode,
    required this.alternativeItemName,
    required this.note,
    required this.purchaseStatus,
    required this.category,
    required this.supplier,
    this.workflowStatus = 'complete',
    this.reviewOrigin = 'manual',
    this.requiredQuantity = 0,
    this.missingRequestCount = 0,
    this.missingLastReportDate,
    this.source = 'manual',
    this.updatedAt,
  });

  factory PurchaseStatusRecord.fromMap(Map<String, dynamic> map) {
    final status = map['purchase_status_options'];
    final statusMap = status is Map<String, dynamic>
        ? status
        : const <String, dynamic>{};
    return PurchaseStatusRecord(
      id: (map['id'] as num).toInt(),
      itemCode: (map['item_code'] ?? '').toString(),
      itemName: (map['item_name'] ?? '').toString(),
      statusId: (map['status_id'] as num?)?.toInt(),
      statusName: (statusMap['name'] ?? map['status_name'] ?? '').toString(),
      statusDate: DateTime.tryParse((map['status_date'] ?? '').toString()),
      alternativeItemCode: (map['alternative_item_code'] ?? '').toString(),
      alternativeItemName: (map['alternative_item_name'] ?? '').toString(),
      note: (map['note'] ?? '').toString(),
      purchaseStatus: (map['purchase_status'] ?? '').toString(),
      category: (map['category'] ?? '').toString(),
      supplier: (map['supplier'] ?? '').toString(),
      workflowStatus: (map['workflow_status'] ?? 'complete')
          .toString()
          .toLowerCase(),
      reviewOrigin: (map['review_origin'] ?? 'manual').toString().toLowerCase(),
      requiredQuantity:
          double.tryParse((map['required_quantity'] ?? 0).toString()) ?? 0,
      missingRequestCount:
          int.tryParse((map['missing_request_count'] ?? 0).toString()) ?? 0,
      missingLastReportDate: DateTime.tryParse(
        (map['missing_last_report_date'] ?? '').toString(),
      ),
      source: (map['source'] ?? 'manual').toString(),
      updatedAt: DateTime.tryParse((map['updated_at'] ?? '').toString()),
    );
  }
}
