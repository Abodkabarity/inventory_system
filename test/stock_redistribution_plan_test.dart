import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:daily_order/domain/entities/stock_redistribution_plan.dart';
import 'package:daily_order/domain/entities/stock_sales_diagnosis.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_redistribution_panel.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/core/utils/stock_redistribution_export.dart';
import 'package:daily_order/core/utils/stock_excel_report.dart';
import 'stock_sales_diagnosis_test.dart' as sample;

Map<String, dynamic> order(
  String name,
  double stock,
  double extra,
  double need, {
  double unit = 1,
  double sales90 = 0,
  double pending = 0,
  double finalQty = 0,
}) => {
  'branch': name,
  'branch_key': name.toLowerCase(),
  'run_date': '2026-10-23',
  'branch_stock': stock,
  'extra_qty_more_than_month': extra,
  'demand_for_30_days': 0,
  'reorder_max': 0,
  'reorder_qty': '$need',
  'final_reorder_qty_store_stock_gt_0': '$finalQty',
  'pending_stock_received': pending,
  'assortment_qty_base_stock': 0,
  'item_minimum_order_unit': unit,
  'total_sales_last_90_days': sales90,
};
Map<String, dynamic> fixture() => {
  ...sample.evidence([
    sample.branch(name: 'Donor', stock: 12, lastSales: 0),
    sample.branch(name: 'Selling', stock: 0, lastSales: 10, outage: true),
  ]),
  'daily_order_day': '2026-10-23',
  'daily_order_rows': [order('Donor', 12, 10, 0), order('Selling', 0, 0, 8)],
};
void makeIdle(Map<String, dynamic> raw) {
  for (final b in raw['branches'] as List) {
    b['branch_group'] = 'APG';
    if (b['branch_name'] == 'Donor') {
      for (final day in b['sales_days'] as List) {
        day['qty'] = 0;
        day['gross_qty'] = 0;
      }
    }
  }
}

StockRedistributionPlan plan(Map<String, dynamic> raw) {
  makeIdle(raw);
  return StockRedistributionPlan.fromDiagnosis(
    StockSalesDiagnosis.fromMap(raw),
  );
}

void main() {
  test(
    'Excel worker rows decorate authoritative group 71 without changing quantities',
    () {
      final raw = fixture();
      makeIdle(raw);
      final p = StockRedistributionPlan.fromDiagnosis(
        StockSalesDiagnosis.fromMap(raw),
      );
      StoreBranchIdentityRegistry.groups.value = {
        'DONOR': '71',
        'SELLING': 'APG',
      };
      final rows = stockRedistributionExportRows(p);
      expect(rows.single['from_branch'], '71 Donor');
      expect(rows.single['to_branch'], 'Selling');
      final report = StockExcelReport(rows, 'sales_analysis');
      expect(
        report.values.single[report.keys.indexOf('from_branch')],
        '71 Donor',
      );
      expect(rows.single['Suggested transfer Qty'], p.suggestedQty);
      StoreBranchIdentityRegistry.groups.value = {};
    },
  );
  test(
    'moves only declared extra and protects the donor; receiver remains capped',
    () {
      final p = plan(fixture());
      expect(p.transfers.length, 1);
      expect(p.transfers.single.from.branch, 'Donor');
      expect(p.transfers.single.to.branch, 'Selling');
      expect(p.suggestedQty, 10);
      expect(p.transfers.single.reason, contains('90 days'));
      expect(p.suggestedQty, lessThanOrEqualTo(p.safeExtra));
      expect(p.suggestedQty, lessThanOrEqualTo(p.totalNeed));
    },
  );
  test(
    '90-day demand protects idle recent sales from being called surplus',
    () {
      final raw = fixture();
      (raw['daily_order_rows'] as List).first['total_sales_last_90_days'] = 30;
      final p = plan(raw);
      expect(p.donors.single.retained, 10);
      expect(p.safeExtra, 2);
      expect(p.suggestedQty, 2);
    },
  );
  test(
    'pending and final allocation reserve receiver need without adding physical stock',
    () {
      final raw = fixture();
      final row = (raw['daily_order_rows'] as List).last;
      row['pending_stock_received'] = 60;
      row['final_reorder_qty_store_stock_gt_0'] = '10';
      final p = plan(raw);
      expect(p.suggestedQty, 0);
      expect(StockSalesDiagnosis.fromMap(raw).physicalStock, 12);
    },
  );
  test(
    'mismatched balances, stale runs and ambiguous branch rows cannot supply a plan',
    () {
      final raw = fixture();
      (raw['daily_order_rows'] as List).first['branch_stock'] = 99;
      expect(plan(raw).suggestedQty, 0);
      final stale = fixture()..['daily_order_day'] = '2026-10-20';
      expect(plan(stale).fresh, false);
      final duplicated = fixture();
      (duplicated['daily_order_rows'] as List).add(order('DONOR', 12, 10, 0));
      expect(plan(duplicated).suggestedQty, 0);
    },
  );
  test(
    'non formulary and different inventory groups are not silently allocated',
    () {
      final raw = fixture();
      (raw['daily_order_rows'] as List).last['reorder_qty'] = 'NON FORMULARY';
      expect(plan(raw).suggestedQty, 0);
      final groups = fixture();
      makeIdle(groups);
      (groups['branches'] as List).first['branch_group'] = '71';
      expect(
        StockRedistributionPlan.fromDiagnosis(
          StockSalesDiagnosis.fromMap(groups),
        ).suggestedQty,
        0,
      );
    },
  );
  test('each donor extra is spent at most once across receivers', () {
    final raw = fixture();
    (raw['branches'] as List).add(
      sample.branch(name: 'Second', stock: 0, lastSales: 10, outage: true),
    );
    (raw['daily_order_rows'] as List).add(order('Second', 0, 0, 30));
    final p = plan(raw);
    expect(p.suggestedQty, 10);
    final moved = p.transfers.fold<double>(0, (s, t) => s + t.qty);
    expect(moved, 10);
    expect(p.unmetNeed, greaterThan(0));
  });
  test(
    'order units are respected and unknown 90-day sales do not free all stock',
    () {
      final raw = fixture();
      for (final row in raw['daily_order_rows'] as List) {
        row['item_minimum_order_unit'] = 3;
      }
      final p = plan(raw);
      expect(p.suggestedQty, 9);
      final unknown = fixture();
      (unknown['daily_order_rows'] as List).first['total_sales_last_90_days'] =
          null;
      expect(plan(unknown).suggestedQty, 0);
    },
  );
  for (final width in [1440.0, 540.0]) {
    testWidgets('transfer table and authoritative 71 labels fit at $width', (
      tester,
    ) async {
      final raw = fixture();
      makeIdle(raw);
      for (final b in raw['branches'] as List) {
        b['branch_group'] = '71';
      }
      final p = StockRedistributionPlan.fromDiagnosis(
        StockSalesDiagnosis.fromMap(raw),
      );
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StockRedistributionPanel(plan: p),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      StoreBranchIdentityRegistry.groups.value = {
        'DONOR': '71',
        'SELLING': '71',
      };
      await tester.pump();
      expect(find.text('71 Donor'), findsWidgets);
      expect(find.text('71 Selling'), findsWidgets);
      expect(tester.takeException(), isNull);
      StoreBranchIdentityRegistry.groups.value = {};
    });
  }
}
