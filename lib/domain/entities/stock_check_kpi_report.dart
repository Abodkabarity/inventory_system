import 'stock_check_campaign.dart';
import 'stock_check_kpi_adjustment.dart';
import 'stock_check_task.dart';

/// One score per branch/item, anchored to the latest selected project.
class StockCheckKpiItem {
  static const tolerance = 0.01;
  static const _roundingNoise = 1e-9;
  final String branch;
  final String code;
  final String name;
  final Map<String, List<StockCheckTask>> _rows;
  final List<StockCheckCampaign> _projects;

  StockCheckKpiItem(List<StockCheckTask> rows, this._projects)
    : branch = rows.first.branchName.trim(),
      code = rows.first.itemCode.trim(),
      name = rows.last.itemName,
      _rows = {} {
    for (final row in rows) {
      _rows.putIfAbsent(row.batchId, () => []).add(row);
    }
  }

  int get projectCount => _rows.length;
  bool get shared => projectCount > 1;
  bool get hasDuplicates => _rows.values.any((rows) => rows.length != 1);
  StockCheckTask? rowFor(String projectId) => _rows[projectId]?.first;
  StockCheckTask? get latestRow => rowFor(_projects.last.id);
  bool get missingLatest => latestRow == null;
  bool get zeroStockLatest =>
      !hasDuplicates &&
      latestRow != null &&
      counted(latestRow!) &&
      normalize(latestRow!.systemQty!) == 0 &&
      normalize(latestRow!.actualQty!) == 0;
  bool get excluded => missingLatest || zeroStockLatest;
  bool get allZeroStock =>
      !hasDuplicates &&
      _projects.every((project) {
        final row = rowFor(project.id);
        return row != null &&
            counted(row) &&
            normalize(row.systemQty!) == 0 &&
            normalize(row.actualQty!) == 0;
      });
  bool get scorable =>
      !excluded &&
      !hasDuplicates &&
      _rows.values.every((rows) => counted(rows.single));
  bool get accurate =>
      scorable &&
      (differenceFor(_projects.last.id) == 0 ||
          (projectCount > 1 && comparisonDifference == 0));
  int? get score => accurate ? 100 : (scorable ? 0 : null);

  /// Normalize differences, never truncate material fractional quantities.
  static num normalize(num value) =>
      value.abs() <= tolerance + _roundingNoise ? 0 : value;

  num? differenceFor(String projectId) {
    final row = rowFor(projectId);
    return row != null && counted(row) ? normalize(row.variance!) : null;
  }

  /// The full range reveals middle-quarter changes even after a correction.
  num? get comparisonDifference {
    if (hasDuplicates || !_rows.values.every((rows) => counted(rows.single))) {
      return null;
    }
    final differences = _rows.values
        .map((rows) => normalize(rows.single.variance!))
        .toList();
    if (differences.length == 1) return differences.single;
    final smallest = differences.reduce((a, b) => a < b ? a : b);
    final largest = differences.reduce((a, b) => a > b ? a : b);
    return normalize(largest - smallest);
  }

  String get result {
    final latest = _label(_projects.last);
    if (missingLatest) return 'Not present in $latest';
    if (hasDuplicates) return 'Duplicate rows — review required';
    if (allZeroStock) {
      return switch (_projects.length) {
        1 => 'Zero stock in $latest',
        2 => 'Zero stock in both quarters',
        _ => 'Zero stock in all quarters',
      };
    }
    if (zeroStockLatest) return 'Zero stock in $latest';
    if (!scorable) return 'Awaiting counts';
    final included = _projects
        .where((p) => differenceFor(p.id) != null)
        .toList();
    // One short category: the most recent meaningful change. Stable later
    // quarters do not add repetitive history or quantities to filter values.
    for (var i = included.length - 1; i > 0; i--) {
      final previous = included[i - 1];
      final current = included[i];
      final before = differenceFor(previous.id)!;
      final after = differenceFor(current.id)!;
      if (normalize(after - before) == 0) continue;
      if (after == 0) {
        return 'Incorrect in ${_label(previous)}, corrected in ${_label(current)}';
      }
      if (before == 0) {
        return 'Correct in ${_label(previous)}, incorrect in ${_label(current)}';
      }
      final magnitudeChange = normalize(after.abs() - before.abs());
      if (magnitudeChange > 0) {
        return 'Variance increased in ${_label(current)}';
      }
      if (magnitudeChange < 0) {
        return 'Variance decreased in ${_label(current)}';
      }
      return 'Variance changed direction in ${_label(current)}';
    }
    if (differenceFor(_projects.last.id) == 0) {
      return projectCount == 1
          ? 'Correct in $latest'
          : 'Correct in all quarters';
    }
    return projectCount == 1
        ? 'Incorrect in $latest'
        : 'Unchanged variance across quarters';
  }

