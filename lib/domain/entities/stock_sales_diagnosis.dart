import 'dart:math' as math;

import 'stock_management.dart';
import 'stock_daily_sales.dart';

/// Small, deterministic statistical learner. Forecasts are fitted separately
/// per branch, using only earlier fully stocked days when those are auditable.
/// Cause attribution is an evidence policy, not a trained causal classifier.
class StockSalesDiagnosis {
  final Map<String, dynamic> evidence;
  final List<StockBranchForecast> branches;
  final double expected, actual, error, dailyDemand, storeStock, physicalStock;
  final double auditedShare,
      emptyShare,
      shortShare,
      beforeAvailability,
      recentAvailability;
  final bool significantDrop;
  final String status;
  const StockSalesDiagnosis._(
    this.evidence,
    this.branches,
    this.expected,
    this.actual,
    this.error,
    this.dailyDemand,
    this.storeStock,
    this.physicalStock,
    this.auditedShare,
    this.emptyShare,
    this.shortShare,
    this.beforeAvailability,
    this.recentAvailability,
    this.significantDrop,
    this.status,
  );

  factory StockSalesDiagnosis.fromMap(Map<String, dynamic> data) {
    final through = DateTime.parse('${data['through']}');
    final rows = (data['branches'] as List? ?? []).map(stockMap).toList();
    final branches = rows
        .where((r) => r['branch_name'] != 'STORE')
        .map((r) => StockBranchForecast.fit(r, through))
        .toList();
    double sum(double Function(StockBranchForecast) f) =>
        branches.fold(0, (a, b) => a + f(b));
    final expected = sum((b) => b.expected);
    final actual = sum((b) => b.actual);
    final rate = expected / 3;
    // Sum absolute errors conservatively; correlated branches are not assumed
    // independent. This is an anomaly tolerance, never a probability interval.
    final error = sum((b) => b.error * 3);
    final storeRow = rows.where((r) => r['branch_name'] == 'STORE').firstOrNull;
    final store = math.max(0.0, stockNumber(storeRow?['current_qty']));
    final physical = store + sum((b) => math.max(0, b.stock));
    final audited = expected <= 0
        ? 0.0
        : sum((b) => b.audited && b.availabilityTrained ? b.expected : 0) /
              expected;
    final empty = expected <= 0
        ? 0.0
        : sum((b) => b.stockKnown && b.stock <= 0 ? b.expected : 0) / expected;
    final short = expected <= 0
        ? 0.0
        : sum((b) => b.stockKnown && b.stock < b.expected ? b.expected : 0) /
              expected;
    final before = expected <= 0
        ? 0.0
        : sum((b) => b.audited ? b.expected * b.beforeAvailability : 0) /
              expected;
    final recent = expected <= 0
        ? 0.0
        : sum((b) => b.audited ? b.expected * b.recentAvailability : 0) /
              expected;
    final drop =
        expected >= 3 &&
        actual < expected * .65 &&
        expected - actual > math.max(3, error);
    final enough = branches.where((b) => b.trained).isNotEmpty && expected > 0;
    final stockCoverage = expected <= 0
        ? 0.0
        : sum((b) => b.stockKnown ? b.expected : 0) / expected;
    final recentRows = rows
        .where((r) => r['branch_name'] != 'STORE')
        .expand((r) => (r['sales_days'] as List? ?? []).map(stockMap))
        .where((r) {
          final day = DateTime.tryParse('${r['day']}');
          return day != null &&
              !day.isBefore(through.subtract(const Duration(days: 2))) &&
              !day.isAfter(through);
        });
    final gross = recentRows.fold<double>(
      0,
      (s, r) => s + stockNumber(r['gross_qty']),
    );
    final returned = recentRows.fold<double>(
      0,
      (s, r) => s + stockNumber(r['return_qty']),
    );
    final status = !enough
        ? 'learning'
        : stockCoverage < .8 || data['stock_day'] != data['through']
        ? 'review_availability'
        : short >= .35 && rate > 0 && store / rate >= 7
        ? 'distribution_delay'
        : drop && audited >= .7 && before >= .7 && recent < before - .2
        ? 'availability_decline'
        : rate > 0 && physical / rate < 7 && short >= .35
        ? 'limited_supply'
        : short >= .35
        ? 'branch_shortage'
        : drop && gross >= expected * .8 && returned >= (expected - actual) * .5
        ? 'returns_impact'
        : drop && audited >= .8 && before >= .9 && recent >= .9 && empty < .1
        ? 'demand_slowing'
        : drop
        ? 'sales_declining'
        : rate > 0 && store == 0 && short < .2
        ? 'distributed'
        : audited < .7
        ? 'stable_sales'
        : 'healthy';
    return StockSalesDiagnosis._(
      data,
      branches,
      expected,
      actual,
      error,
      rate,
      store,
      physical,
      audited,
      empty,
      short,
      before,
      recent,
      drop,
      status,
    );
  }

