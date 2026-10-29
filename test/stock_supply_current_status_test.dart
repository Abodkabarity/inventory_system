import 'dart:io';

import 'package:daily_order/core/utils/stock_catalog_export.dart';
import 'package:daily_order/core/utils/stock_register_export.dart';
import 'package:daily_order/domain/entities/stock_catalog.dart';
import 'package:daily_order/domain/entities/stock_expiry.dart';
import 'package:daily_order/domain/entities/stock_management.dart';
import 'package:daily_order/domain/entities/stock_supply_insight.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_catalog_visuals.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_supply_insight_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'stock_catalog_test.dart' as catalog;

StockCatalogItem returnedItem({
  String state = 'supply_restored',
  bool summaryOnly = false,
}) => StockCatalogItem({
  'item_code': 'RETURN-EXAMPLE',
  'store_stock': state == 'limited_supply' ? 5 : 120,
  'branches_stock': 10,
  'monthly_sales': [
    for (var month = 1; month <= 10; month++)
      {
        'month': '${month.toString().padLeft(2, '0')}/2026',
        'total': month == 5 ? 203 : 42,
      },
  ],
  'supply_insight': {
    'status': 'in_store',
    'confidence': 'inferred',
    'through': '2026-10-28',
    'stock_day': '2026-10-28',
    if (!summaryOnly) 'current_qty': state == 'limited_supply' ? 5 : 120,
    'effective_supply': {
      'status': state,
      if (summaryOnly) 'daily_qty': 5,
      if (!summaryOnly) 'model': {'status': 'ready', 'daily_qty': 5},
      'latest_period': state == 'limited_supply'
          ? {
              'from': '2026-10-26',
              'through': '2026-10-28',
              'days': 3,
              'returned_at': null,
            }
          : {
              'from': '2026-09-01',
              'through': '2026-10-20',
              'days': 50,
              'returned_at': '2026-10-21',
              'received_qty': 115,
            },
    },
    if (!summaryOnly)
      'chart_timeline': {
        'periods': [
          {'from': '2026-02-01', 'through': '2026-03-01', 'days': 29},
          {'from': '2026-09-01', 'through': '2026-10-20', 'days': 50},
        ],
        // Deliberately unsorted: current state must not depend on list position.
        'arrivals': [
          {'date': '2026-10-21', 'qty': 115, 'kind': 'restored'},
          {'date': '2026-02-06', 'qty': 9, 'kind': 'limited'},
          {'date': '2026-03-02', 'qty': 60, 'kind': 'restored'},
        ],
      },
  },
});

StockCatalogItem returnedEmptyItem({String coverage = 'enough'}) {
  final original = returnedItem();
  final data = StockSupplyInsight.of(original).data;
  return StockCatalogItem({
    ...original.data,
    'store_stock': 0,
    'branches_stock': 213,
    'supply_insight': {
      ...data,
      'status': 'back_in_store',
      'current_qty': 0,
      'current_qty_basis': 'omitted_means_zero',
      'endpoint_inferred': true,
      'endpoint_difference': 232,
      'history_qty': 232,
      'returned_at': '2026-10-22',
      'received_qty': 232,
      'gap_days': 293,
      'at_least': true,
      'effective_supply': {'status': 'current_store_empty'},
      'return_assessment': {
        'from': '2026-01-02',
        'returned_at': '2026-10-22',
        'received_qty': 232,
        'gap_days': 293,
        'days': 293,
        'months': 9,
        'remaining_days': 20,
        'at_least': true,
        'coverage': coverage,
        'daily_qty': coverage == 'unknown' ? null : .558065,
        'receipt_cover_days': coverage == 'unknown' ? null : 415.72,
        'branches_qty': 213,
      },
      'chart_timeline': {
        'review_required': false,
        'periods': [
          {
            'from': '2026-01-02',
            'through': '2026-10-21',
            'days': 293,
            'months': 9,
            'remaining_days': 20,
            'returned_at': '2026-10-22',
          },
        ],
        'arrivals': [
          {
            'date': '2026-10-22',
            'qty': 232,
            'kind': coverage == 'enough' ? 'restored' : 'limited',
          },
        ],
      },
    },
  });
}

