import 'package:daily_order/core/utils/stock_catalog_export.dart';
import 'package:daily_order/core/utils/stock_excel_report.dart';
import 'package:daily_order/domain/entities/stock_catalog.dart';
import 'package:daily_order/domain/entities/stock_distribution.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_catalog_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_catalog_product_dialog.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_catalog_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'stock_catalog_test.dart' as catalog;

final _today = DateTime.now().toUtc().add(const Duration(hours: 4));
String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
Map<String, dynamic> facts({int covered = 5}) => {
  'complete': true,
  'run_date': _date(_today),
  'eligible': 61,
  'stocked': 4,
  'reorder': 3,
  'final': 2,
  'covered': covered,
};
Map<String, dynamic> receipt() => {
  'checked': true,
  'first_date': _date(_today.subtract(const Duration(days: 17))),
  'last_date': _date(_today.subtract(const Duration(days: 2))),
  'received_qty': 120,
};
StockCatalogItem candidate({Map<String, dynamic> overrides = const {}}) =>
    StockCatalogItem({
      ...catalog.fixture().data,
      'added_date_time': _date(_today.subtract(const Duration(days: 18))),
      'store_stock': 120,
      'distribution': facts(),
      'store_receipt': receipt(),
      ...overrides,
    });

class DistributionSource extends catalog.FakeCatalog {
  @override
  Future<StockCatalogResult> fetchPage(StockCatalogQuery query) async {
    final result = await super.fetchPage(query);
    return StockCatalogResult(
      rows: [
        for (var i = 0; i < result.rows.length; i++)
          StockCatalogItem({
            ...result.rows[i].data,
            'added_date_time': _date(_today.subtract(const Duration(days: 18))),
            'store_stock': 120,
            'distribution': facts(covered: query.offset + i == 0 ? 5 : 40),
            'store_receipt': query.offset + i == 0 ? {} : receipt(),
          }),
      ],
      summary: result.summary,
      meta: result.meta,
      categories: result.categories,
      suppliers: result.suppliers,
    );
  }

  @override
  Future<StockCatalogItem> fetchItem(String code) async => candidate(
    overrides: {
      'item_code': code,
      'branches': [
        {
          'branch': 'AL AIN',
          'branch_group': '71',
          'stock': 0,
          'distribution_eligible': true,
          'reorder_qty': 3,
          'final_qty': 0,
        },
        {
          'branch': 'CITY',
          'branch_group': 'APG',
          'stock': 0,
          'distribution_eligible': true,
          'reorder_qty': 0,
          'final_qty': 2,
        },
        {
          'branch': 'EXCLUDED',
          'branch_group': 'APG',
          'stock': 0,
          'distribution_eligible': false,
          'reorder_qty': 0,
          'final_qty': 0,
        },
      ],
    },
  );
}

