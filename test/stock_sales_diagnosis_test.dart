import 'package:daily_order/domain/entities/stock_sales_diagnosis.dart';
import 'package:daily_order/domain/entities/stock_daily_sales.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_sales_diagnosis_panel.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_catalog_visuals.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'dart:async';

Map<String, dynamic> branch({
  String name = 'Alpha',
  double stock = 100,
  bool audited = true,
  double lastSales = 1,
  bool outage = false,
  bool weekdayPattern = false,
}) => {
  'branch_name': name,
  'branch_group': 'APG',
  'current_qty': stock,
  'current_rows': 1,
  'opening_qty': 10000,
  'reconciled': audited,
  'movements': [
    if (outage) {'day': '2026-10-19', 'net': -10000},
  ],
  'sales_days': [
    for (
      var d = DateTime(2026, 9, 8);
      !d.isAfter(DateTime(2026, 10, 22));
      d = d.add(const Duration(days: 1))
    )
      {
        'day': d.toIso8601String().substring(0, 10),
        'qty': d.day >= 20 && d.month == 10
            ? lastSales
            : weekdayPattern
            ? (d.weekday >= 6 ? 0 : 10)
            : 10,
        'gross_qty': d.day >= 20 && d.month == 10
            ? lastSales
            : weekdayPattern
            ? (d.weekday >= 6 ? 0 : 10)
            : 10,
      },
  ],
};
Map<String, dynamic> evidence(
  List<Map<String, dynamic>> rows, {
  double store = 0,
}) => {
  'status': 'ready',
  'through': '2026-10-22',
  'stock_day': '2026-10-22',
  'sales_day': '2026-10-22',
  'branches': [
    ...rows,
    {'branch_name': 'STORE', 'current_qty': store},
  ],
  'latest_mrn': {'day': '2026-10-03', 'qty': 6},
};
void main() {
  testWidgets(
    'analysis starts collapsed, loads on opening and reuses its result',
    (tester) async {
      var loads = 0;
      final pending = Completer<StockSalesDiagnosis>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StockSalesDiagnosisPanel(
                code: 'A',
                load: (_) {
                  loads++;
                  return pending.future;
                },
              ),
            ),
          ),
        ),
      );
      expect(loads, 0);
      expect(find.byType(CatalogMetric), findsNothing);
      await tester.tap(find.text('Sales & stock check'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(loads, 1);
      pending.complete(StockSalesDiagnosis.fromMap(evidence([branch()])));
      await tester.pumpAndSettle();
      expect(find.byType(CatalogMetric), findsNWidgets(4));
      await tester.tap(find.text('Sales & stock check'));
      await tester.pumpAndSettle();
      expect(find.byType(CatalogMetric), findsNothing);
      await tester.tap(find.text('Sales & stock check'));
      await tester.pumpAndSettle();
      expect(loads, 1);
      expect(find.byType(CatalogMetric), findsNWidgets(4));
    },
  );
  test('new receipt metadata never silently changes older stock coverage', () {
    final raw = evidence([branch()])
      ..['latest_mrn'] = {'day': '2026-10-23', 'qty': 1000};
    final d = StockSalesDiagnosis.fromMap(raw);
    expect(d.receiptAfterCutoff, true);
    expect(d.physicalStock, 100);
    expect(d.action, contains('newest MRN'));
  });
  testWidgets('missing MRN is shown as unknown rather than zero Qty', (
    tester,
  ) async {
    final raw = evidence([branch()])..remove('latest_mrn');
    final d = StockSalesDiagnosis.fromMap(raw);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StockSalesDiagnosisPanel(code: 'A', load: (_) async => d),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sales & stock check'));
    await tester.pumpAndSettle();
    final metric = tester
        .widgetList<CatalogMetric>(find.byType(CatalogMetric))
        .firstWhere((m) => m.title == 'LAST RECEIVED QTY');
    expect(metric.value, '—');
    expect(d.receiptCover, isNull);
    expect(d.receiptAssessment, contains('No approved MRN'));
  });
  for (final width in [1440.0, 540.0]) {
    testWidgets(
      'analysis explains evidence and refreshes branch 71 labels at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final d = StockSalesDiagnosis.fromMap(
          evidence([branch(name: 'Beta', stock: 0, outage: true)], store: 200),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: StockSalesDiagnosisPanel(
                    code: 'A',
                    load: (_) async => d,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Sales & stock check'));
        await tester.pumpAndSettle();
        expect(find.text('Send stock to branches'), findsOneWidget);
        await tester.ensureVisible(find.text('What did we check?'));
        await tester.tap(find.text('What did we check?'));
        await tester.pumpAndSettle();
        StoreBranchIdentityRegistry.groups.value = {'BETA': '71'};
        await tester.pump();
        expect(find.text('71 Beta'), findsOneWidget);
        expect(tester.takeException(), isNull);
        StoreBranchIdentityRegistry.groups.value = {};
      },
    );
  }
  test('stocked-day learner separates demand slowing from a branch outage', () {
    final demand = StockSalesDiagnosis.fromMap(evidence([branch()]));
    expect(demand.status, 'demand_slowing');
    expect(demand.expected, 30);
    expect(demand.actual, 3);
    expect(demand.auditedShare, 1);
    final supply = StockSalesDiagnosis.fromMap(
      evidence([branch(stock: 0, outage: true)]),
    );
    expect(supply.status, 'availability_decline');
    expect(supply.recentAvailability, 0);
  });
  test(
    'stock in STORE with empty selling branches prioritizes distribution',
    () {
      final d = StockSalesDiagnosis.fromMap(
        evidence([branch(stock: 0, outage: true)], store: 200),
      );
      expect(d.status, 'distribution_delay');
      expect(d.networkCover, 20);
      expect(d.receiptCover, .6);
      expect(d.latestMrn['qty'], 6);
    },
  );
  test('empty STORE after distribution does not imply network stockout', () {
    final d = StockSalesDiagnosis.fromMap(
      evidence([branch(stock: 100, lastSales: 10)]),
    );
    expect(d.status, 'distributed');
    expect(d.networkCover, 10);
  });
  test(
    'current shortage can be assessed without inventing historical gaps',
    () {
      final d = StockSalesDiagnosis.fromMap(
        evidence([branch(stock: 1, audited: false)]),
      );
      expect(d.status, 'limited_supply');
      expect(d.auditedShare, 0);
      expect(d.branches.single.availabilityTrained, false);
    },
  );
  test('unreconciled stock never establishes weakening demand', () {
    final d = StockSalesDiagnosis.fromMap(evidence([branch(audited: false)]));
    expect(d.status, 'sales_declining');
    expect(d.auditedShare, 0);
  });
  test('missing stock is not silently counted as zero', () {
    final b = branch()
      ..['current_rows'] = 0
      ..['current_qty'] = null;
    final d = StockSalesDiagnosis.fromMap(evidence([b]));
    expect(d.status, 'review_availability');
    expect(d.emptyShare, 0);
  });
  test('a high selling branch weighs more than many low selling branches', () {
    final big = branch(stock: 0, outage: true);
    final small = branch(name: 'Beta', stock: 100, lastSales: 1);
    for (final day in small['sales_days'] as List) {
      day['qty'] = 1;
      day['gross_qty'] = 1;
    }
    final d = StockSalesDiagnosis.fromMap(evidence([big, small]));
    expect(d.shortShare, greaterThan(.9));
    expect(d.status, 'availability_decline');
  });
  test(
    'last three target days never influence learned demand or selection',
    () {
      final a = StockSalesDiagnosis.fromMap(evidence([branch(lastSales: 1)]));
      final b = StockSalesDiagnosis.fromMap(evidence([branch(lastSales: 500)]));
      expect(a.expected, b.expected);
      expect(a.branches.single.method, b.branches.single.method);
      expect(a.error, b.error);
    },
  );
  test('negative history disables stocked-day cause attribution', () {
    final b = branch()..['opening_qty'] = -1;
    final d = StockSalesDiagnosis.fromMap(evidence([b]));
    expect(d.branches.single.audited, false);
    expect(d.status, 'sales_declining');
  });
  test('learner selects weekday behavior on chronological validation', () {
    final d = StockSalesDiagnosis.fromMap(
      evidence([branch(weekdayPattern: true)]),
    );
    expect(d.branches.single.method, 'weekday');
    expect(d.branches.single.validationDays, 7);
    expect(d.branches.single.trainingDays, 42);
  });
  test('stale sales and current stock are not treated as contemporaneous', () {
    final raw = evidence([branch()])..['stock_day'] = '2026-10-23';
    expect(StockSalesDiagnosis.fromMap(raw).status, 'review_availability');
  });
  test('uneven branch coverage is not declared healthy by a network total', () {
    final d = StockSalesDiagnosis.fromMap(
      evidence([
        branch(name: 'Alpha', stock: 0, lastSales: 10),
        branch(name: 'Beta', stock: 1000, lastSales: 10),
      ]),
    );
    expect(d.networkCover, greaterThan(30));
    expect(d.status, 'branch_shortage');
  });
  test('returns do not become an assertion of weak demand', () {
    final b = branch(lastSales: -3);
    for (final day in b['sales_days'] as List) {
      if ('${day['day']}'.compareTo('2026-10-20') >= 0) {
        day['gross_qty'] = 10;
        day['return_qty'] = 13;
      }
    }
    final d = StockSalesDiagnosis.fromMap(evidence([b]));
    expect(d.status, 'returns_impact');
  });
  test(
    'unposted MRN is not added to physical stock or declared distributed',
    () {
      final raw = evidence([branch(stock: 10)], store: 0)
        ..['latest_mrn_movement_qty'] = 0;
      final d = StockSalesDiagnosis.fromMap(raw);
      expect(d.receiptAwaitingMovements, true);
      expect(d.physicalStock, 10);
      expect(d.action, contains('Confirm the latest receipt'));
    },
  );
  test(
    'channel comparison preserves the five channels and rejects another cutoff',
    () {
      final d = StockSalesDiagnosis.fromMap(evidence([branch()]));
      final days = [
        for (
          var date = DateTime(2026, 9, 8);
          !date.isAfter(DateTime(2026, 10, 22));
          date = date.add(const Duration(days: 1))
        )
          {
            'date': date.toIso8601String().substring(0, 10),
            for (final channel in StockSalesChannel.values) channel.key: 1,
          },
      ];
      final raw = <String, dynamic>{
        'daily_sales_45d_available': true,
        'daily_sales_45d': days,
        'recent_sales': 225,
        'meta': {'demand_from': '2026-09-08', 'demand_through': '2026-10-22'},
      };
      final mix = StockDailySalesMix.fromMap(raw);
      final channels = d.channelChanges(mix);
      expect(channels.length, 5);
      expect(channels.every((r) => r['last_3_daily_qty'] == 1), true);
      final stale = StockSalesDiagnosis.fromMap({
        ...evidence([branch()]),
        'through': '2026-10-21',
      });
      expect(stale.channelChanges(mix), isEmpty);
    },
  );
}
