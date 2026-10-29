import 'dart:io';
import 'package:daily_order/core/utils/stock_catalog_export.dart';
import 'package:daily_order/domain/entities/stock_catalog.dart';
import 'package:daily_order/domain/entities/stock_supply_insight.dart';
import 'package:daily_order/domain/entities/stock_management.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_catalog_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'stock_catalog_test.dart' as catalog;

StockCatalogItem timelineItem({bool review = false}) => StockCatalogItem({
  'item_code': 'METROLAG',
  'supply_insight': {
    'status': review ? 'history_needed' : 'in_store',
    'confidence': review ? 'unavailable' : 'inferred',
    'chart_timeline': {
      'confidence': 'estimated',
      'review_required': review,
      'periods': [
        {
          'from': '2026-01-02',
          'through': '2026-10-21',
          'returned_at': '2026-10-22',
          'days': 293,
          'months': 9,
          'remaining_days': 20,
        },
      ],
      'arrivals': [
        {'date': '2026-04-02', 'kind': 'limited', 'qty': 3},
        {'date': '2026-10-22', 'kind': 'restored', 'qty': 232},
      ],
    },
  },
  'monthly_sales': [
    for (var m = 1; m <= 10; m++)
      {
        'month': '${m.toString().padLeft(2, '0')}/2026',
        'total': m == 10 ? 5 : 12,
      },
  ],
});

StockCatalogItem continuousEmptyItem() => StockCatalogItem({
  'item_code': '16-02-07756',
  'supply_insight': {
    'status': 'store_empty',
    'confidence': 'inferred',
    'current_qty': 0,
    'through': '2026-10-26',
    'gap_days': 298,
    'at_least': true,
    'events': [],
    'issues': [],
    'effective_supply': {
      'status': 'insufficient_history',
      'model': {'months': 4, 'positive_months': 4},
    },
    'monthly': [
      for (var m = 1; m <= 10; m++)
        {
          'month': '${m.toString().padLeft(2, '0')}/2026',
          'empty_days': m == 10 ? 26 : 28,
        },
    ],
  },
  'monthly_sales': [
    for (var m = 1; m <= 10; m++)
      {'month': '${m.toString().padLeft(2, '0')}/2026', 'total': 0},
  ],
});

