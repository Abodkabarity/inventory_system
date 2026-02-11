import '../../domain/entities/assortment_entry.dart';

class AssortmentEntryModel extends AssortmentEntry {
  const AssortmentEntryModel({
    required super.branchName,
    required super.itemCode,
    super.itemName,
    super.assortmentQty,
    super.assortmentBy,
    super.start,
    super.end,
    super.reason,
  });

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  factory AssortmentEntryModel.fromMap(Map<String, dynamic> map) {
    return AssortmentEntryModel(
      branchName: (map['branch_name'] as String?) ?? '',
      itemCode: (map['item_code'] as String?) ?? '',
      itemName: map['item_name'] as String?,
      reason: map['reason'] as String?,
      assortmentQty: map['assortment_qty'] as num?,
      assortmentBy: map['assortment_by'] as String?,
      start: _parseDate(map['assortment_start']),
      end: _parseDate(map['assortment_end']),
    );
  }
}
