// lib/domain/entities/request_effectiveness_row.dart

class RequestEffectivenessRow {
  final String id;
  final String branchName;
  final String itemCode;
  final String itemName;
  final num requestQty;
  final num totalSoldQty;
  final String status;
  final String requestDate;
  final int daysElapsed;
  final int? daysToFirstSale;
  final int daysWithoutSale;
  final int sellingDays;
  final String effectivenessStatus; // sold_within_3d | sold_after_3d | not_sold
  final String effectivenessLabel;
  final num soldPct;

  const RequestEffectivenessRow({
    required this.id,
    required this.branchName,
    required this.itemCode,
    required this.itemName,
    required this.requestQty,
    required this.totalSoldQty,
    required this.status,
    required this.requestDate,
    required this.daysElapsed,
    required this.daysToFirstSale,
    required this.daysWithoutSale,
    required this.sellingDays,
    required this.effectivenessStatus,
    required this.effectivenessLabel,
    required this.soldPct,
  });

  factory RequestEffectivenessRow.fromMap(Map<String, dynamic> m) {
    return RequestEffectivenessRow(
      id: m['id']?.toString() ?? '',
      branchName: m['branch_name']?.toString() ?? '',
      itemCode: m['item_code']?.toString() ?? '',
      itemName: m['item_name']?.toString() ?? '',
      requestQty: (m['request_qty'] as num?) ?? 0,
      totalSoldQty: (m['total_sold_qty'] as num?) ?? 0,
      status: m['status']?.toString() ?? '',
      requestDate: m['request_date']?.toString() ?? '',
      daysElapsed: (m['days_elapsed'] as num?)?.toInt() ?? 0,
      daysToFirstSale: (m['days_to_first_sale'] as num?)?.toInt(),
      daysWithoutSale: (m['days_without_sale'] as num?)?.toInt() ?? 0,
      sellingDays: (m['selling_days'] as num?)?.toInt() ?? 0,
      effectivenessStatus: m['effectiveness_status']?.toString() ?? 'not_sold',
      effectivenessLabel: m['effectiveness_label']?.toString() ?? '—',
      soldPct: (m['sold_pct'] as num?) ?? 0,
    );
  }
}