void main() {
  setUpAll(() async {
    final root = Platform.environment['CATALOG_FONT_ROOT'];
    if (root == null) return;
    final roboto = FontLoader('Roboto');
    for (final name in ['roboto-regular.ttf', 'roboto-bold.ttf']) {
      roboto.addFont(
        Future.value(
          ByteData.sublistView(File('$root/$name').readAsBytesSync()),
        ),
      );
    }
    await roboto.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('$root/MaterialIcons-Regular.otf').readAsBytesSync(),
          ),
        ),
      );
    await icons.load();
    for (final family in ['FilterIcon', 'UnsortIcon']) {
      final loader = FontLoader('packages/syncfusion_flutter_datagrid/$family')
        ..addFont(
          rootBundle.load(
            'packages/syncfusion_flutter_datagrid/assets/font/$family.ttf',
          ),
        );
      await loader.load();
    }
  });
  tearDown(() => StoreBranchIdentityRegistry.groups.value = const {});
  test(
    'distribution boundaries exclude stale, missing and fully-covered facts',
    () {
      const rules = StockDistributionRules();
      expect(candidate().distributionStatus.needsDistribution, isTrue);
      expect(candidate().signal, 'New · Needs distribution');
      expect(candidate().distributionStatus.uncovered, 56);
      expect(candidate().distributionStatus.receivedAfterCreation, isTrue);
      expect(candidate().distributionStatus.daysInStore, 17);
      expect(
        candidate().distributionStatus.covered,
        5,
      ); // The server union is not 4+2.
      final cases = [
        ({'store_stock': 49.99}, false),
        ({'store_stock': 50}, true),
        ({'store_stock': 0}, false),
        ({'store_receipt': {}}, true),
        (
          {
            'store_receipt': {...receipt(), 'checked': false},
          },
          true,
        ),
        (
          {
            'store_receipt': {...receipt(), 'first_date': null},
          },
          true,
        ),
        (
          {
            'store_receipt': {...receipt(), 'received_qty': 0},
          },
          true,
        ),
        (
          {
            'store_receipt': {
              ...receipt(),
              'first_date': _date(_today.subtract(const Duration(days: 19))),
            },
          },
          true,
        ),
        (
          {
            'store_receipt': {
              ...receipt(),
              'first_date': _date(_today.add(const Duration(days: 1))),
            },
          },
          true,
        ),
        (
          {
            'store_receipt': {
              ...receipt(),
              'first_date': _date(_today.subtract(const Duration(days: 18))),
            },
          },
          true,
        ),
        (
          {
            'distribution': {...facts(), 'final_qty': 120},
          },
          false,
        ),
        (
          {
            'distribution': {...facts(), 'final_qty': 119},
            'min_order_unit': 2,
          },
          false,
        ),
        (
          {'added_date_time': _date(_today.subtract(const Duration(days: 30)))},
          true,
        ),
        (
          {'added_date_time': _date(_today.subtract(const Duration(days: 31)))},
          false,
        ),
        (
          {'added_date_time': _date(_today.add(const Duration(days: 1)))},
          false,
        ),
        ({'added_date_time': null}, false),
        ({'distribution': facts(covered: 6)}, true),
        ({'distribution': facts(covered: 7)}, false),
        (
          {
            'distribution': {...facts(covered: 6), 'eligible': 6},
          },
          false,
        ),
        (
          {
            'distribution': {...facts(), 'complete': false},
          },
          false,
        ),
        (
          {
            'distribution': {
              ...facts(),
              'run_date': _date(_today.subtract(const Duration(days: 2))),
            },
          },
          false,
        ),
        (
          {
            'distribution': {...facts(), 'run_date': null},
          },
          false,
        ),
        ({'distribution': {}}, false),
      ];
      for (final entry in cases) {
        expect(
          rules.evaluate(candidate(overrides: entry.$1)).needsDistribution,
          entry.$2,
          reason: '${entry.$1}',
        );
      }
      final csv = catalogExportRow(candidate());
      expect(csv['Distribution status'], 'New · Needs distribution');
      expect(csv['Stock or final order branches'], 5);
      expect(csv['Reorder branches'], 3);
      expect(csv['Final order branches'], 2);
      expect(csv['Branches for distribution'], 61);
      expect(csv['Days in STORE'], 17);
      expect(csv['STORE received after creation'], true);
      expect(csv['First STORE MRN date'], isNotEmpty);
      expect(
        candidate(
          overrides: {
            'store_receipt': {...receipt(), 'first_date': null},
          },
        ).distributionStatus.label,
        'New · Needs distribution',
      );
    },
  );

  testWidgets(
    'distribution card, local filter and adjustable rules agree with export',
    (tester) async {
      final source = DistributionSource();
      final key = GlobalKey();
      await catalog.app(
        tester,
        StockCatalogPage(dataSource: source),
        boundary: key,
      );
      expect(find.text('NEEDS DISTRIBUTION'), findsOneWidget);
      await tester.tap(find.text('NEEDS DISTRIBUTION'));
      await tester.pumpAndSettle();
      final grid = tester.widget<StockCatalogGrid>(
        find.byType(StockCatalogGrid),
      );
      expect(grid.items.length, 1);
      expect(grid.items.single.distributionStatus.receiptKnown, isFalse);
      expect(
        catalogExportRow(grid.items.single)['Distribution status'],
        'New · Needs distribution',
      );
      await catalog.capture(tester, key, 'stock_distribution_overview');
      await tester.tap(find.byTooltip('Distribution rules'));
      await tester.pumpAndSettle();
      await catalog.capture(tester, key, 'stock_distribution_rules');
      tester.view.physicalSize = const Size(430, 680);
      await tester.pumpAndSettle();
      expect(find.text('Apply').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await catalog.capture(tester, key, 'stock_distribution_rules_compact');
      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Minimum STORE stock'),
        '200',
      );
      await tester.pump();
      expect(find.textContaining('STORE ≥ 200 Qty'), findsOneWidget);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('No products match these filters.'), findsOneWidget);
      await tester.tap(find.byTooltip('Distribution rules'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Minimum STORE stock'),
        '-1',
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('Distribution rules'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Minimum STORE stock'),
        '50',
      );
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<StockCatalogGrid>(find.byType(StockCatalogGrid))
            .items
            .length,
        1,
      );
      expect(source.queries.length, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'distribution details show requests separately and list only uncovered eligible branches',
    (tester) async {
      final key = GlobalKey();
      await catalog.app(
        tester,
        StockCatalogProductDialog(
          item: candidate(),
          source: DistributionSource(),
        ),
        size: const Size(1480, 1100),
        boundary: key,
      );
      expect(find.text('New product distribution'), findsOneWidget);
      expect(find.text('17 days in STORE'), findsOneWidget);
      expect(find.textContaining('First STORE MRN:'), findsOneWidget);
      expect(find.textContaining('5 of 61 eligible branches'), findsOneWidget);
      expect(find.text('Reorder branches'), findsOneWidget);
      expect(find.text('Final order branches'), findsOneWidget);
      await catalog.capture(tester, key, 'stock_distribution_product');
      final filter = find.text('Uncovered eligible branches');
      await tester.ensureVisible(filter);
      await tester.pumpAndSettle();
      await tester.tap(filter);
      await tester.pumpAndSettle();
      StoreBranchIdentityRegistry.groups.value = {
        'AL AIN': '71',
        'CITY': 'APG',
        'EXCLUDED': 'APG',
      };
      await tester.pumpAndSettle();
      expect(find.text('71 AL AIN'), findsOneWidget);
      expect(find.text('CITY'), findsNothing);
      expect(find.text('EXCLUDED'), findsNothing);
      expect(
        StockExcelReport([
          {'branch': 'AL AIN', 'reorder_qty': 3},
        ], 'branches.xlsx').values.single,
        contains('71 AL AIN'),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('new product distribution fits a compact dialog', (tester) async {
    final key = GlobalKey();
    await catalog.app(
      tester,
      StockCatalogProductDialog(
        item: candidate(),
        source: DistributionSource(),
      ),
      size: const Size(430, 900),
      boundary: key,
    );
    final panel = find.text('New product distribution');
    await tester.ensureVisible(panel);
    await tester.pumpAndSettle();
    expect(find.textContaining('5 of 61 eligible branches'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await catalog.capture(tester, key, 'stock_distribution_compact');
  });
}
