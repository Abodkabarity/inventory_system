/// A complete, single-revision receipt history, independent of latest-day KPIs.
class StockMrnReceiptHistory {
  final List<Map<String, dynamic>> lines;
  final int mrnCount, dayCount;
  final double receivedQty;
  final double bonus;
  final String from, through;

  const StockMrnReceiptHistory({
    required this.lines,
    required this.mrnCount,
    required this.dayCount,
    required this.receivedQty,
    this.bonus = 0,
    required this.from,
    required this.through,
  });
}
