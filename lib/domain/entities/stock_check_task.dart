class StockCheckTask {
  final String id;
  final String batchId;
  final String title;
  final String source;
  final String branchName;
  final String itemCode;
  final String itemName;
  final num? systemQty;
  final num? actualQty;
  final bool includeBarcodeStickerCheck;
  final bool? barcodeStickerIsCorrect;
  final String status;
  final String note;
  final DateTime? sentAt;
  final DateTime? expiresAt;
  final DateTime? submittedAt;
  final String submittedByName;
  final String submittedByEmployeeId;

  const StockCheckTask({
    required this.id,
    required this.batchId,
    required this.title,
    required this.source,
    required this.branchName,
    required this.itemCode,
    required this.itemName,
    required this.systemQty,
    required this.actualQty,
    required this.includeBarcodeStickerCheck,
    required this.barcodeStickerIsCorrect,
    required this.status,
    required this.note,
    required this.sentAt,
    required this.expiresAt,
    required this.submittedAt,
    required this.submittedByName,
    required this.submittedByEmployeeId,
  });

  bool get isSubmitted => status.trim().toLowerCase() == 'submitted';
  bool get isPending => !isSubmitted;
  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!.toLocal());
  num? get variance {
    if (systemQty == null || actualQty == null) return null;
    return actualQty! - systemQty!;
  }

  StockCheckTask copyWith({
    Object? systemQty = _sentinel,
    num? actualQty,
    bool? includeBarcodeStickerCheck,
    Object? barcodeStickerIsCorrect = _sentinel,
    String? status,
    String? note,
    DateTime? expiresAt,
    DateTime? submittedAt,
    String? submittedByName,
    String? submittedByEmployeeId,
  }) {
    return StockCheckTask(
      id: id,
      batchId: batchId,
      title: title,
      source: source,
      branchName: branchName,
      itemCode: itemCode,
      itemName: itemName,
      systemQty: identical(systemQty, _sentinel)
          ? this.systemQty
          : systemQty as num?,
      actualQty: actualQty ?? this.actualQty,
      includeBarcodeStickerCheck:
          includeBarcodeStickerCheck ?? this.includeBarcodeStickerCheck,
      barcodeStickerIsCorrect: identical(barcodeStickerIsCorrect, _sentinel)
          ? this.barcodeStickerIsCorrect
          : barcodeStickerIsCorrect as bool?,
      status: status ?? this.status,
      note: note ?? this.note,
      sentAt: sentAt,
      expiresAt: expiresAt ?? this.expiresAt,
      submittedAt: submittedAt ?? this.submittedAt,
      submittedByName: submittedByName ?? this.submittedByName,
      submittedByEmployeeId:
          submittedByEmployeeId ?? this.submittedByEmployeeId,
    );
  }

  static const Object _sentinel = Object();

  static num? _nullableNum(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return num.tryParse(text.replaceAll(',', ''));
  }

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  static bool _bool(dynamic value) {
    if (value is bool) return value;
    final text = (value ?? '').toString().trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  static bool? _nullableBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty) return null;
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no') return false;
    return null;
  }

  factory StockCheckTask.fromMap(Map<String, dynamic> map) {
    return StockCheckTask(
      id: (map['id'] ?? '').toString(),
      batchId: (map['batch_id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      source: (map['source'] ?? 'inventory').toString(),
      branchName: (map['branch_name'] ?? '').toString(),
      itemCode: (map['item_code'] ?? '').toString(),
      itemName: (map['item_name'] ?? '').toString(),
      systemQty: _nullableNum(map['system_qty']),
      actualQty: _nullableNum(map['actual_qty']),
      includeBarcodeStickerCheck: _bool(map['include_barcode_sticker_check']),
      barcodeStickerIsCorrect: _nullableBool(map['barcode_sticker_is_correct']),
      status: (map['status'] ?? 'pending').toString(),
      note: (map['note'] ?? '').toString(),
      sentAt: _date(map['sent_at']),
      expiresAt: _date(map['expires_at']),
      submittedAt: _date(map['submitted_at']),
      submittedByName: (map['submitted_by_name'] ?? '').toString(),
      submittedByEmployeeId: (map['submitted_by_employee_id'] ?? '').toString(),
    );
  }
}
