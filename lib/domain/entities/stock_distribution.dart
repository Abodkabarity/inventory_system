import '../../core/utils/stock_item_added_date.dart';
import 'stock_management.dart';

class StockDistributionRules {
  final int maxAgeDays, maxCoveredBranches;
  final double minStoreStock;
  const StockDistributionRules({
    this.maxAgeDays = 30,
    this.minStoreStock = 50,
    this.maxCoveredBranches = 6,
  });

  StockDistribution evaluate(StockManagementItem item, {DateTime? today}) {
    final now = today ?? DateTime.now().toUtc().add(const Duration(hours: 4));
    final date = DateTime.utc(now.year, now.month, now.day);
    final created = stockItemAddedDate(item.data['added_date_time']);
    final age = created == null
        ? null
        : date
              .difference(
                DateTime.utc(created.year, created.month, created.day),
              )
              .inDays;
    final facts = stockMap(item.data['distribution']);
    final receipt = stockMap(item.data['store_receipt']);
    final firstReceived = stockItemAddedDate(receipt['first_date']);
    final lastReceived = stockItemAddedDate(receipt['last_date']);
    final receivedAge = firstReceived == null
        ? null
        : date
              .difference(
                DateTime.utc(
                  firstReceived.year,
                  firstReceived.month,
                  firstReceived.day,
                ),
              )
              .inDays;
    final receivedAfterCreation =
        receipt['checked'] == true &&
        created != null &&
        firstReceived != null &&
        !firstReceived.isBefore(created) &&
        receivedAge != null &&
        receivedAge >= 0 &&
        stockNumber(receipt['received_qty']) > 0;
    final run = DateTime.tryParse('${facts['run_date'] ?? ''}');
    final runAge = run == null
        ? null
        : date.difference(DateTime.utc(run.year, run.month, run.day)).inDays;
    final fresh = runAge != null && runAge >= 0 && runAge <= 1;
    final known = facts['complete'] == true && fresh;
    final orderDataAvailable =
        fresh && (known || stockNumber(facts['observed']) > 0);
    final isNew = age != null && age >= 0 && age <= maxAgeDays;
    final eligible = stockNumber(facts['eligible']).toInt();
    final covered = stockNumber(facts['covered']).toInt();
    final availableStore =
        (item.number('store_stock') -
                stockNumber(facts['final_qty']).clamp(0, double.infinity))
            .clamp(0, double.infinity)
            .toDouble();
    final minimumUnit = item.number('min_order_unit') > 0
        ? item.number('min_order_unit')
        : 1;
    return StockDistribution(
      ageDays: age,
      isNew: isNew,
      known: known,
      orderDataAvailable: orderDataAvailable,
      reorderQuantity: stockNumber(facts['reorder_qty']),
      finalQuantity: stockNumber(facts['final_qty']),
      eligible: eligible,
      stocked: stockNumber(facts['stocked']).toInt(),
      reorder: stockNumber(facts['reorder']).toInt(),
      finalOrders: stockNumber(facts['final']).toInt(),
      covered: covered,
      availableStore: availableStore,
      receiptKnown: receipt['checked'] == true,
      receivedAfterCreation: receivedAfterCreation,
      firstReceivedDate: firstReceived,
      lastReceivedDate: lastReceived,
      daysInStore: receivedAfterCreation ? receivedAge : null,
      needsDistribution:
          isNew &&
          known &&
          item.number('store_stock') >= minStoreStock &&
          item.number('store_stock') > 0 &&
          availableStore >= minimumUnit &&
          covered <= maxCoveredBranches &&
          eligible > covered,
    );
  }
}

class StockDistribution {
  final int? ageDays;
  final bool isNew, known, needsDistribution;
  final bool orderDataAvailable;
  final double reorderQuantity, finalQuantity;
  final int eligible, stocked, reorder, finalOrders, covered;
  final double availableStore;
  final bool receiptKnown, receivedAfterCreation;
  final DateTime? firstReceivedDate, lastReceivedDate;
  final int? daysInStore;
  const StockDistribution({
    required this.ageDays,
    required this.isNew,
    required this.known,
    required this.orderDataAvailable,
    required this.reorderQuantity,
    required this.finalQuantity,
    required this.needsDistribution,
    required this.eligible,
    required this.stocked,
    required this.reorder,
    required this.finalOrders,
    required this.covered,
    required this.availableStore,
    required this.receiptKnown,
    required this.receivedAfterCreation,
    required this.firstReceivedDate,
    required this.lastReceivedDate,
    required this.daysInStore,
  });
  int get uncovered => (eligible - covered).clamp(0, eligible);
  String get label => needsDistribution
      ? 'New · Needs distribution'
      : !known
      ? 'Order data unavailable'
      : covered == eligible && eligible > 0
      ? 'All branches covered'
      : isNew
      ? 'New product'
      : 'Established product';
  String get coverage => known ? '$covered / $eligible branches' : '—';
}
