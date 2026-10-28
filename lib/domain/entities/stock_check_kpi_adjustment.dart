/// Signed source quantities. KPI difference tolerance never alters adjustments.
class StockCheckKpiAdjustment {
  final num quantity;
  final int movementCount;
  final bool complete;

  const StockCheckKpiAdjustment({
    required this.quantity,
    required this.movementCount,
    required this.complete,
  });

  String get quantityLabel =>
      quantity.toString().replaceFirst(RegExp(r'\.0+$'), '');
  String get countLabel =>
      '$movementCount adjustment${movementCount == 1 ? '' : 's'}';

  String get label => movementCount == 0 ? '' : '$quantityLabel ($countLabel)';
  Object get exportValue => label;
}

class StockCheckKpiAdjustments {
  final DateTime fromDate;
  final DateTime throughDate;
  final String snapshot;
  final Map<String, StockCheckKpiAdjustment> values;

  StockCheckKpiAdjustments({
    required this.fromDate,
    required this.throughDate,
    required this.snapshot,
    required Map<String, StockCheckKpiAdjustment> values,
  }) : values = Map.unmodifiable(values);

  static String key(String branch, String code) =>
      '${branch.trim().toLowerCase()}\u0000${code.trim().toLowerCase()}';
  StockCheckKpiAdjustment? forItem(String branch, String code) =>
      values[key(branch, code)];
  String get period =>
      '${fromDate.toIso8601String().split('T').first} → '
      '${throughDate.toIso8601String().split('T').first}';
}
