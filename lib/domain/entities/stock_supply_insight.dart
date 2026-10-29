import 'stock_management.dart';

/// STORE system-stock evidence; retail availability and demand are separate.
class StockSupplyInsight {
  final Map<String, dynamic> data;
  final double? _storeQty;
  final double? _branchesQty;
  final bool _stockUnavailable;
  final bool _hasStoreSnapshot, _hasBranchesSnapshot;
  const StockSupplyInsight(
    this.data, {
    double? storeQty,
    double? branchesQty,
    bool stockUnavailable = false,
    bool hasStoreSnapshot = false,
    bool hasBranchesSnapshot = false,
  }) : _storeQty = storeQty,
       _branchesQty = branchesQty,
       _stockUnavailable = stockUnavailable,
       _hasStoreSnapshot = hasStoreSnapshot,
       _hasBranchesSnapshot = hasBranchesSnapshot;
  factory StockSupplyInsight.of(StockManagementItem item) => StockSupplyInsight(
    stockMap(item.data['supply_insight']),
    storeQty: item.stockAvailable
        ? _finiteNumber(item.data['store_stock'])
        : null,
    branchesQty: _finiteNumber(item.data['branches_stock']),
    stockUnavailable: !item.stockAvailable,
    hasStoreSnapshot: item.data.containsKey('store_stock'),
    // The current product reference is authoritative; an omitted branch
    // quantity means zero, rather than a fallback to an old receipt snapshot.
    hasBranchesSnapshot: true,
  );
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
  Map<String, dynamic> get returnAssessment =>
      usable && status == 'back_in_store'
      ? stockMap(data['return_assessment'])
      : const {};
  bool get hasReturnAssessment {
    final row = returnAssessment;
    final date = DateTime.tryParse('${row['returned_at']}');
    final through = DateTime.tryParse('${data['through']}');
    return date != null &&
        through != null &&
        !date.isAfter(through) &&
        row['returned_at'] == data['returned_at'] &&
        _finiteNumber(data['current_qty']) == 0 &&
        stockNumber(row['received_qty']) > 0 &&
        stockNumber(row['gap_days']) >= 30 &&
        const {'enough', 'limited', 'unknown'}.contains(row['coverage']);
  }

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

  String get displayGapLabel => hasReturnAssessment
      ? supplyDuration(returnAssessment)
      : hasSupplyAnalysis
      ? supplyDuration(latestSupplyPeriod)
      : gapLabel;
  String get basis => !usable
      ? 'Needs checking'
      : inferred
      ? 'Estimated'
      : 'Verified';
  String get basisDescription => [
    if (data['opening_basis'] == 'assumed_zero')
      'Opening STORE stock is assumed zero because this item was omitted from the opening report.',
    if (data['provisional'] == true && data['endpoint_inferred'] != true)
      'Recent movements or MRN receipts extend the archive provisionally and match the current STORE ledger.',
    if (data['endpoint_inferred'] == true)
      'Arrival history and current STORE stock are assessed separately; the movement balance is retained for comparison.',
    if (data['current_qty_basis'] == 'omitted_means_zero')
      'The item is absent from the latest STORE report and is counted as zero.',
  ].join(' ');
  // Availability is a current stock observation. Historical returns never
  // override it, even if the last delivery was enough when it arrived.
  String get currentState {
    final qty = currentStoreQty;
    if (qty == null) return 'unknown';
    if (qty < 0) return 'invalid';
    if (qty == 0) return 'empty';
    final daily = estimatedDailyDemand;
    if (daily == null) return 'cover_unknown';
    final recordedMinimum = _finiteNumber(demandModel['entry_qty']);
    final configuredDays = _finiteNumber(demandModel['entry_cover_days']);
    final minimumDays = configuredDays != null && configuredDays > 0
        ? configuredDays
        : 7;
    final minimum = recordedMinimum != null && recordedMinimum > 0
        ? recordedMinimum
        : (daily * minimumDays).ceilToDouble();
    return qty < minimum ? 'limited' : 'available';
  }

  String get branchAvailability {
    final qty = currentBranchesQty;
    return qty > 0 ? 'Available in branches' : 'Unavailable in branches';
  }

  bool get showCurrentStatus =>
      present ||
      currentStoreQty != null ||
      currentBranchesQty > 0 ||
      _hasBranchesSnapshot ||
      _stockUnavailable;
  String get label {
    if (currentState == 'unknown' && _stockUnavailable) {
      return 'Stock data unavailable';
    }
    final store = switch (currentState) {
      'empty' => 'STORE empty',
      'limited' => 'Limited stock',
      'available' => 'Stock available',
      'cover_unknown' => 'In STORE',
      'invalid' => 'Check STORE stock',
      _ => 'STORE stock unknown',
    };
    return '$store · $branchAvailability';
  }

  String get currentLabel => label;
  String get currentCoverLabel => switch (currentState) {
    'empty' => 'STORE empty',
    'limited' => 'Limited stock (estimated)',
    'available' => 'Enough stock (estimated)',
    'cover_unknown' => 'Cover not confirmed',
    _ => 'Current stock unknown',
  };