  String get label => switch (status) {
    'distribution_delay' => 'Send stock to branches',
    'availability_decline' => 'Low stock may explain lower sales',
    'limited_supply' => 'Limited stock',
    'branch_shortage' => 'Some selling branches need stock',
    'stable_sales' => 'Sales are steady',
    'returns_impact' => 'Returns lowered the sales total',
    'demand_slowing' => 'Sales may be slowing',
    'sales_declining' => 'Sales lower than usual',
    'distributed' => 'Stock is in the branches',
    'review_availability' => 'Branch stock needs checking',
    'learning' => 'More sales history needed',
    _ => 'Healthy',
  };
  String get explanation => switch (status) {
    'distribution_delay' =>
      'STORE has enough stock for about a week or more, but several selling branches have less than 3 days left. These branches may need a delivery from STORE.',
    'availability_decline' =>
      'Sales dropped as stock ran low in branches that usually sell this product. Some customers may not have been able to buy it because it was not available.',
    'limited_supply' =>
      'The stock left in STORE and all branches together is estimated to last less than a week. Some branches that usually sell this product are already short of stock.',
    'branch_shortage' =>
      'Some branches that usually sell this product have less than 3 days of stock left. Other branches may have more than they need, so moving stock between branches could help.',
    'stable_sales' =>
      'Sales have not dropped much compared with the estimate. We still need more stock history to know whether every selling branch has enough.',
    'returns_impact' =>
      'Customers bought close to the expected Qty, but returned products reduced the final sales total. The lower total does not necessarily mean fewer customers wanted the product.',
    'demand_slowing' =>
      'Sales fell even though the selling branches still had stock. Customers may be buying less, but check that all sales have been uploaded before deciding.',
    'sales_declining' =>
      'Sales are lower than we expected from earlier days. We cannot yet tell whether customers are buying less or whether selling branches do not have enough stock.',
    'distributed' =>
      'STORE has no stock, but the main selling branches still have at least 3 days of estimated sales left. The product is still available in those branches.',
    'review_availability' =>
      'We can compare sales, but some branch stock is missing or comes from a different date. Update the stock and sales data so we can check whether the branches have enough.',
    'learning' =>
      'There are not enough earlier sales to estimate how much this product normally sells. You can still see the current stock and the latest delivery below.',
    _ =>
      'Sales are close to the estimate, and no large shortage was found in the selling branches for these dates.',
  };
  String get action => receiptAfterCutoff
      ? 'Check the newest MRN delivery and update branch stock before buying more. Then send stock to the selling branches that need it most.'
      : receiptAwaitingMovements
      ? 'Confirm the latest receipt is included in stock. Send it to the branches that need it before buying more.'
      : switch (status) {
          'distribution_delay' =>
            'Send stock first to branches that usually sell more and have little left.',
          'availability_decline' || 'limited_supply' || 'branch_shortage' =>
            'Check for a recent delivery or extra stock in other branches. Send stock first to the selling branches with the least left.',
          'demand_slowing' =>
            'Check Cash, Online and Insurance sales, prices, and the same weekdays in earlier weeks before buying less.',
          'returns_impact' =>
            'Check the returned Qty before deciding that customers are buying less.',
          'sales_declining' || 'review_availability' =>
            'Check recent branch deliveries and make sure all sales have been uploaded.',
          'learning' =>
            'Check branch requests and the latest delivery while more daily sales are collected.',
          _ =>
            'Keep checking how much stock is left in selling branches and when the next delivery is due.',
        };
  double? get networkCover =>
      dailyDemand > 0 ? physicalStock / dailyDemand : null;
  Map<String, dynamic> get latestMrn => stockMap(evidence['latest_mrn']);
  bool get receiptAfterCutoff {
    final receipt = DateTime.tryParse('${latestMrn['day']}');
    final through = DateTime.tryParse('${evidence['through']}');
    return receipt != null && through != null && receipt.isAfter(through);
  }

