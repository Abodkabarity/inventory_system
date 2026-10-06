class ItemsTrackerActionImport {
  final int excelRow;
  final String itemId;
  final String itemCode;
  final String itemName;
  final String body;
  final DateTime? actionDate;
  final int expectedVersion;
  final String importToken;

  const ItemsTrackerActionImport({
    required this.excelRow,
    required this.itemId,
    required this.itemCode,
    required this.itemName,
    required this.body,
    required this.actionDate,
    required this.expectedVersion,
    required this.importToken,
  });

  Map<String, dynamic> toJson() => {
    'excel_row': excelRow,
    'item_id': itemId,
    'item_code': itemCode,
    'body': body,
    'action_date': actionDate?.toIso8601String().split('T').first,
    'expected_version': expectedVersion,
    'import_token': importToken,
  };
}

class ItemsTrackerActionImportResult {
  final int excelRow;
  final String status;
  final String message;
  const ItemsTrackerActionImportResult({
    required this.excelRow,
    required this.status,
    required this.message,
  });

  factory ItemsTrackerActionImportResult.fromMap(Map<String, dynamic> map) =>
      ItemsTrackerActionImportResult(
        excelRow: (map['excel_row'] as num).toInt(),
        status: map['status'] as String,
        message: map['message'] as String,
      );

  bool get ready => status == 'ready';
  bool get imported => status == 'imported';
}
