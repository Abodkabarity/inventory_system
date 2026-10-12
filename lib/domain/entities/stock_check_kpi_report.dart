import 'stock_check_campaign.dart';
import 'stock_check_task.dart';

/// Each branch/item earns one mark across every selected project containing it.
class StockCheckKpiItem {
  // Allow only floating-point rounding noise when comparing a difference to zero.
  static const tolerance = 1e-9;
  final String branch;
  final String code;
  final String name;
  final Map<String, List<StockCheckTask>> _rows;

  StockCheckKpiItem(List<StockCheckTask> rows)
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
  bool get scorable =>
      !hasDuplicates && _rows.values.every((rows) => counted(rows.single));
  bool get accurate =>
      scorable &&
      _rows.values.every((rows) => rows.single.variance!.abs() <= tolerance);
  int? get score => scorable ? (accurate ? 100 : 0) : null;

  /// All included quarters participate; equal first/last quarters cannot hide
  /// a difference in a middle quarter. A single-quarter item uses its variance.
  num? get comparisonDifference {
    if (!scorable) return null;
    final differences = _rows.values
        .map((rows) => rows.single.variance!)
        .toList();
    if (differences.length == 1) return differences.single;
    final smallest = differences.reduce((a, b) => a < b ? a : b);
    final largest = differences.reduce((a, b) => a > b ? a : b);
    final spread = largest - smallest;
    return spread.abs() <= tolerance ? 0 : spread;
  }

  String get result => hasDuplicates
      ? 'Duplicate rows — needs review'
      : !scorable
      ? 'Awaiting submitted counts'
      : accurate
      ? '100% — zero difference in every included project'
      : '0% — non-zero difference';

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
        return previous == null ? null : current.variance! - previous.variance!;
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
  late final int correct = items.where((item) => item.accurate).length;
  int get failed => scored - correct;
  int get awaiting => total - scored;
  late final int shared = items.where((item) => item.shared).length;
  int get standalone => total - shared;
  double? get accuracy => scored == 0 ? null : correct * 100 / scored;
}

class StockCheckKpiReport extends StockCheckKpiTotals {
  final List<StockCheckCampaign> projects;
  final List<String> incompleteProjectIds;
  late final Map<String, StockCheckKpiTotals> branches = _groupBranches();

  factory StockCheckKpiReport({
    required List<StockCheckCampaign> projects,
    required List<StockCheckTask> rows,
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
    final items = grouped.values.map(StockCheckKpiItem.new).toList()
      ..sort((a, b) {
        final branch = a.branch.toLowerCase().compareTo(b.branch.toLowerCase());
        return branch != 0 ? branch : a.code.compareTo(b.code);
      });
    return StockCheckKpiReport._(List.unmodifiable(ordered), items, const []);
  }

  StockCheckKpiReport._(this.projects, super.items, this.incompleteProjectIds);

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
