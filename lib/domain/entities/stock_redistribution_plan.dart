import 'dart:math' as math;
import 'stock_management.dart';
import 'stock_sales_diagnosis.dart';

/// Uses learned branch demand plus declared Daily Order extras. These are
/// reviewable suggestions, not transfer instructions or physical reservations.
class StockRedistributionPlan {
  final List<StockRedistributionBranch> branches;
  final List<StockTransferSuggestion> transfers;
  final DateTime? runDate;
  final bool fresh;
  final int excluded;
  final double declaredExtra;
  final Map<String, String> exclusions;
  const StockRedistributionPlan._(
    this.branches,
    this.transfers,
    this.runDate,
    this.fresh,
    this.excluded,
    this.declaredExtra,
    this.exclusions,
  );
  factory StockRedistributionPlan.fromDiagnosis(StockSalesDiagnosis d) {
    final date = DateTime.tryParse('${d.evidence['daily_order_day']}');
    final stockDay = DateTime.tryParse('${d.evidence['stock_day']}');
    // Daily Order is normally prepared next morning using the previous night's
    // ledger. Older or future order runs cannot drive a redistribution plan.
    final lag = date == null || stockDay == null
        ? -100
        : date.difference(stockDay).inDays;
    final fresh = lag >= 0 && lag <= 1;
    if (!fresh) {
      return StockRedistributionPlan._(
        const [],
        const [],
        date,
        false,
        0,
        0,
        const {},
      );
    }
    final rawBranches = (d.evidence['branches'] as List? ?? []).map(stockMap);
    final byName = {for (final r in rawBranches) '${r['branch_name']}': r};
    String key(Object? value) => '$value'.trim().toLowerCase();
    final orders = <String, List<Map<String, dynamic>>>{};
    for (final r in (d.evidence['daily_order_rows'] as List? ?? []).map(
      stockMap,
    )) {
      orders.putIfAbsent(key(r['branch_key'] ?? r['branch']), () => []).add(r);
    }
    final result = <StockRedistributionBranch>[];
    var excluded = 0;
    var declared = 0.0;
    final exclusions = <String, String>{};
    for (final f in d.branches) {
      final meta = byName[f.branch] ?? const <String, dynamic>{};
      final matches = orders[key(meta['branch_key'] ?? f.branch)];
      if (matches == null) continue;
      if (matches.length != 1) {
        excluded++;
        exclusions[f.branch] =
            'This branch appears more than once in Daily Order. Check which record is correct.';
        continue;
      }
      final row = matches.single;
      declared += math.max(0.0, _number(row['extra_qty_more_than_month']) ?? 0);
      final orderStock = _number(row['branch_stock'], emptyZero: false);
      if (!f.stockKnown ||
          orderStock == null ||
          orderStock < 0 ||
          (orderStock - f.stock).abs() > .000001 ||
          '${row['run_date']}' != date!.toIso8601String().substring(0, 10)) {
        excluded++;
        exclusions[f.branch] =
            'Daily Order shows ${orderStock ?? 'unknown'} Qty, while the stock report shows ${f.stockKnown ? f.stock : 'unknown'} Qty. Check the two reports and their dates before moving stock.';
        continue;
      }
      final unit = _number(row['item_minimum_order_unit'], emptyZero: false);
      if (unit == null || unit <= 0) {
        excluded++;
        exclusions[f.branch] =
            'The minimum Qty that can be ordered or moved is missing or incorrect.';
        continue;
      }
      final extra = math.max(
        0.0,
        _number(row['extra_qty_more_than_month']) ?? 0,
      );
      final daily = f.expected / 3;
      final demand30 = math.max(0.0, _number(row['demand_for_30_days']) ?? 0);
      final sales90 = _number(
        row['total_sales_last_90_days'],
        emptyZero: false,
      );
      final base = math.max(
        0.0,
        _number(row['assortment_qty_base_stock']) ?? 0,
      );
      final maxStock = math.max(0.0, _number(row['reorder_max']) ?? 0);
      final retained = _up(
        [
          daily * 30,
          demand30,
          base,
          maxStock,
          sales90 == null ? f.stock : math.max(0.0, sales90) / 3,
        ].reduce(math.max),
        unit,
      );
      final safeExtra = _down(
        math.max(0, math.min(extra, f.stock - retained)),
        unit,
      );
      final reorder = _number(row['reorder_qty']);
      final finalQty = _number(row['final_reorder_qty_store_stock_gt_0']);
      final pending = _number(row['pending_stock_received']);
      final blocked = '${row['reorder_qty']}'.toUpperCase().contains(
        'NON FORMULARY',
      );
      final canReceive =
          !blocked &&
          reorder != null &&
          finalQty != null &&
          pending != null &&
          pending >= 0 &&
          finalQty >= 0;
      // Pending receipts and planned final allocations reserve the need in the
      // suggestion only. They never increase physical network stock.
      final reserve = canReceive ? pending + finalQty : 0.0;
      final deficit = canReceive
          ? _down(
              math.max(
                0.0,
                math.max(reorder, _up(daily * 7, unit) - f.stock) - reserve,
              ),
              unit,
            )
          : 0.0;
      result.add(
        StockRedistributionBranch(
          f.branch,
          '${meta['branch_group'] ?? 'APG'}',
          f.stock,
          extra,
          safeExtra,
          retained,
          deficit,
          daily,
          unit,
          reserve,
          sales90 != null && sales90 == 0,
          demand30,
        ),
      );
    }
    final donors = result.where((b) => b.safeExtra > 0).toList()
      ..sort((a, b) {
        final cmp = b.safeExtra.compareTo(a.safeExtra);
        return cmp != 0 ? cmp : a.branch.compareTo(b.branch);
      });
    final receivers =
        result.where((b) => b.need > 0 && b.safeExtra == 0).toList()
          ..sort((a, b) {
            final ac = a.daily > 0 ? a.stock / a.daily : double.infinity;
            final bc = b.daily > 0 ? b.stock / b.daily : double.infinity;
            final cmp = ac.compareTo(bc);
            if (cmp != 0) return cmp;
            final demand = b.daily.compareTo(a.daily);
            return demand != 0 ? demand : a.branch.compareTo(b.branch);
          });
    final remaining = {for (final b in donors) b.branch: b.safeExtra};
    final moves = <StockTransferSuggestion>[];
    for (final receiver in receivers) {
      var need = receiver.need;
      for (final donor in donors) {
        // Separate branch-group inventory pools. Cross-group movements require
        // a separate decision rather than being silently suggested here.
        if (donor.branch == receiver.branch ||
            donor.group != receiver.group ||
            (donor.unit - receiver.unit).abs() > .000001) {
          continue;
        }
        final qty = _down(math.min(need, remaining[donor.branch]!), donor.unit);
        if (qty <= 0) continue;
        remaining[donor.branch] = remaining[donor.branch]! - qty;
        need -= qty;
        moves.add(StockTransferSuggestion(donor, receiver, qty));
        if (need < receiver.unit - .000001) break;
      }
    }
    return StockRedistributionPlan._(
      result,
      moves,
      date,
      true,
      excluded,
      declared,
      exclusions,
    );
  }
  double get safeExtra => branches.fold(0, (s, b) => s + b.safeExtra);
  double get suggestedQty => transfers.fold(0, (s, t) => s + t.qty);
  double get totalNeed => branches.fold(0, (s, b) => s + b.need);
  double get unmetNeed => math.max(0, totalNeed - suggestedQty);
  List<StockRedistributionBranch> get donors =>
      branches.where((b) => b.declaredExtra > 0).toList();
  List<StockRedistributionBranch> get receivers =>
      branches.where((b) => b.need > 0).toList();
  static double? _number(Object? value, {bool emptyZero = true}) {
    if (value == null || '$value'.trim().isEmpty || '$value'.trim() == '-') {
      return emptyZero ? 0 : null;
    }
    final parsed = num.tryParse(
      '$value'.replaceAll(',', '').trim(),
    )?.toDouble();
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  static double _down(num qty, double unit) =>
      ((qty + .0000001) / unit).floor() * unit;
  static double _up(num qty, double unit) =>
      ((qty - .0000001) / unit).ceil() * unit;
}

class StockRedistributionBranch {
  final String branch, group;
  final double stock,
      declaredExtra,
      safeExtra,
      retained,
      need,
      daily,
      unit,
      reserved,
      demand30;
  final bool noSales90;
  const StockRedistributionBranch(
    this.branch,
    this.group,
    this.stock,
    this.declaredExtra,
    this.safeExtra,
    this.retained,
    this.need,
    this.daily,
    this.unit,
    this.reserved,
    this.noSales90,
    this.demand30,
  );
}

class StockTransferSuggestion {
  final StockRedistributionBranch from, to;
  final double qty;
  const StockTransferSuggestion(this.from, this.to, this.qty);
  String get reason => from.noSales90
      ? 'The sending branch has extra stock and no sales recorded in 90 days. The receiving branch needs stock.'
      : 'The sending branch can spare this Qty and keep enough for itself. The receiving branch has low stock or still needs its order filled.';
}