  String _label(StockCheckCampaign project) =>
      project.quarter != null &&
          _projects.map((p) => p.year).toSet().length == 1
      ? 'Q${project.quarter}'
      : project.period.isEmpty
      ? project.title
      : project.period;

  static bool counted(StockCheckTask row) =>
      row.isSubmitted &&
      row.systemQty != null &&
      row.actualQty != null &&
      row.systemQty!.isFinite &&
      row.actualQty!.isFinite;

  /// Change from the preceding included project with submitted quantities.
  num? differenceChange(String projectId, List<StockCheckCampaign> projects) {
    final current = rowFor(projectId);
    if (current == null || !counted(current)) return null;
    StockCheckTask? previous;
    for (final project in projects) {
      if (project.id == projectId) {
        return previous == null
            ? null
            : normalize(
                normalize(current.variance!) - normalize(previous.variance!),
              );
      }
      final row = rowFor(project.id);
      if (row != null && counted(row)) previous = row;
    }
    return null;
  }
}

class StockCheckKpiTotals {
  final List<StockCheckKpiItem> items;
  StockCheckKpiTotals(Iterable<StockCheckKpiItem> items)
    : items = List.unmodifiable(items);

  int get total => items.length;
  late final int scored = items.where((item) => item.scorable).length;
  late final int correct = items
      .where((item) => item.scorable && item.accurate)
      .length;
  int get failed => scored - correct;
  late final int excluded = items.where((item) => item.excluded).length;
  int get awaiting => total - scored - excluded;
  late final int shared = items.where((item) => item.shared).length;
  int get standalone => total - shared;
  double? get accuracy => scored == 0 ? null : correct * 100 / scored;
}

class StockCheckKpiReport extends StockCheckKpiTotals {
  final StockCheckKpiAdjustments? adjustments;
  final List<StockCheckCampaign> projects;
  final List<String> incompleteProjectIds;
  late final Map<String, StockCheckKpiTotals> branches = _groupBranches();

  factory StockCheckKpiReport({
    required List<StockCheckCampaign> projects,
    required List<StockCheckTask> rows,
    StockCheckKpiAdjustments? adjustments,
  }) {
    final ordered = List<StockCheckCampaign>.of(projects)
      ..sort((a, b) {
        if (a.year != null &&
            a.quarter != null &&
            b.year != null &&
            b.quarter != null) {
          final period = (a.year! * 4 + a.quarter!).compareTo(
            b.year! * 4 + b.quarter!,
          );
          if (period != 0) return period;
        }
        final sent = (a.sentAt ?? DateTime(2000)).compareTo(
          b.sentAt ?? DateTime(2000),
        );
        return sent != 0 ? sent : a.id.compareTo(b.id);
      });
    final ids = ordered.map((project) => project.id).toSet();
    final loadedCounts = <String, int>{};
    for (final row in rows) {
      loadedCounts.update(row.batchId, (count) => count + 1, ifAbsent: () => 1);
    }
    final incomplete = ordered
        .where(
          (project) =>
              (loadedCounts[project.id] ?? 0) != project.total &&
              project.total > 0,
        )
        .map((project) => project.id)
        .toList();
    // An unloaded project must never look like an absent product.
    if (incomplete.isNotEmpty) {
      return StockCheckKpiReport._(
        List.unmodifiable(ordered),
        const [],
        List.unmodifiable(incomplete),
      );
    }
    final grouped = <String, List<StockCheckTask>>{};
    for (final row in rows) {
      if (!ids.contains(row.batchId)) continue;
      final key =
          '${row.branchName.trim().toLowerCase()}\u0000'
          '${row.itemCode.trim().toLowerCase()}';
      grouped.putIfAbsent(key, () => []).add(row);
    }
    final items =
        grouped.values.map((rows) => StockCheckKpiItem(rows, ordered)).toList()
          ..sort((a, b) {
            final branch = a.branch.toLowerCase().compareTo(
              b.branch.toLowerCase(),
            );
            return branch != 0 ? branch : a.code.compareTo(b.code);
          });
    return StockCheckKpiReport._(
      List.unmodifiable(ordered),
      items,
      const [],
      adjustments,
    );
  }

  StockCheckKpiReport._(
    this.projects,
    super.items,
    this.incompleteProjectIds, [
    this.adjustments,
  ]);

  StockCheckKpiReport withAdjustments(StockCheckKpiAdjustments adjustments) =>
      StockCheckKpiReport._(projects, items, incompleteProjectIds, adjustments);

  Map<String, StockCheckKpiTotals> _groupBranches() {
    final grouped = <String, List<StockCheckKpiItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.branch.toLowerCase(), () => []).add(item);
    }
    return Map.unmodifiable(
      grouped.map(
        (_, items) => MapEntry(items.first.branch, StockCheckKpiTotals(items)),
      ),
    );
  }
}
