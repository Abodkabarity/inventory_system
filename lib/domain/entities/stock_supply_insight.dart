import 'stock_management.dart';

/// STORE system-stock evidence; retail availability and demand are separate.
class StockSupplyInsight {
  final Map<String, dynamic> data;
  const StockSupplyInsight(this.data);
  factory StockSupplyInsight.of(StockManagementItem item) =>
      StockSupplyInsight(stockMap(item.data['supply_insight']));
  String get status => data['status']?.toString() ?? 'pending';
  bool get present => data.isNotEmpty;
  bool get verified => data['confidence'] == 'verified';
  bool get inferred => data['confidence'] == 'inferred';
  bool get usable =>
      (verified || inferred) &&
      const {'back_in_store', 'store_empty', 'in_store'}.contains(status);
  Map<String, dynamic> get effectiveSupply =>
      stockMap(data['effective_supply']);
  bool get hasSupplyAnalysis =>
      usable &&
      const {
        'limited_supply',
        'supply_restored',
        'adequate_supply',
      }.contains(effectiveSupply['status']);
  Map<String, dynamic> get demandModel => stockMap(effectiveSupply['model']);
  Map<String, dynamic> get latestSupplyPeriod =>
      hasSupplyAnalysis ? stockMap(effectiveSupply['latest_period']) : const {};
  List<Map<String, dynamic>> get supplyPeriods => !hasSupplyAnalysis
      ? const []
      : (effectiveSupply['periods'] as List? ?? [])
            .map(stockMap)
            .where((p) => stockNumber(p['days']) >= 30)
            .toList();
  String supplyDuration(Map<String, dynamic> period, {bool compact = false}) {
    if (period.isEmpty) return '';
    final months = stockNumber(period['months']).toInt();
    final days = stockNumber(
      period['remaining_days'] ?? period['days'],
    ).toInt();
    final text = months > 0
        ? '$months ${months == 1 ? 'month' : 'months'}${days > 0 && !compact ? ' $days days' : ''}'
        : '${stockNumber(period['days']).toInt()} days';
    return '${period['at_least'] == true ? 'At least ' : ''}$text';
  }

  String get displayGapLabel =>
      hasSupplyAnalysis ? supplyDuration(latestSupplyPeriod) : gapLabel;
  String get basis => !usable
      ? 'Needs checking'
      : inferred
      ? 'Estimated'
      : 'Verified';
  String get basisDescription => [
    if (data['opening_basis'] == 'assumed_zero')
      'Opening STORE stock is assumed zero because this item was omitted from the opening report.',
    if (data['provisional'] == true)
      'Recent movements or MRN receipts extend the archive provisionally and match the current STORE ledger.',
  ].join(' ');
  String get label => hasSupplyAnalysis
      ? switch (effectiveSupply['status']) {
          'limited_supply' => 'Limited supply',
          'supply_restored' => 'Supply restored',
          _ => 'Stock available',
        }
      : switch (status) {
          'back_in_store' => 'Back in STORE',
          'store_empty' => 'STORE empty',
          'in_store' => 'Stock available',
          'receipt_pending' => 'Receipt needs checking',
          'history_needed' => 'Review supply',
          _ => 'Awaiting analysis',
        };
  String get gapLabel => !usable || data['gap_days'] == null
      ? ''
      : '${data['at_least'] == true ? 'At least ' : ''}${stockNumber(data['gap_days']).toInt()} days';
  List<Map<String, dynamic>> get months => usable
      ? (data['monthly'] as List? ?? []).map(stockMap).toList()
      : const [];
  List<Map<String, dynamic>> get returns => usable
      ? (data['events'] as List? ?? [])
            .map(stockMap)
            .where((r) => r['established'] == true && r['mrn_linked'] == true)
            .toList()
      : const [];
  Map<String, dynamic> month(Object? key) =>
      months.firstWhere((row) => row['month'] == key, orElse: () => const {});