  double? get receiptCover => dailyDemand > 0 && latestMrn['qty'] != null
      ? stockNumber(latestMrn['qty']) / dailyDemand
      : null;
  bool get receiptAwaitingMovements =>
      latestMrn['qty'] != null &&
      evidence['latest_mrn_movement_qty'] != null &&
      (stockNumber(latestMrn['qty']) -
                  stockNumber(evidence['latest_mrn_movement_qty']))
              .abs() >
          .000001;
  // The latest receipt is historical: compare to learned demand, never add it
  // again to current stock or imply its units are still present.
  String get receiptAssessment => latestMrn['qty'] == null
      ? 'No approved MRN found for this product'
      : receiptCover == null
      ? 'There are not enough sales to estimate how long this delivery could last'
      : auditedShare < .7
      ? 'At recent sales levels, this delivery could last about ${receiptCover!.toStringAsFixed(1)} days. This is a rough guide because we could not check enough days when the product was available'
      : receiptCover! < 3
      ? 'This delivery would last less than 3 days at the estimated selling rate'
      : 'This delivery would last about ${receiptCover!.toStringAsFixed(1)} days at the estimated selling rate';
  Map<String, dynamic> get exportFields => {
    'Sales and stock result': label,
    'What the result means': explanation,
    'Sales and stock checked through': evidence['through'],
    'Expected sales Qty in 3 days': expected,
    'Sold Qty in 3 days': actual,
    'Estimated days the remaining stock may last': networkCover,
    'Expected sales supported by checked stock records (%)': auditedShare,
    'Latest STORE MRN date': latestMrn['day'],
    'Latest STORE MRN Qty': latestMrn['qty'],
    'Estimated days the last delivery could last': receiptCover,
    'Latest MRN not fully shown in stock movements': receiptAwaitingMovements,
    'What to do next': action,
  };

  /// Descriptive channel comparison using exactly the same source cutoff.
  /// Channel changes are evidence to investigate, not an inferred cause.
  List<Map<String, dynamic>> channelChanges(StockDailySalesMix? mix) {
    if (mix == null ||
        !mix.available ||
        mix.days.length < 17 ||
        mix.days.last.isoDate != evidence['through']) {
      return const [];
    }
    final prior = mix.days.take(mix.days.length - 3).toList();
    final recent = mix.days.skip(mix.days.length - 3).toList();
    return [
      for (final channel in StockSalesChannel.values)
        {
          'channel': channel.label,
          'previous_daily_qty':
              prior.fold<double>(0, (s, d) => s + d.qty(channel)) /
              prior.length,
          'last_3_daily_qty':
              recent.fold<double>(0, (s, d) => s + d.qty(channel)) / 3,
        },
    ];
  }
}

class _Day {
  final DateTime date;
  final double qty, gross, returns;
  final bool stocked;
  const _Day(this.date, this.qty, this.gross, this.returns, this.stocked);
}

class StockBranchForecast {
  final String branch, method;
  final double stock,
      expected,
      actual,
      error,
      beforeAvailability,
      recentAvailability;
  final bool stockKnown, audited, availabilityTrained, trained;
  final int trainingDays, validationDays;
  const StockBranchForecast(
    this.branch,
    this.method,
    this.stock,
    this.expected,
    this.actual,
    this.error,
    this.beforeAvailability,
    this.recentAvailability,
    this.stockKnown,
    this.audited,
    this.availabilityTrained,
    this.trained,
    this.trainingDays,
    this.validationDays,
  );

