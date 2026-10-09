import 'stock_check_task.dart';

class StockCheckKpiItemPair {
  final StockCheckTask? previous;
  final StockCheckTask? current;
  const StockCheckKpiItemPair(this.previous, this.current);
  String get branch => (current ?? previous)!.branchName;
  String get code => (current ?? previous)!.itemCode;
  String get name => (current ?? previous)!.itemName;
  bool get comparable => _counted(previous) && _counted(current);
  static bool _counted(StockCheckTask? row) =>
      row != null &&
      row.isSubmitted &&
      row.systemQty != null &&
      row.actualQty != null;
  static bool accurate(StockCheckTask? row) =>
      _counted(row) && row!.variance!.abs() <= .010000001;
  String get result {
    if (previous == null) return 'Added';
    if (current == null) return 'Removed';
    if (!comparable) return 'Awaiting counts';
    final oldDiff = accurate(previous) ? 0 : previous!.variance!.abs();
    final newDiff = accurate(current) ? 0 : current!.variance!.abs();
    if (accurate(previous) && accurate(current)) return 'Unchanged';
    if (newDiff < oldDiff - 1e-9) return 'Improved';
    if (newDiff > oldDiff + 1e-9) return 'Worsened';
    if ((previous!.variance! - current!.variance!).abs() > .01) {
      return 'Direction changed';
    }
    return 'Unchanged';
  }
}

class StockCheckKpiComparison {
  final List<StockCheckKpiItemPair> items;
  StockCheckKpiComparison(
    List<StockCheckTask> previous,
    List<StockCheckTask> current,
  ) : items = _pair(previous, current);
  static List<StockCheckKpiItemPair> _pair(
    List<StockCheckTask> previous,
    List<StockCheckTask> current,
  ) {
    String key(StockCheckTask row) =>
        '${row.branchName.trim().toLowerCase()}\u0000${row.itemCode.trim().toLowerCase()}';
    final old = {for (final row in previous) key(row): row};
    final latest = {for (final row in current) key(row): row};
    final keys = {...old.keys, ...latest.keys}.toList()..sort();
    return List.unmodifiable(
      keys.map((key) => StockCheckKpiItemPair(old[key], latest[key])),
    );
  }

  late final List<StockCheckKpiItemPair> comparable = items
      .where((item) => item.comparable)
      .toList(growable: false);
  double? get previousAccuracy => comparable.isEmpty
      ? null
      : comparable
                .where((item) => StockCheckKpiItemPair.accurate(item.previous))
                .length *
            100 /
            comparable.length;
  double? get currentAccuracy => comparable.isEmpty
      ? null
      : comparable
                .where((item) => StockCheckKpiItemPair.accurate(item.current))
                .length *
            100 /
            comparable.length;
  double? get delta =>
      comparable.isEmpty ? null : currentAccuracy! - previousAccuracy!;
  late final Map<String, StockCheckKpiComparison> branches = _branches();
  Map<String, StockCheckKpiComparison> _branches() {
    final groups = <String, List<StockCheckKpiItemPair>>{};
    for (final item in items) {
      groups.putIfAbsent(item.branch.trim().toLowerCase(), () => []).add(item);
    }
    return {
      for (final entry in groups.entries)
        entry.value.first.branch.trim(): StockCheckKpiComparison(
          entry.value
              .map((item) => item.previous)
              .whereType<StockCheckTask>()
              .toList(),
          entry.value
              .map((item) => item.current)
              .whereType<StockCheckTask>()
              .toList(),
        ),
    };
  }
}
