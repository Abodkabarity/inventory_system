import 'dart:io';
import 'package:daily_order/core/utils/stock_catalog_export.dart';
import 'package:daily_order/core/utils/stock_register_export.dart';
import 'package:daily_order/domain/entities/stock_catalog.dart';
import 'package:daily_order/domain/entities/stock_expiry.dart';
import 'package:daily_order/domain/entities/stock_management.dart';
import 'package:daily_order/domain/entities/stock_supply_insight.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_management_grid.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_catalog_visuals.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_expiry_grid.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_supply_insight_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'stock_catalog_test.dart' as catalog;

Map<String, dynamic> insightData({bool verified = true}) => {
  'status': verified ? 'back_in_store' : 'history_needed',
  'confidence': verified ? 'verified' : 'unavailable',
  'scope': 'STORE',
  'through': '2026-10-21',
  'stock_day': '2026-10-22',
  'gap_days': 166,
  'at_least': false,
  'returned_at': '2026-10-15',
  'received_qty': 100,
  'current_qty': 95,
  'issues': verified ? [] : ['opening_missing', 'balance_mismatch'],
  'events': [
    {
      'from': '2026-05-02',
      'returned_at': '2026-10-15',
      'days': 166,
      'established': true,
      'mrn_linked': true,
      'received_qty': 100,
    },
  ],
  'monthly': [
    {
      'month': '09/2026',
      'available_days': 0,
      'empty_days': 30,
      'partial_days': 0,
      'sales_qty': 10,
      'prior_year_sales_qty': 300,
    },
    {
      'month': '10/2026',
      'available_days': 6,
      'empty_days': 14,
      'partial_days': 1,
      'sales_qty': 40,
      'prior_year_sales_qty': 290,
    },
  ],
};
StockManagementItem supplyItem({bool verified = true}) => StockManagementItem({
  'item_code': 'RETURN',
  'item_name': 'Returned product',
  'store_stock': 95,
  'supply_insight': insightData(verified: verified),
});

