import '../../domain/entities/max_adj.dart';

class MaxAdjModel extends MaxAdj {
  const MaxAdjModel({
    required super.branchName,
    required super.itemCode,
    required super.currentDemand30d,
    required super.maxAdjustment30d,
    required super.adjustmentType,
    required super.updateDate,
  });

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return int.tryParse(s);
  }

  static DateTime? _parseAnyDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;

    final parts = s.split('/');
    if (parts.length == 3) {
      final dd = int.tryParse(parts[0]);
      final mm = int.tryParse(parts[1]);
      final yy = int.tryParse(parts[2]);
      if (dd != null && mm != null && yy != null) {
        return DateTime(yy, mm, dd);
      }
    }
    return null;
  }

  factory MaxAdjModel.fromMap(Map<String, dynamic> map) {
    return MaxAdjModel(
      branchName: (map['branch_name'] ?? '').toString(),
      itemCode: (map['item_code'] ?? '').toString(),
      currentDemand30d: _toInt(map['current_demand_30d']),
      maxAdjustment30d: _toInt(map['max_adjustment_30d']),
      adjustmentType: (map['adjustment_type'] ?? '').toString(),
      updateDate: _parseAnyDate(map['update_date']),
    );
  }
}