  String get returnCoverLabel => !usable
      ? ''
      : hasReturnAssessment
      ? switch (returnAssessment['coverage']) {
          'enough' => 'Enough at arrival (estimated)',
          'limited' => 'Limited at arrival (estimated)',
          _ => 'Cover not confirmed',
        }
      : hasSupplyAnalysis
      ? effectiveSupply['status'] == 'limited_supply'
            ? 'Limited stock now'
            : 'Enough stock (estimated)'
      : status == 'back_in_store'
      ? 'Cover not confirmed'
      : '';

  String get currentExplanation {
    final store = switch (currentState) {
      'empty' => 'STORE currently has no stock.',
      'limited' =>
        'Current STORE stock is below the estimated minimum supply level.',
      'available' =>
        'Current STORE stock covers the estimated minimum supply level.',
      'cover_unknown' =>
        'Stock is present in STORE. Demand cannot yet be estimated reliably, so quantity coverage is not confirmed.',
      'invalid' =>
        'The reported STORE quantity is negative and needs checking.',
      _ => 'Current STORE stock is not available in the loaded report.',
    };
    final branches = currentBranchesQty > 0
        ? 'Stock is recorded in some branches; this does not mean every branch has stock.'
        : 'Branch stock is zero; an absent quantity in the current reference is counted as zero.';
    return '$store $branches';
  }

  static double? _finiteNumber(dynamic value) {
    final n = value is num ? value.toDouble() : double.tryParse('$value');
    return n != null && n.isFinite ? n : null;
  }

  double? get estimatedDailyDemand {
    if (!hasSupplyAnalysis && !hasReturnAssessment) return null;
    final daily = _finiteNumber(
      hasReturnAssessment
          ? returnAssessment['daily_qty']
          : demandModel['daily_qty'] ?? effectiveSupply['daily_qty'],
    );
    return daily != null && daily > 0 ? daily : null;
  }

  double? get currentStoreQty => _stockUnavailable
      ? null
      : _hasStoreSnapshot
      ? _storeQty
      : _storeQty ?? (usable ? _finiteNumber(data['current_qty']) : null);

  double get currentBranchesQty => _hasBranchesSnapshot
      ? _branchesQty ?? 0
      : _branchesQty ??
            (usable
                ? _finiteNumber(
                    data['current_branches_qty'] ??
                        returnAssessment['branches_qty'],
                  )
                : null) ??
            0;

  double? get estimatedStoreCoverDays {
    final daily = estimatedDailyDemand, qty = currentStoreQty;
    if (daily == null || qty == null || qty < 0) return null;
    final cover = qty / daily;
    return cover.isFinite ? cover : null;
  }

  /// A receipt's historical coverage is never recomputed from today's balance.
  Map<String, dynamic> get latestReturn {
    if (!usable) return const {};
    final candidates = <Map<String, dynamic>>[
      for (final event in returns)
        {
          ...event,
          'date': event['returned_at'],
          'qty': event['received_qty'],
          'kind': 'unknown',
        },
      if (data['returned_at'] != null)
        {
          'date': data['returned_at'],
          'qty': data['received_qty'],
          'kind': 'unknown',
        },
      if (latestSupplyPeriod['returned_at'] != null)
        {
          'date': latestSupplyPeriod['returned_at'],
          'qty': latestSupplyPeriod['received_qty'],
          'kind': 'restored',
        },
      if (!chartNeedsReview) ...chartArrivals,
      if (hasReturnAssessment)
        {
          'date': returnAssessment['returned_at'],
          'qty': returnAssessment['received_qty'],
          'kind': switch (returnAssessment['coverage']) {
            'enough' => 'restored',
            'limited' => 'limited',
            _ => 'unknown',
          },
        },
    ];
    final through = DateTime.tryParse('${data['through']}');
    Map<String, dynamic> latest = const {};
    DateTime? latestDate;
    for (final candidate in candidates) {
      final date = DateTime.tryParse('${candidate['date']}');
      if (date == null ||
          (through != null && date.isAfter(through)) ||
          (_finiteNumber(candidate['qty']) ?? 0) <= 0) {
        continue;
      }
      if (latestDate == null || !date.isBefore(latestDate)) {
        latest = candidate;
        latestDate = date;
      }
    }
    return latest;
  }

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
      switch (arrival['kind']) {
        'restored' => 'Enough stock at arrival (estimated)',
        'limited' => 'Limited stock at arrival (estimated)',
        _ => 'Cover at arrival not confirmed',
      };

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
    'STORE current status': currentLabel,
    'STORE current status explanation': showCurrentStatus
        ? currentExplanation
        : null,
    'STORE current cover assessment': currentCoverLabel,
    'STORE current branches availability': branchAvailability,
    'STORE estimated stock cover days': estimatedStoreCoverDays,
    'STORE current quantity basis': data['current_qty_basis'],
    'STORE returned Qty estimated cover days': hasReturnAssessment
        ? returnAssessment['receipt_cover_days']
        : null,
    'STORE return estimated daily demand': hasReturnAssessment
        ? returnAssessment['daily_qty']
        : null,
    'STORE returned Qty cover assessment': hasReturnAssessment
        ? returnAssessment['coverage']
        : null,
    'STORE stock movement endpoint difference': data['endpoint_difference'],
    'STORE last marked return date': latestReturn['date'],
    'STORE last marked return Qty': latestReturn['qty'],
    'STORE last marked return cover': latestReturn.isEmpty
        ? null
        : arrivalLabel(latestReturn),
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
