import 'package:daily_order/data/datasources/remote/availability_kpi_remote_ds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('item availability is capped stock divided by weekly need', () {
    final item = AvailabilityKpiItem.fromMasterMap(
      _masterRow(itemCode: 'A', weeklyNeed: 5),
      branchStock: 4,
    );

    expect(item.availabilityRate, 80);
    expect(item.stockShortage, 1);
    expect(item.recentSalesValue, 200);
    expect(item.retail, 10);
    expect(item.sellingMonthNumbers, [1, 2, 4, 5, 6]);
  });

  test('a shortage of a quarter unit or less is treated as fully covered', () {
    final item = AvailabilityKpiItem.fromMasterMap(
      _masterRow(itemCode: 'A', weeklyNeed: 1.15),
      branchStock: 1,
    );

    expect(item.weeklyNeed, 1);
    expect(item.stockShortage, 0);
    expect(item.availabilityRate, 100);
  });

  test('branch availability is the simple average of item coverage', () {
    final items = [
      AvailabilityKpiItem.fromMasterMap(
        _masterRow(itemCode: 'A', weeklyNeed: 10),
        branchStock: 5,
      ),
      AvailabilityKpiItem.fromMasterMap(
        _masterRow(itemCode: 'B', weeklyNeed: 1),
        branchStock: 1,
      ),
    ];

    final summary = AvailabilityBranchSummary.fromItems('Branch', items);

    expect(summary.availabilityRate, 75);
    expect(summary.stockShortage, 5);
    expect(summary.fullyAvailableItems, 1);
  });

  test('configured purchase status overrides zero stock to full coverage', () {
    final item = AvailabilityKpiItem.fromMasterMap(
      _masterRow(itemCode: 'A', weeklyNeed: 5),
      branchStock: 0,
      purchaseStatusId: 7,
      purchaseStatusName: 'Test Status',
    );

    expect(item.statusName, 'Test Status');
    expect(item.isStatusCovered, isTrue);
    expect(item.availabilityRate, 100);
    expect(item.stockShortage, 0);

    final summary = AvailabilityBranchSummary.fromItems('Branch', [item]);
    expect(summary.availabilityRate, 100);
    expect(summary.fullyAvailableItems, 1);
    expect(summary.shortageItems, 0);
  });

  test('other purchase statuses do not override calculated coverage', () {
    final item = AvailabilityKpiItem.fromMasterMap(
      _masterRow(itemCode: 'A', weeklyNeed: 5),
      branchStock: 0,
      purchaseStatusId: 3,
      purchaseStatusName: 'Other Status',
    );

    expect(item.statusName, 'Other Status');
    expect(item.isStatusCovered, isFalse);
    expect(item.availabilityRate, 0);
    expect(item.stockShortage, 5);
  });

  test('extra quantity is exposed only for items below full coverage', () {
    final shortage = AvailabilityKpiItem.fromMasterMap(
      _masterRow(itemCode: 'A', weeklyNeed: 5),
      branchStock: 2,
      extraQtyMoreThanMonth: 7,
    );
    final covered = AvailabilityKpiItem.fromMasterMap(
      _masterRow(itemCode: 'B', weeklyNeed: 5),
      branchStock: 5,
      extraQtyMoreThanMonth: 9,
    );

    expect(shortage.availabilityRate, 40);
    expect(shortage.extraQtyMoreThanMonth, 7);
    expect(covered.availabilityRate, 100);
    expect(covered.extraQtyMoreThanMonth, 0);
  });

  test('allocation preview changes only the displayed branch rate', () {
    final current = AvailabilityBranchSummary(
      branchName: 'Branch',
      masterItems: 10,
      fullyAvailableItems: 8,
      shortageItems: 2,
      paretoItems: 6,
      consistentItems: 5,
      weeklyNeed: 40,
      branchStock: 35,
      coveredWeeklyNeed: 35,
      stockShortage: 5,
      availabilityRate: 80,
    );

    final projected = current.withAvailabilityRate(94.5);

    expect(current.availabilityRate, 80);
    expect(projected.availabilityRate, 94.5);
    expect(projected.branchStock, current.branchStock);
    expect(projected.masterItems, current.masterItems);
  });

  test('allocation impact reads projected branch totals', () {
    final impact = AvailabilityAllocationImpact.fromMap({
      'branch_name': 'AL AIN MAIN',
      'current_rate': 82.1,
      'projected_rate': 96.4,
      'rate_change': 14.3,
      'incoming_qty': 26,
      'outgoing_qty': 3,
    });

    expect(impact.branchName, 'AL AIN MAIN');
    expect(impact.projectedRate, 96.4);
    expect(impact.incomingQty, 26);
    expect(impact.outgoingQty, 3);
  });

  test('explicit retail stays correct when demand replaces sales units', () {
    final item = AvailabilityKpiItem.fromMasterMap(
      {..._masterRow(itemCode: 'A', weeklyNeed: 7), 'recent_sales': 30},
      branchStock: 7,
      retailPrice: 12.5,
    );

    expect(item.recentSales, 30);
    expect(item.retail, 12.5);
    expect(item.weeklyNeed, 7);
  });

  test('branch rates within 0.2 below 97 are raised to 97', () {
    expect(AvailabilityBranchSummary.normalizeRate(96.8), 97);
    expect(AvailabilityBranchSummary.normalizeRate(96.9), 97);
    expect(AvailabilityBranchSummary.normalizeRate(96.799), 96.799);
    expect(AvailabilityBranchSummary.normalizeRate(97), 97);
    expect(AvailabilityBranchSummary.normalizeRate(97.1), 97.1);
  });

  test('item keeps branch decrease note demand and calculated store stock', () {
    final item = AvailabilityKpiItem.fromMasterMap(
      _masterRow(itemCode: 'A', weeklyNeed: 7),
      branchStock: 5,
      storeStock: 18,
      decreaseDemand30Days: 30,
    );

    expect(item.recentSales, 20);
    expect(item.decreaseDemand30Days, 30);
    expect(item.storeStock, 18);
    expect(item.weeklyNeed, 7);
  });
}

Map<String, dynamic> _masterRow({
  required String itemCode,
  required num weeklyNeed,
}) {
  return {
    'branch_name': 'Branch',
    'item_code': itemCode,
    'item_name': 'Item $itemCode',
    'master_source': 'pareto|1, 2, 4, 5, 6',
    'in_pareto': true,
    'in_consistent': false,
    'recent_sales': 20,
    'branch_recent_sales': 1000,
    'recent_sales_share': .2,
    'cumulative_sales_share': .6,
    'total_sales': 40,
    'selling_months': 4,
    'total_months': 5,
    'month_consistency': .8,
    'recent_selling_months': 4,
    'weekly_need': weeklyNeed,
    'analysis_start': '2026-01-01',
    'recent_start': '2026-04-01',
    'as_of_date': '2026-07-16',
  };
}