void main() {
  setUpAll(() async {
    final root = Platform.environment['CATALOG_FONT_ROOT'];
    if (root == null) return;
    for (final (family, file) in [
      ('Roboto', 'roboto-regular.ttf'),
      ('MaterialIcons', 'MaterialIcons-Regular.otf'),
    ]) {
      final loader = FontLoader(family)
        ..addFont(
          Future.value(
            ByteData.sublistView(File('$root/$file').readAsBytesSync()),
          ),
        );
      await loader.load();
    }
  });
  test('all exports carry the same verified STORE evidence', () {
    final item = supplyItem();
    final rows = [
      catalogExportRow(StockCatalogItem(item.data)),
      stockRegisterExportRow(item),
      stockExpiryExportRow(StockExpiryAlert({'product_data': item.data})),
    ];
    for (final row in rows) {
      expect(row['STORE review'], 'In STORE · Unavailable in branches');
      expect(row['STORE gap (days)'], 166);
      expect(row['STORE return date'], '2026-10-15');
      expect(row['STORE return received Qty'], 100);
    }
    final unverified = StockSupplyInsight.of(supplyItem(verified: false));
    expect(unverified.gapLabel, '');
    expect(unverified.months, isEmpty);
    expect(unverified.returns, isEmpty);
    expect(unverified.exportFields['STORE gap (days)'], isNull);
    expect(unverified.exportFields['STORE return date'], isNull);
  });
  test('MRN and expiry filters receive searchable supply review labels', () {
    final mrn = StockManagementGridSource([supplyItem()], onOpen: (_) {});
    final near = StockExpiryGridSource(
      alerts: [
        StockExpiryAlert({'product_data': supplyItem().data}),
      ],
      busy: {},
      fading: {},
      onOpen: (_) {},
      onReview: (_) {},
      riskColor: (_) => Colors.orange,
    );
    addTearDown(mrn.dispose);
    addTearDown(near.dispose);
    for (final source in [mrn, near]) {
      expect(
        source.rows.single
            .getCells()
            .singleWhere((c) => c.columnName == 'supply_review')
            .value,
        'In STORE · Unavailable in branches',
      );
    }
  });
  for (final width in [1440.0, 540.0]) {
    testWidgets('STORE evidence and separate monthly sales scopes at $width', (
      tester,
    ) async {
      final boundary = GlobalKey();
      await catalog.app(
        tester,
        SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: StockSupplyInsightPanel(item: supplyItem()),
          ),
        ),
        size: Size(width, 960),
        boundary: boundary,
      );
      expect(find.text('In STORE · Unavailable in branches'), findsOneWidget);
      expect(find.text('166 days'), findsOneWidget);
      expect(
        find.textContaining('empty STORE alone does not prove lost sales'),
        findsOneWidget,
      );
      await tester.tap(find.text('Monthly sales and STORE days'));
      await tester.pumpAndSettle();
      final table = tester.widget<DataTable>(find.byType(DataTable));
      expect(table.rows.length, 2);
      expect(find.text('Sep 2026'), findsOneWidget);
      expect(find.text('Prior-year Qty'), findsOneWidget);
      expect(find.text('Partial days'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await catalog.capture(
        tester,
        boundary,
        'stock_supply_insight_${width.toInt()}',
      );
    });
  }

  test(
    'estimated evidence remains qualified in every export and monthly mark',
    () {
      final data = {
        ...insightData(),
        'confidence': 'inferred',
        'opening_basis': 'assumed_zero',
        'provisional': true,
      };
      final item = StockManagementItem({
        'item_code': 'ASSUMED',
        'supply_insight': data,
      });
      final insight = StockSupplyInsight.of(item);
      expect(insight.verified, false);
      expect(insight.usable, true);
      expect(insight.marksMonth('09/2026'), true);
      expect(insight.marksMonth('09/2025'), false);
      expect(
        insight.monthDescription('09/2026'),
        contains('30 STORE out-of-stock days'),
      );
      for (final row in [
        catalogExportRow(StockCatalogItem(item.data)),
        stockRegisterExportRow(item),
        stockExpiryExportRow(StockExpiryAlert({'product_data': item.data})),
      ]) {
        expect(row['STORE gap (days)'], 166);
        expect(row['STORE history verified'], 'No');
        expect(row['STORE analysis basis'], 'Estimated');
        expect(row['STORE evidence note'], contains('assumed zero'));
      }
      final monthly = catalogMonthlyExportRows(
        StockCatalogItem({
          ...item.data,
          'monthly_sales': [
            {'month': '10/2026', 'total': 4},
          ],
        }),
      );
      final absentSalesMonth = monthly.singleWhere(
        (row) => row['month'] == '09/2026',
      );
      expect(absentSalesMonth['total'], 0);
      expect(absentSalesMonth['STORE empty days'], 30);
      expect(absentSalesMonth['STORE analysis basis'], 'Estimated');
      expect(monthly.first.containsKey('STORE empty days'), false);
      final invalid = StockSupplyInsight({...data, 'status': 'history_needed'});
      expect(invalid.usable, false);
      expect(invalid.months, isEmpty);
      expect(invalid.exportFields['STORE gap (days)'], isNull);
    },
  );
  for (final width in [1440.0, 540.0]) {
    testWidgets('estimated returns and chart outage annotations at $width', (
      tester,
    ) async {
      final boundary = GlobalKey();
      final item = StockCatalogItem({
        'item_code': 'METROLAG',
        'monthly_sales': [
          {'month': '09/2025', 'total': 300},
          {'month': '09/2026', 'total': 10},
          {'month': '10/2026', 'total': 40},
        ],
        'supply_insight': {
          ...insightData(),
          'confidence': 'inferred',
          'opening_basis': 'assumed_zero',
          'provisional': true,
        },
      });
      await catalog.app(
        tester,
        SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                StockSupplyInsightPanel(item: item),
                const SizedBox(height: 16),
                CatalogPanel(
                  title: 'Monthly sales & momentum',
                  child: CatalogMonthlyChart(item: item),
                ),
              ],
            ),
          ),
        ),
        size: Size(width, 1100),
        boundary: boundary,
      );
      expect(find.text('In STORE · Unavailable in branches'), findsOneWidget);
      expect(
        find.textContaining('Estimated • Opening STORE stock is assumed zero'),
        findsOneWidget,
      );
      expect(find.text('Chart history · Estimated'), findsOneWidget);
      final semantics = tester
          .widgetList<Semantics>(find.byType(Semantics))
          .map((w) => w.properties.label ?? '')
          .firstWhere(
            (label) => label.startsWith('Monthly net sales and trailing'),
          );
      expect(semantics, contains('09/2026: 30 STORE out-of-stock days'));
      expect(semantics, isNot(contains('09/2025:')));
      final scroller = find.descendant(
        of: find.byType(CatalogMonthlyChart),
        matching: find.byType(SingleChildScrollView),
      );
      final scrollWidget = tester.widget<SingleChildScrollView>(scroller);
      scrollWidget.controller!.jumpTo(
        scrollWidget.controller!.position.maxScrollExtent,
      );
      await tester.pumpAndSettle();
      final chart = find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString() == '_MonthlyPainter',
      );
      final chartSize = tester.getSize(chart);
      final series = catalogMonthlySeries(item);
      final index = series.indexWhere((r) => r['month'] == '09/2026');
      await tester.ensureVisible(chart);
      scrollWidget.controller!.jumpTo(
        scrollWidget.controller!.position.maxScrollExtent,
      );
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getTopLeft(chart) +
            Offset(
              60 + (chartSize.width - 76) / series.length * (index + .5),
              100,
            ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('30 STORE out-of-stock days · 0 stocked days'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await catalog.capture(
        tester,
        boundary,
        'stock_supply_outage_chart_${width.toInt()}',
      );
    });
  }

  Map<String, dynamic> learnedInsight() {
    final period = {
      'from': '2026-01-02',
      'through': '2026-10-21',
      'returned_at': '2026-10-22',
      'days': 293,
      'months': 9,
      'remaining_days': 20,
      'at_least': true,
      'received_qty': 232,
      'small_arrivals': 7,
      'small_arrival_qty': 9,
    };
    return {
      ...insightData(),
      'confidence': 'inferred',
      'opening_basis': 'assumed_zero',
      'provisional': true,
      'current_qty': 232,
      'through': '2026-10-22',
      'effective_supply': {
        'status': 'supply_restored',
        'confidence': 'estimated',
        'latest_period': period,
        'periods': [period],
        'model': {
          'status': 'ready',
          'daily_qty': .558065,
          'recovery_qty': 8,
          'recovery_cover_days': 14,
          'months': 12,
          'validation_months': 7,
          'holdout_months': 2,
          'holdout_mae_qty': 7.171,
          'validation_mae_qty': 22.951,
        },
      },
      'monthly': [
        for (var m = 1; m <= 10; m++)
          {
            'month': '${m.toString().padLeft(2, '0')}/2026',
            'limited_days': m == 1
                ? 30
                : m == 2
                ? 28
                : m == 10
                ? 21
                : DateTime(2026, m + 1, 0).day,
            'empty_days': m == 2 ? 18 : 20,
            'available_days': m == 2 ? 4 : 0,
            'partial_days': m == 2 ? 6 : 0,
            'sales_qty': m == 2 ? 6 : 0,
          },
      ],
    };
  }

  test('learned interruption is distinct from raw zero stock in all exports', () {
    final item = StockCatalogItem({
      'item_code': 'METROLAG',
      'supply_insight': learnedInsight(),
      'monthly_sales': [
        {'month': '10/2026', 'total': 0},
      ],
    });
    final supply = StockSupplyInsight.of(item);
    expect(supply.label, 'Stock available · Unavailable in branches');
    expect(supply.displayGapLabel, 'At least 9 months 20 days');
    expect(supply.gapLabel, '166 days');
    expect(supply.marksMonth('01/2026'), true);
    expect(supply.marksMonth('12/2025'), false);
    expect(
      supply.monthDescription('02/2026'),
      contains('28 days of insufficient STORE supply'),
    );
    for (final row in [
      catalogExportRow(item),
      stockRegisterExportRow(item),
      stockExpiryExportRow(StockExpiryAlert({'product_data': item.data})),
    ]) {
      expect(row['STORE effective gap days'], 293);
      expect(row['STORE small arrival Qty during gap'], 9);
      expect(row['STORE recovery Qty threshold'], 8);
      expect(row['STORE effective supply basis'], startsWith('Estimated'));
    }
    final rows = catalogMonthlyExportRows(item);
    final feb = rows.singleWhere((r) => r['month'] == '02/2026');
    expect(feb['STORE empty days'], 18);
    expect(feb['STORE supply interruption days'], 28);
    final invalid = StockSupplyInsight({
      ...learnedInsight(),
      'confidence': 'unavailable',
      'status': 'history_needed',
    });
    expect(invalid.supplyPeriods, isEmpty);
    expect(invalid.exportFields['STORE effective gap days'], isNull);
    // A large old period and a new ongoing short period must retain separate dates.
    final ongoing = StockSupplyInsight({
      ...learnedInsight(),
      'current_qty': 2,
      'effective_supply': {
        'status': 'limited_supply',
        'daily_qty': .558065,
        'latest_period': {
          'from': '2026-10-20',
          'days': 3,
          'months': 0,
          'remaining_days': 3,
          'returned_at': null,
        },
        'periods': [],
      },
    });
    expect(ongoing.displayGapLabel, '3 days');
    expect(ongoing.label, 'Limited stock · Unavailable in branches');
  });
  for (final width in [1440.0, 540.0]) {
    testWidgets(
      'continuous learned supply span and readable context at $width',
      (tester) async {
        final boundary = GlobalKey();
        final item = StockCatalogItem({
          'item_code': 'METROLAG',
          'supply_insight': learnedInsight(),
          'monthly_sales': [
            {'month': '01/2025', 'total': 151},
            {'month': '08/2025', 'total': 60},
            {'month': '01/2026', 'total': 12},
            {'month': '02/2026', 'total': 6},
            {'month': '10/2026', 'total': 0},
          ],
        });
        await catalog.app(
          tester,
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  StockSupplyInsightPanel(item: item),
                  const SizedBox(height: 16),
                  CatalogPanel(
                    title: 'Monthly sales & momentum',
                    child: CatalogMonthlyChart(item: item),
                  ),
                ],
              ),
            ),
          ),
          size: Size(width, 1200),
          boundary: boundary,
        );
        expect(
          find.text('Stock available · Unavailable in branches'),
          findsOneWidget,
        );
        expect(find.text('At least 9 months 20 days'), findsOneWidget);
        expect(find.text('SUPPLY INTERRUPTION'), findsOneWidget);
        expect(
          find.textContaining('Meaningful recovery ≥ 8 Qty'),
          findsOneWidget,
        );
        expect(find.textContaining('7 small arrivals / 9 Qty'), findsOneWidget);
        expect(find.text('Chart history · Estimated'), findsOneWidget);
        expect(find.text('STORE out of stock · Estimated'), findsNothing);
        final scroller = find.descendant(
          of: find.byType(CatalogMonthlyChart),
          matching: find.byType(SingleChildScrollView),
        );
        final scrollWidget = tester.widget<SingleChildScrollView>(scroller);
        scrollWidget.controller!.jumpTo(
          scrollWidget.controller!.position.maxScrollExtent,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await catalog.capture(
          tester,
          boundary,
          'stock_continuous_supply_${width.toInt()}',
        );
        await tester.tap(find.text('Monthly sales and STORE days'));
        await tester.pumpAndSettle();
        expect(find.text('Supply interruption days'), findsOneWidget);
        final table = tester.widget<DataTable>(find.byType(DataTable));
        expect(table.rows[1].cells.length, 7);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'unverified reconstruction never displays an asserted outage or monthly totals',
    (tester) async {
      await catalog.app(
        tester,
        StockSupplyInsightPanel(item: supplyItem(verified: false)),
      );
      expect(find.text('In STORE · Unavailable in branches'), findsOneWidget);
      expect(
        find.textContaining('opening STORE balance is missing'),
        findsOneWidget,
      );
      expect(find.text('166 days'), findsNothing);
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('RECEIVED QTY'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
