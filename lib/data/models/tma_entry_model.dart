import '../../domain/entities/tma_entry.dart';

class TmaEntryModel extends TmaEntry {
  const TmaEntryModel({
    required super.branchName,
    required super.itemCode,
    super.itemName,
    super.start,
    super.end,
    super.finalQtyToKeep,
    super.qtyPerDuration,
  });

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  factory TmaEntryModel.fromMap(Map<String, dynamic> map) {
    return TmaEntryModel(
      branchName: (map['branch_name'] as String?) ?? '',
      itemCode: (map['item_code'] as String?) ?? '',
      itemName: map['item_name'] as String?,
      start: _parseDate(map['start_date']),
      end: _parseDate(map['end_date']),
      finalQtyToKeep: map['final_qty_to_keep'] as num?,
      qtyPerDuration: map['qty_per_duration'] as num?,
    );
  }
}