  static StockBranchForecast fit(Map<String, dynamic> row, DateTime through) {
    final sales = {
      for (final r in (row['sales_days'] as List? ?? []).map(stockMap))
        '${r['day']}': r,
    };
    final movements = {
      for (final r in (row['movements'] as List? ?? []).map(stockMap))
        '${r['day']}': r,
    };
    String key(DateTime d) => d.toIso8601String().substring(0, 10);
    var balance = stockNumber(row['opening_qty']);
    var nonnegative = balance >= 0;
    final observations = <_Day>[];
    final start = through.subtract(const Duration(days: 44));
    // Compute forward from the opening boundary, not by subtracting guessed
    // missing movements from today's stock. Same-day stockouts are excluded.
    for (
      var d = DateTime(2026, 1, 2);
      !d.isAfter(through);
      d = d.add(const Duration(days: 1))
    ) {
      final before = balance;
      final m = movements[key(d)];
      balance += stockNumber(m?['net']);
      if (balance < -.000001) nonnegative = false;
      if (!d.isBefore(start)) {
        final s = sales[key(d)];
        observations.add(
          _Day(
            d,
            stockNumber(s?['qty']),
            stockNumber(s?['gross_qty']),
            stockNumber(s?['return_qty']),
            before > 0 && balance > 0 && m?['adjustment'] != true,
          ),
        );
      }
    }
    final audited = row['reconciled'] == true && nonnegative;
    final prior = observations
        .where(
          (d) => d.date.isBefore(through.subtract(const Duration(days: 2))),
        )
        .toList();
    final stocked = prior.where((d) => d.stocked).toList();
    final availabilityTrained =
        audited &&
        stocked.length >= 21 &&
        stocked.where((d) => d.gross > 0).length >= 3;
    final eligible = availabilityTrained ? stocked : prior;
    // Missing availability is never converted to a stocked day. A fallback
    // model predicts observed sales only, and cannot establish weaker demand.
    final trained =
        eligible.length >= 21 && eligible.where((d) => d.gross > 0).length >= 3;
    final selection = eligible
        .where(
          (d) =>
              !d.date.isAfter(through.subtract(const Duration(days: 10))) &&
              !d.date.isBefore(through.subtract(const Duration(days: 16))),
        )
        .toList();
    var best = 'mean';
    var bestError = double.infinity;
    double score(String method, List<_Day> targets) {
      if (targets.isEmpty) return double.infinity;
      return targets.fold<double>(
            0,
            (sum, d) =>
                sum +
                (_predict(
                          eligible
                              .where((x) => x.date.isBefore(d.date))
                              .toList(),
                          d.date,
                          method,
                        ) -
                        math.max(0, d.qty))
                    .abs(),
          ) /
          targets.length;
    }

    if (trained && selection.length >= 4) {
      for (final method in ['mean', 'recent14', 'weekday']) {
        final e = score(method, selection);
        if (e < bestError * .98) {
          best = method;
          bestError = e;
        }
      }
    }
    final holdout = eligible
        .where(
          (d) => d.date.isAfter(through.subtract(const Duration(days: 10))),
        )
        .toList();
    final error = trained && holdout.length >= 4
        ? score(best, holdout)
        : eligible.isEmpty
        ? 0.0
        : math.max(
            1.0,
            eligible.fold<double>(0, (s, d) => s + d.gross) / eligible.length,
          );
    var expected = 0.0, actual = 0.0;
    for (final day in observations.skip(math.max(0, observations.length - 3))) {
      expected += _predict(eligible, day.date, best);
      actual += day.qty;
    }
    double availability(List<_Day> days) =>
        days.isEmpty ? 0 : days.where((d) => d.stocked).length / days.length;
    return StockBranchForecast(
      '${row['branch_name']}',
      best,
      stockNumber(row['current_qty']),
      expected,
      actual,
      error,
      availability(prior.skip(math.max(0, prior.length - 14)).toList()),
      availability(
        observations.skip(math.max(0, observations.length - 3)).toList(),
      ),
      stockNumber(row['current_rows']) == 1 && row['current_qty'] != null,
      audited,
      availabilityTrained,
      trained,
      eligible.length,
      holdout.length,
    );
  }

  static double _predict(List<_Day> history, DateTime date, String method) {
    if (history.isEmpty) return 0;
    double mean(List<_Day> days) => days.isEmpty
        ? 0
        : days.fold<double>(0, (s, d) => s + math.max(0, d.qty)) / days.length;
    final average = mean(history);
    if (method == 'recent14') {
      final recent = history
          .where(
            (d) => !d.date.isBefore(date.subtract(const Duration(days: 14))),
          )
          .toList();
      return recent.length >= 7 ? mean(recent) : average;
    }
    if (method == 'weekday') {
      final same = history
          .where((d) => d.date.weekday == date.weekday)
          .toList();
      // Shrink sparse weekday estimates towards the branch mean.
      return (mean(same) * same.length + average * 3) / (same.length + 3);
    }
    return average;
  }
}