  /// Historical chart evidence is separate from the current verified status.
  /// The server permits an unreconciled timeline only for a missing current
  /// STORE row or an endpoint mismatch; other invalid history stays excluded.
  Map<String, dynamic> get chartTimeline => stockMap(data['chart_timeline']);
  bool get chartNeedsReview => chartTimeline['review_required'] == true;
  List<Map<String, dynamic>> get chartPeriods {
    if (chartTimeline.isNotEmpty) {
      return (chartTimeline['periods'] as List? ?? [])
          .map(stockMap)
          .where((p) => stockNumber(p['days']) >= 30)
          .toList();
    }
    if (hasSupplyAnalysis) return supplyPeriods;
    // A recorded continuous empty-STORE spell does not need enough sales to
    // fit a demand model. Keep its dates together instead of monthly OUT labels.
    final days = stockNumber(data['gap_days']).toInt();
    final through = DateTime.tryParse('${data['through']}');
    if (!usable ||
        status != 'store_empty' ||
        days < 30 ||
        through == null ||
        data['current_qty'] == null ||
        stockNumber(data['current_qty']) != 0 ||
        (data['events'] as List? ?? []).isNotEmpty ||
        (data['issues'] as List? ?? []).isNotEmpty) {
      return const [];
    }
    final from = through.subtract(Duration(days: days - 1));
    final until = through.add(const Duration(days: 1));
    var months = (until.year - from.year) * 12 + until.month - from.month;
    if (until.day < from.day) months--;
    final anniversary = DateTime(from.year, from.month + months, from.day);
    return [
      {
        'kind': 'store_empty',
        'from': from.toIso8601String().substring(0, 10),
        'through': through.toIso8601String().substring(0, 10),
        'days': days,
        'months': months,
        'remaining_days': until.difference(anniversary).inDays,
        'at_least': data['at_least'] == true,
      },
    ];
  }

  bool get chartIsContinuousStockout =>
      chartPeriods.isNotEmpty &&
      chartPeriods.every((p) => p['kind'] == 'store_empty');
  List<Map<String, dynamic>> get chartArrivals =>
      (chartTimeline['arrivals'] as List? ?? [])
          .map(stockMap)
          .where(
            (r) =>
                DateTime.tryParse('${r['date']}') != null &&
                stockNumber(r['qty']) > 0 &&
                const {'restored', 'limited'}.contains(r['kind']),
          )
          .toList();
  bool get hasChartPeriods => chartPeriods.isNotEmpty;
  bool chartMarksMonth(Object? key) {
    if (!hasChartPeriods) return marksMonth(key);
    final start = _monthStart(key);
    if (start == null) return false;
    final end = DateTime(start.year, start.month + 1);
    return chartPeriods.any((p) {
      final from = DateTime.tryParse('${p['from']}');
      final through = DateTime.tryParse('${p['through']}');
      return from != null &&
          through != null &&
          from.isBefore(end) &&
          !through.isBefore(start);
    });
  }

  List<Map<String, dynamic>> chartArrivalsInMonth(Object? key) {
    final start = _monthStart(key);
    if (start == null) return const [];
    return chartArrivals.where((r) {
      final date = DateTime.parse('${r['date']}');
      return date.year == start.year && date.month == start.month;
    }).toList();
  }

  static String arrivalLabel(Map<String, dynamic> arrival) =>
      arrival['kind'] == 'restored' ? 'Back in stock' : 'Back · Limited stock';

  String chartMonthDescription(Object? key) {
    if (!hasChartPeriods) return monthDescription(key);
    final start = _monthStart(key);
    if (start == null || !chartMarksMonth(key)) return '';
    final days = <DateTime>{};
    final end = DateTime(start.year, start.month + 1);
    for (final period in chartPeriods) {
      final from = DateTime.tryParse('${period['from']}');
      final through = DateTime.tryParse('${period['through']}');
      if (from == null || through == null) continue;
      for (
        var d = from.isBefore(start) ? start : from;
        d.isBefore(end) && !d.isAfter(through);
        d = DateTime(d.year, d.month, d.day + 1)
      ) {
        days.add(d);
      }
    }
    if (chartIsContinuousStockout) {
      final period = chartPeriods.single;
      return 'STORE out of stock from ${period['from']} to ${period['through']}'
          ' · ${supplyDuration(period)} (${period['days']} days) · $basis';
    }
    return '${days.length} days of insufficient STORE supply'
        ' · Small receipts do not restore normal cover · Estimated'
        '${chartNeedsReview ? ' · Stock history needs checking' : ''}';
  }

