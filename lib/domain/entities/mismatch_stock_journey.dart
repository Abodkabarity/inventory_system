/// Date-only evidence never establishes ordering within a transaction day.
class MismatchStockJourney {
  MismatchStockJourney(this.analysis, Map<String, dynamic> evidence) {
    movements =
        (evidence['movements'] as List? ?? [])
            .map((v) => Map<String, dynamic>.from(v as Map))
            .where(
              (r) =>
                  day(r['trans_date']) != null &&
                  countDay != null &&
                  !day(r['trans_date'])!.isAfter(countDay!),
            )
            .toList()
          ..sort(
            (a, b) => '${a['trans_date']}'.compareTo('${b['trans_date']}'),
          );
  }
  final Map<String, dynamic> analysis;
  late final List<Map<String, dynamic>> movements;
  static DateTime? day(dynamic v) {
    final d = DateTime.tryParse('$v');
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  static num quantity(Map r) => num.tryParse('${r['qty']}') ?? 0;
  static bool isAdjustment(Map r) =>
      '${r['trans_type']}'.trim().toLowerCase() == 'invadjustment';
  late final DateTime? countDay = day(analysis['event_at']);
  late final DateTime? receiptDay = day(analysis['last_receipt']);
  late final List<Map<String, dynamic>> adjustments = movements
      .where(isAdjustment)
      .toList();
  late final List<Map<String, dynamic>> laterMovements = receiptDay == null
      ? []
      : movements
            .where((r) => day(r['trans_date'])!.isAfter(receiptDay!))
            .toList();
  late final List<Map<String, dynamic>> receiptDayOtherMovements =
      receiptDay == null
      ? []
      : movements
            .where(
              (r) =>
                  day(r['trans_date']) == receiptDay &&
                  (isAdjustment(r) || quantity(r) <= 0),
            )
            .toList();
  late final num laterIn = laterMovements
      .where((r) => !isAdjustment(r) && quantity(r) > 0)
      .fold<num>(0, (sum, r) => sum + quantity(r));
  late final num laterOut = laterMovements
      .where((r) => !isAdjustment(r) && quantity(r) < 0)
      .fold<num>(0, (sum, r) => sum - quantity(r));
  late final int laterAdjustments = laterMovements.where(isAdjustment).length;
  late final List<Map<String, dynamic>> beforeCountMovements = laterMovements
      .where((r) => day(r['trans_date'])!.isBefore(countDay!))
      .toList();
  late final List<Map<String, dynamic>> countDayMovements = movements
      .where((r) => day(r['trans_date']) == countDay && quantity(r) != 0)
      .toList();
  static String type(Map r) => '${r['trans_type']}'.trim().toLowerCase();
  static bool isSale(Map r) => const ['pos', 'posdvn'].contains(type(r));
  static bool isTransferOut(Map r) => type(r) == 'stocktransferfrom';
  num _outWhere(bool Function(Map) test) => beforeCountMovements
      .where((r) => quantity(r) < 0 && test(r))
      .fold<num>(0, (sum, r) => sum - quantity(r));
  late final num sold = _outWhere(isSale);
  late final num transferredOut = _outWhere(isTransferOut);
  late final num otherOut = _outWhere(
    (r) => !isSale(r) && !isTransferOut(r) && !isAdjustment(r),
  );
  late final num adjustmentNet = beforeCountMovements
      .where(isAdjustment)
      .fold<num>(0, (sum, r) => sum + quantity(r));
  late final num otherIn = beforeCountMovements
      .where((r) => quantity(r) > 0 && !isAdjustment(r))
      .fold<num>(0, (sum, r) => sum + quantity(r));
  num? get expectedBeforeCount =>
      num.tryParse('${analysis['reconstructed_before']}');
  late final num? stockBeforeReceipt = _stockBeforeReceipt();
  num? _stockBeforeReceipt() {
    final baseline = num.tryParse('${analysis['baseline_qty']}');
    if (baseline == null || receiptDay == null) return null;
    final start = DateTime(receiptDay!.year, 1, 1);
    return baseline +
        movements
            .where((r) {
              final d = day(r['trans_date'])!;
              return d.isAfter(start) && d.isBefore(receiptDay!);
            })
            .fold<num>(0, (sum, r) => sum + quantity(r));
  }

  late final num receiptDayOtherNet = receiptDayOtherMovements.fold<num>(
    0,
    (sum, r) => sum + quantity(r),
  );
  late final int? daysToCount = receiptDay == null || countDay == null
      ? null
      : countDay!.difference(receiptDay!).inDays;
  String get elapsedEnglish {
    if (daysToCount == null || daysToCount! < 0) return 'Unknown time';
    String days(int value) => '$value ${value == 1 ? 'day' : 'days'}';
    final from = receiptDay!, to = countDay!;
    var months = (to.year - from.year) * 12 + to.month - from.month;
    DateTime anniversary(int m) {
      final first = DateTime(from.year, from.month + m, 1);
      final lastDay = DateTime(first.year, first.month + 1, 0).day;
      return DateTime(
        first.year,
        first.month,
        from.day > lastDay ? lastDay : from.day,
      );
    }

    if (anniversary(months).isAfter(to)) months--;
    if (months < 1) return days(daysToCount!);
    final remaining = to.difference(anniversary(months)).inDays;
    final label = '$months ${months == 1 ? 'month' : 'months'}';
    return '$label${remaining == 0 ? '' : ' and ${days(remaining)}'} (${days(daysToCount!)})';
  }

  bool get canCompareCount =>
      coverageComplete &&
      (analysis['issues'] as List? ?? []).isEmpty &&
      expectedBeforeCount != null &&
      countDayMovements.isEmpty;
  bool get coverageComplete {
    final through = day(analysis['coverage_through']);
    return countDay != null &&
        through != null &&
        !through.isBefore(countDay!) &&
        !(analysis['issues'] as List? ?? []).contains('incomplete_coverage');
  }

  bool get noLaterMovementEstablished =>
      receiptDay != null &&
      coverageComplete &&
      laterMovements.isEmpty &&
      receiptDayOtherMovements.isEmpty;
  String adjustmentTiming(Map r) {
    if (receiptDay == null) return 'No incoming checkpoint';
    final d = day(r['trans_date'])!;
    return d.isBefore(receiptDay!)
        ? 'Before latest incoming'
        : d.isAfter(receiptDay!)
        ? 'After latest incoming'
        : 'Same day as incoming · order unknown';
  }
}