void main() {
  setUpAll(() async {
    final root = Platform.environment['CATALOG_FONT_ROOT'];
    if (root == null) return;
    for (final (family, file) in [
      ('Roboto', 'roboto-regular.ttf'),
      ('MaterialIcons', 'materialicons-regular.otf'),
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(
              ByteData.sublistView(File('$root/$file').readAsBytesSync()),
            ),
          ))
          .load();
    }
  });
  test(
    'continuous empty STORE history forms one span without a demand model',
    () {
      final item = continuousEmptyItem();
      final insight = StockSupplyInsight.of(item);
      expect(insight.hasSupplyAnalysis, false);
      expect(insight.chartIsContinuousStockout, true);
      final period = insight.chartPeriods.single;
      expect(period['from'], '2026-01-02');
      expect(period['through'], '2026-10-26');
      expect(period['days'], 298);
      expect(insight.supplyDuration(period), 'At least 9 months 25 days');
      expect(insight.chartMarksMonth('12/2025'), false);
      expect(insight.chartMarksMonth('02/2026'), true);
      expect(insight.chartMarksMonth('11/2026'), false);
      expect(insight.chartArrivals, isEmpty);
      expect(insight.chartMonthDescription('02/2026'), contains('298 days'));
      expect(insight.chartMonthDescription('02/2026'), contains('Estimated'));
      expect(
        insight.chartMonthDescription('02/2026'),
        isNot(contains('Small receipts')),
      );
      final rows = catalogMonthlyExportRows(item);
      expect(
        rows.singleWhere(
          (r) => r['month'] == '02/2026',
        )['STORE chart timeline'],
        contains('2026-01-02 to 2026-10-26'),
      );
      // The chart fallback must not manufacture demand or change evidence status.
      expect(insight.label, 'STORE empty · Unavailable in branches');
      expect(insight.exportFields['STORE learned daily demand'], isNull);
    },
  );
  test(
    'empty history fallback preserves evidence checks and existing timelines',
    () {
      final data = StockSupplyInsight.of(continuousEmptyItem()).data;
      for (final changes in <Map<String, dynamic>>[
        {'status': 'history_needed', 'confidence': 'unavailable'},
        {
          'issues': ['balance_mismatch'],
        },
        {'current_qty': 1},
        {'current_qty': null},
        {'gap_days': 20},
        {'through': 'invalid'},
        {
          'events': [
            {'received_qty': 3},
          ],
        },
        {
          'chart_timeline': {'periods': []},
        },
      ]) {
        expect(StockSupplyInsight({...data, ...changes}).chartPeriods, isEmpty);
      }
      expect(
        StockSupplyInsight({
          ...data,
          'confidence': 'verified',
        }).chartMonthDescription('02/2026'),
        contains('Verified'),
      );
    },
  );
  test(
    'chart export keeps estimated history and both receipt explanations',
    () {
      final rows = catalogMonthlyExportRows(timelineItem(review: true));
      expect(
        rows.singleWhere(
          (r) => r['month'] == '04/2026',
        )['STORE receipt timeline'],
        contains('Limited stock'),
      );
      expect(
        rows.singleWhere(
          (r) => r['month'] == '10/2026',
        )['STORE receipt timeline'],
        contains('232'),
      );
      expect(
        rows.singleWhere(
          (r) => r['month'] == '02/2026',
        )['STORE chart timeline'],
        contains('28 days'),
      );
      expect(
        rows.singleWhere(
          (r) => r['month'] == '02/2026',
        )['STORE chart timeline'],
        contains('needs checking'),
      );
    },
  );
  test(
    'historical gap survives return and endpoint mismatch without changing verified status',
    () {
      for (final review in [false, true]) {
        final insight = StockSupplyInsight.of(timelineItem(review: review));
        expect(insight.chartMarksMonth('03/2026'), true);
        expect(insight.chartMarksMonth('10/2026'), true);
        expect(insight.chartMarksMonth('11/2026'), false);
        expect(insight.chartMarksMonth('00/2026'), false);
        expect(insight.chartMonthDescription('02/2026'), startsWith('28 days'));
        expect(insight.chartMonthDescription('10/2026'), startsWith('21 days'));
        expect(
          insight.chartArrivalsInMonth('04/2026').single['kind'],
          'limited',
        );
        expect(insight.chartArrivalsInMonth('10/2026').single['qty'], 232);
        expect(insight.chartNeedsReview, review);
        if (review) {
          expect(insight.usable, false);
          expect(insight.exportFields['STORE gap (days)'], isNull);
          expect(
            insight.chartMonthDescription('10/2026'),
            contains('needs checking'),
          );
        }
      }
    },
  );

  for (final width in [1440.0, 540.0]) {
    testWidgets('continuous empty STORE span is shown at $width', (
      tester,
    ) async {
      final boundary = GlobalKey();
      await catalog.app(
        tester,
        SingleChildScrollView(
          child: CatalogPanel(
            title: 'Monthly sales & momentum',
            child: CatalogMonthlyChart(item: continuousEmptyItem()),
          ),
        ),
        size: Size(width, 720),
        boundary: boundary,
      );
      expect(
        find.text('Current: STORE empty · Unavailable in branches'),
        findsOneWidget,
      );
      expect(find.text('Chart history · Estimated'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(
            '.*Continuous STORE out-of-stock periods:.*2026-01-02 through 2026-10-26: At least 9 months 25 days.*',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Supply interruption · Estimated'), findsNothing);
      expect(find.text('Back in stock'), findsNothing);
      expect(tester.takeException(), isNull);
      await catalog.capture(
        tester,
        boundary,
        'stock_supply_continuous_empty_${width.toInt()}',
      );
    });
    testWidgets('receipt timeline remains readable and selectable at $width', (
      tester,
    ) async {
      final original = timelineItem(review: true);
      final supplyData = stockMap(original.data['supply_insight']);
      final timeline = stockMap(supplyData['chart_timeline']);
      final item = StockCatalogItem({
        ...original.data,
        'supply_insight': {
          ...supplyData,
          'chart_timeline': {
            ...timeline,
            'arrivals': [
              ...timeline['arrivals'] as List,
              for (var day = 1; day <= 18; day++)
                {
                  'date': '2026-10-${day.toString().padLeft(2, '0')}',
                  'kind': 'limited',
                  'qty': 1,
                },
            ],
          },
        },
      });
      final boundary = GlobalKey();
      await catalog.app(
        tester,
        SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: CatalogPanel(
              title: 'Monthly sales & momentum',
              child: CatalogMonthlyChart(item: item),
            ),
          ),
        ),
        size: Size(width, 720),
        boundary: boundary,
      );
      expect(find.text('Chart history · Estimated'), findsOneWidget);
      expect(
        find.text('Current: STORE stock unknown · Unavailable in branches'),
        findsOneWidget,
      );
      expect(find.text('Back in stock'), findsNothing);
      expect(find.text('Back · Limited stock'), findsNothing);
      expect(
        find.text('Estimated · Stock history needs checking'),
        findsOneWidget,
      );
      final scroll = tester.widget<SingleChildScrollView>(
        find.descendant(
          of: find.byType(CatalogMonthlyChart),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      scroll.controller!.jumpTo(scroll.controller!.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final chart = find.byWidgetPredicate(
        (w) =>
            w is CustomPaint &&
            w.painter.runtimeType.toString() == '_MonthlyPainter',
      );
      final series = catalogMonthlySeries(item);
      final chartSize = tester.getSize(chart);
      final initialHeight = tester
          .getSize(find.byType(CatalogMonthlyChart))
          .height;
      final initialPlotTop = tester.getTopLeft(chart).dy;
      await tester.tapAt(
        tester.getTopLeft(chart) +
            Offset(
              60 +
                  (chartSize.width - 76) / series.length * (series.length - .5),
              110,
            ),
      );
      await tester.pumpAndSettle();
      expect(find.text('19 receipts · 250 Qty · Details'), findsOneWidget);
      expect(
        tester.getSize(find.byType(CatalogMonthlyChart)).height,
        closeTo(initialHeight, .1),
      );
      expect(tester.getTopLeft(chart).dy, closeTo(initialPlotTop, .1));
      expect(
        find.textContaining('21 days of insufficient STORE supply'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('monthly-receipt-details')));
      await tester.pumpAndSettle();
      expect(find.text('Month details · 10/2026'), findsOneWidget);
      expect(find.text('232'), findsOneWidget);
      expect(find.text('22 Oct 2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await catalog.capture(
        tester,
        boundary,
        'stock_supply_timeline_${width.toInt()}',
      );
      await tester.tap(find.byTooltip('Close month details'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(CatalogMonthlyChart)).height,
        closeTo(initialHeight, .1),
      );
    });
  }
}