  DateTime? _monthStart(Object? key) {
    final parts = '$key'.split('/');
    if (parts.length != 2) return null;
    final m = int.tryParse(parts[0]), y = int.tryParse(parts[1]);
    if (m == null || m < 1 || m > 12 || y == null) return null;
    return DateTime(y, m);
  }

  /// Small isolated gaps stay in the detail table; chart marks sustained gaps.
  bool marksMonth(Object? key) {
    if (!hasSupplyAnalysis) return stockNumber(month(key)['empty_days']) >= 7;
    final parts = '$key'.split('/');
    if (parts.length != 2) return false;
    final m = int.tryParse(parts[0]), y = int.tryParse(parts[1]);
    if (m == null || y == null) return false;
    final start = DateTime(y, m), end = DateTime(y, m + 1);
    return supplyPeriods.any((p) {
      final from = DateTime.tryParse('${p['from']}'),
          through = DateTime.tryParse('${p['through']}');
      return from != null &&
          through != null &&
          from.isBefore(end) &&
          !through.isBefore(start);
    });
  }

  String monthDescription(Object? key) {
    final row = month(key);
    if (!marksMonth(key)) return '';
    if (hasSupplyAnalysis) {
      return '${stockNumber(row['limited_days']).toInt()} days of insufficient STORE supply'
          ' · Small receipts do not restore normal cover · Estimated';
    }
    return '${stockNumber(row['empty_days']).toInt()} STORE out-of-stock days'
        ' · ${stockNumber(row['available_days']).toInt()} stocked days'
        ' · ${stockNumber(row['partial_days']).toInt()} partial days'
        ' · $basis';
  }

  List<String> get reasons => [
    for (final issue in data['issues'] as List? ?? [])
      switch (issue) {
        'opening_missing' => 'A unique opening STORE balance is missing.',
        'history_missing' => 'Movement history does not cover this period.',
        'company_mismatch' => 'Company details do not match the stock source.',
        'opening_boundary' => 'Movements on the opening date need checking.',
        'negative_balance' =>
          'The reconstructed history contains a negative balance.',
        'movement_sign' =>
          'Some movement quantities or directions need checking.',
        'current_stock_missing' => 'A unique current STORE balance is missing.',
        'current_stock_not_comparable' =>
          'Recent movements do not yet cover the ledger date.',
        'balance_mismatch' =>
          'The reconstructed balance does not match the ledger.',
        _ => 'Stock history needs checking.',
      },
  ];
  Map<String, dynamic> get exportFields => {
    'STORE review': label,
    'STORE history verified': verified ? 'Yes' : 'No',
    'STORE analysis basis': basis,
    'STORE evidence note': usable ? basisDescription : null,
    'STORE gap (days)': usable ? data['gap_days'] : null,
    'STORE gap is minimum': usable && data['gap_days'] != null
        ? data['at_least'] == true
              ? 'Yes'
              : 'No'
        : null,
    'STORE return date': usable ? data['returned_at'] : null,
    'STORE return received Qty': usable ? data['received_qty'] : null,
    'STORE history through': data['through'],
    'STORE effective supply': hasSupplyAnalysis ? label : null,
    'STORE effective gap from': latestSupplyPeriod['from'],
    'STORE effective gap through': latestSupplyPeriod['through'],
    'STORE effective gap days': latestSupplyPeriod['days'],
    'STORE effective gap duration': hasSupplyAnalysis ? displayGapLabel : null,
    'STORE meaningful return date': latestSupplyPeriod['returned_at'],
    'STORE meaningful return Qty': latestSupplyPeriod['received_qty'],
    'STORE small arrivals during gap': latestSupplyPeriod['small_arrivals'],
    'STORE small arrival Qty during gap':
        latestSupplyPeriod['small_arrival_qty'],
    'STORE learned daily demand': hasSupplyAnalysis
        ? demandModel['daily_qty'] ?? effectiveSupply['daily_qty']
        : null,
    'STORE recovery Qty threshold': hasSupplyAnalysis
        ? demandModel['recovery_qty'] ?? effectiveSupply['recovery_qty']
        : null,
    'STORE effective supply basis': hasSupplyAnalysis
        ? 'Estimated from historical demand and reconciled STORE movements'
        : null,
  };
}
