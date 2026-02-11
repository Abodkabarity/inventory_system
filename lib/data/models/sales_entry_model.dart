import '../../domain/entities/sales_entry.dart';

class SalesRowModel extends SalesEntry {
  const SalesRowModel({
    required super.branchName,
    required super.itemCode,
    required super.qty,
  });

  static String normCode(dynamic v) {
    if (v == null) return '';
    var s = v.toString().trim().replaceAll(' ', '');
    if (s.endsWith('.0')) s = s.substring(0, s.length - 2);
    return s;
  }

  static num parseNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  factory SalesRowModel.fromMap(Map<String, dynamic> map) {
    return SalesRowModel(
      branchName: (map['branch_name'] ?? '').toString().trim(),
      itemCode: normCode(map['item_code']),
      qty: parseNum(map['qty']),
    );
  }
}