void main() {
  setUpAll(() async {
    final root = Platform.environment['CATALOG_FONT_ROOT'];
    if (root == null) return;
    for (final (family, name) in [
      ('Roboto', 'roboto-regular.ttf'),
      ('MaterialIcons', 'MaterialIcons-Regular.otf'),
    ]) {
      await (FontLoader(family)..addFont(
            Future.value(
              ByteData.sublistView(File('$root/$name').readAsBytesSync()),
            ),
          ))
          .load();
    }
  });

  test(
    'current assessment and coverage agree in summary, detail and all exports',
    () {
      for (final summaryOnly in [true, false]) {
        final item = returnedItem(summaryOnly: summaryOnly);
        final insight = StockSupplyInsight.of(item);
        expect(insight.currentLabel, 'Stock available · Available in branches');
        expect(insight.returnCoverLabel, 'Enough stock (estimated)');
        expect(insight.estimatedStoreCoverDays, 24);
        expect(insight.latestReturn['date'], '2026-10-21');
        expect(insight.latestReturn['qty'], 115);
        for (final row in [
          catalogExportRow(item),
          stockRegisterExportRow(item),
          stockExpiryExportRow(StockExpiryAlert({'product_data': item.data})),
        ]) {
          expect(
            row['STORE current status'],
            'Stock available · Available in branches',
          );
          expect(row['STORE estimated stock cover days'], 24);
          expect(
            row['STORE last marked return cover'],
            'Enough stock at arrival (estimated)',
          );
        }
      }
    },
  );

  test(
    'a past good arrival cannot override a current shortage or missing evidence',
    () {
      final item = returnedItem(state: 'limited_supply');
      final low = StockSupplyInsight.of(item);
      expect(low.currentLabel, 'Limited stock · Available in branches');
      expect(low.returnCoverLabel, 'Limited stock now');
      expect(low.estimatedStoreCoverDays, 1);
      expect(
        StockSupplyInsight.arrivalLabel(low.latestReturn),
        contains('Enough stock at arrival'),
      );
      final unverified = StockSupplyInsight({
        ...low.data,
        'status': 'history_needed',
        'confidence': 'unavailable',
      });
      expect(
        unverified.currentLabel,
        'STORE stock unknown · Unavailable in branches',
      );
      expect(unverified.latestReturn, isEmpty);
      expect(unverified.estimatedStoreCoverDays, isNull);
      expect(unverified.currentStoreQty, isNull);
    },
  );

  test(
    'one unit and insufficient sales history must never imply limited stock',
    () {
      final insight = StockSupplyInsight({
        'status': 'back_in_store',
        'confidence': 'inferred',
        'current_qty': 1,
        'through': '2026-10-28',
        'returned_at': '2026-10-26',
        'received_qty': 1,
        'effective_supply': {'status': 'insufficient_history'},
      });
      expect(insight.currentLabel, 'In STORE · Unavailable in branches');
      expect(insight.returnCoverLabel, 'Cover not confirmed');
      expect(insight.estimatedStoreCoverDays, isNull);
      expect(
        StockSupplyInsight.arrivalLabel(insight.latestReturn),
        'Cover at arrival not confirmed',
      );
      expect(
        insight.currentExplanation,
        contains('Demand cannot yet be estimated reliably'),
      );
    },
  );

  test(
    'invalid demand and explicit missing stock cannot become zero or infinite cover',
    () {
      final data = StockSupplyInsight.of(returnedItem()).data;
      for (final qty in [null, -1, double.nan]) {
        expect(
          StockSupplyInsight({
            ...data,
            'current_qty': qty,
          }).estimatedStoreCoverDays,
          isNull,
        );
      }
      for (final daily in [null, 0, -1, double.infinity]) {
        expect(
          StockSupplyInsight({
            ...data,
            'effective_supply': {
              'status': 'adequate_supply',
              'model': {'daily_qty': daily},
            },
          }).estimatedStoreCoverDays,
          isNull,
        );
      }
    },
  );

  test('returned supply is retained when STORE report omits the item', () {
    for (final coverage in ['enough', 'limited', 'unknown']) {
      const label = 'STORE empty · Available in branches';
      final item = returnedEmptyItem(coverage: coverage);
      final insight = StockSupplyInsight.of(item);
      expect(insight.label, label);
      expect(insight.currentStoreQty, 0);
      expect(insight.latestReturn['date'], '2026-10-22');
      expect(insight.displayGapLabel, 'At least 9 months 20 days');
      expect(
        insight.currentExplanation,
        contains('STORE currently has no stock'),
      );
      expect(
        insight.basisDescription,
        isNot(contains('match the current STORE ledger')),
      );
      for (final row in [
        catalogExportRow(item),
        stockRegisterExportRow(item),
        stockExpiryExportRow(StockExpiryAlert({'product_data': item.data})),
      ]) {
        expect(row['STORE review'], label);
        expect(row['STORE current quantity basis'], 'omitted_means_zero');
        expect(row['STORE return received Qty'], 232);
      }
      final review = StockSupplyInsight({
        ...insight.data,
        'status': 'history_needed',
        'confidence': 'unavailable',
      });
      expect(review.hasReturnAssessment, false);
      expect(
        review.currentLabel,
        'STORE stock unknown · Unavailable in branches',
      );
      final badDate = StockSupplyInsight({
        ...insight.data,
        'returned_at': '2026-10-23',
      });
      expect(badDate.hasReturnAssessment, false);
    }
  });

  test(
    'current availability uses recorded branch stock and counts missing quantities as zero',
    () {
      for (final (storeQty, prefix) in [
        (0.0, 'STORE empty'),
        (5.0, 'Limited stock'),
        (120.0, 'Stock available'),
      ]) {
        for (final (branchQty, suffix) in <(double?, String)>[
          (62, 'Available in branches'),
          (0, 'Unavailable in branches'),
          (null, 'Unavailable in branches'),
        ]) {
          final original = returnedItem();
          final item = StockCatalogItem({
            ...original.data,
            'store_stock': storeQty,
            'branches_stock': branchQty,
          });
          final insight = StockSupplyInsight.of(item);
          expect(insight.label, '$prefix · $suffix');
          for (final row in [
            catalogExportRow(item),
            stockRegisterExportRow(item),
            stockExpiryExportRow(StockExpiryAlert({'product_data': item.data})),
          ]) {
            expect(row['STORE review'], insight.label);
            expect(row['STORE current branches availability'], suffix);
          }
        }
      }
    },
  );

  test(
    'missing current branch balance is zero even when historical receipt evidence has stock',
    () {
      final original = returnedEmptyItem();
      for (final reference in <Map<String, dynamic>>[
        {...original.data}..remove('branches_stock'),
        {...original.data, 'branches_stock': null},
        {...original.data, 'branches_stock': 0},
      ]) {
        final item = StockCatalogItem(reference);
        final insight = StockSupplyInsight.of(item);
        expect(insight.returnAssessment['branches_qty'], 213);
        expect(insight.currentBranchesQty, 0);
        expect(insight.label, 'STORE empty · Unavailable in branches');
        for (final row in [
          catalogExportRow(item),
          stockRegisterExportRow(item),
          stockExpiryExportRow(StockExpiryAlert({'product_data': item.data})),
        ]) {
          expect(row['STORE review'], insight.label);
          expect(
            row['STORE current branches availability'],
            'Unavailable in branches',
          );
        }
      }
      final recorded = StockSupplyInsight.of(
        StockCatalogItem({...original.data, 'branches_stock': 18}),
      );
      expect(recorded.currentBranchesQty, 18);
      expect(recorded.label, 'STORE empty · Available in branches');
    },
  );

  test(
    'new snapshot quantities change current state without changing past return facts',
    () {
      final original = returnedEmptyItem();
      for (final (storeQty, expected) in [
        (0, 'STORE empty'),
        (1, 'Limited stock'),
        (10, 'Stock available'),
        (0, 'STORE empty'),
      ]) {
        final insight = StockSupplyInsight.of(
          StockCatalogItem({
            ...original.data,
            'store_stock': storeQty,
            'branches_stock': 0,
          }),
        );
        expect(insight.label, '$expected · Unavailable in branches');
        expect(insight.latestReturn['qty'], 232);
        expect(insight.latestReturn['date'], '2026-10-22');
        expect(insight.chartPeriods.single['days'], 293);
      }
      final unknown = StockSupplyInsight.of(
        StockCatalogItem({
          ...original.data,
          'store_stock': null,
          'branches_stock': null,
        }),
      );
      expect(unknown.label, 'STORE stock unknown · Unavailable in branches');
      final noReport = StockSupplyInsight.of(
        StockCatalogItem({...original.data, 'stock_unavailable': true}),
      );
      expect(noReport.label, 'Stock data unavailable');
      final sparse = StockSupplyInsight.of(
        const StockCatalogItem({'store_stock': 1, 'branches_stock': 0}),
      );
      expect(sparse.label, 'In STORE · Unavailable in branches');
      expect(sparse.currentExplanation, contains('coverage is not confirmed'));
    },
  );

  for (final width in [1440.0, 540.0, 360.0]) {
    testWidgets(
      'missing STORE item displays return, zero stock and branch stock at $width',
      (tester) async {
        final boundary = GlobalKey();
        final item = returnedEmptyItem();
        await catalog.app(
          tester,
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: CatalogPanel(
                title: 'Monthly sales & momentum',
                child: CatalogMonthlyChart(item: item),
              ),
            ),
          ),
          size: Size(width, 1000),
          boundary: boundary,
        );
        expect(
          find.text('Current: STORE empty · Available in branches'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Last return after shortage:'),
          findsNothing,
        );
        expect(find.textContaining('STORE stock: 0 Qty'), findsNothing);
        expect(find.textContaining('Branches: 213 Qty'), findsNothing);
        expect(
          find.textContaining('about 415.72 days of estimated demand'),
          findsNothing,
        );
        expect(find.textContaining('Review supply'), findsNothing);
        expect(tester.takeException(), isNull);
        await catalog.capture(
          tester,
          boundary,
          'stock_return_zero_${width.toInt()}',
        );
      },
    );
    testWidgets(
      'chart shows one current state with dated historical arrivals at $width',
      (tester) async {
        final item = returnedItem();
        final boundary = GlobalKey();
        await catalog.app(
          tester,
          SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: CatalogPanel(
                title: 'Monthly sales & momentum',
                child: CatalogMonthlyChart(item: item),
              ),
            ),
          ),
          size: Size(width, 900),
          boundary: boundary,
        );
        expect(
          find.byKey(const ValueKey('monthly-current-store-status')),
          findsOneWidget,
        );
        expect(
          find.text('Current: Stock available · Available in branches'),
          findsOneWidget,
        );
        expect(find.text('Back · Limited stock'), findsNothing);
        expect(find.text('Back in stock'), findsNothing);
        expect(
          find.textContaining(
            '21 Oct 2026 · 115 Qty · Enough stock at arrival',
          ),
          findsNothing,
        );
        expect(
          find.textContaining('Estimated to last about 24 days at 5 Qty/day'),
          findsNothing,
        );
        expect(
          StockSupplyInsight.of(
            item,
          ).chartArrivalsInMonth('02/2026').single['kind'],
          'limited',
        );
        expect(tester.takeException(), isNull);
        await catalog.capture(
          tester,
          boundary,
          'stock_current_status_${width.toInt()}',
        );
      },
    );
  }

  testWidgets(
    'current status cells separate STORE and branches and fit normal expiry rows',
    (tester) async {
      final boundary = GlobalKey();
      final samples = [
        const StockManagementItem({
          'supply_insight': {
            'status': 'back_in_store',
            'confidence': 'inferred',
            'gap_days': 33,
            'current_qty': 1,
            'effective_supply': {'status': 'insufficient_history'},
          },
        }),
        returnedEmptyItem(),
        StockManagementItem({...returnedEmptyItem().data, 'branches_stock': 0}),
        returnedItem(state: 'limited_supply'),
        returnedItem(),
      ];
      await catalog.app(
        tester,
        Center(
          child: SizedBox(
            width: 210,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final sample in samples)
                  SizedBox(
                    height: 78,
                    child: Center(child: StockSupplyReviewCell(item: sample)),
                  ),
              ],
            ),
          ),
        ),
        size: const Size(250, 430),
        boundary: boundary,
      );
      expect(find.text('In STORE'), findsOneWidget);
      expect(find.text('Unavailable in branches'), findsNWidgets(2));
      expect(find.text('Available in branches'), findsNWidgets(3));
      expect(find.text('Limited stock'), findsOneWidget);
      expect(find.text('Stock available'), findsOneWidget);
      expect(find.text('Cover not confirmed'), findsNothing);
      expect(tester.takeException(), isNull);
      await catalog.capture(tester, boundary, 'stock_status_cells_redesign');
    },
  );
  for (final coverage in ['enough', 'limited', 'unknown']) {
    testWidgets(
      'returned-$coverage cell fits a normal row and keeps its return explanation',
      (tester) async {
        final item = returnedEmptyItem(coverage: coverage);
        await catalog.app(
          tester,
          Center(
            child: SizedBox(
              width: 190,
              height: 88,
              child: StockSupplyReviewCell(item: item),
            ),
          ),
        );
        expect(find.text('STORE empty'), findsOneWidget);
        expect(find.text('Available in branches'), findsOneWidget);
        expect(
          find.text(StockSupplyInsight.of(item).returnCoverLabel),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
