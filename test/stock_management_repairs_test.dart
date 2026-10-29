import 'package:daily_order/core/utils/stock_catalog_export.dart';
import 'package:daily_order/core/utils/stock_register_export.dart';
import 'package:daily_order/domain/entities/stock_catalog.dart';
import 'package:daily_order/domain/entities/stock_management.dart';
import 'package:daily_order/domain/entities/stock_expiry.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_management_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_expiry_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_catalog_grid.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_catalog_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'stock_management_test.dart' as stock;
import 'stock_expiry_test.dart' as expiry;

class ExportSource extends stock.FakeStockSource {
  @override
  Future<StockManagementResult> fetchPage(StockManagementQuery query) async =>
      StockManagementResult(
        rows: [
          for (final row in [('A', 10), ('B', 30), ('C', 20)])
            StockManagementItem({
              ...stock.product(code: row.$1).data,
              'total_stock': row.$2,
            }),
        ],
        summary: const {'items': 3},
        meta: const {},
      );
}

Future<void> show(
  WidgetTester tester,
  Widget page, {
  Size size = const Size(1440, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'ratios use total stock and 45-day sales, with safe empty denominators',
    () {
      const item = StockManagementItem({
        'store_stock': 42,
        'total_stock': 129,
        'recent_sales': 26,
      });
      expect(item.storeTotalPercent, closeTo(42 / 129 * 100, 1e-9));
      expect(item.stockSalesPercent, closeTo(129 / 26 * 100, 1e-9));
      expect(
        const StockManagementItem({
          'total_stock': 0,
          'recent_sales': 26,
        }).stockSalesPercent,
        0,
      );
      expect(
        const StockManagementItem({
          'total_stock': 129,
          'recent_sales': 0,
        }).stockSalesPercent,
        isNull,
      );
      expect(
        const StockManagementItem({
          'total_stock': 129,
          'recent_sales': -1,
        }).stockSalesPercent,
        isNull,
      );
      expect(
        const StockManagementItem({
          'store_stock': 0,
          'total_stock': 0,
        }).storeTotalPercent,
        isNull,
      );
      expect(
        const StockManagementItem({
          'total_stock': 129,
          'recent_sales': 26,
          'stock_unavailable': true,
        }).stockSalesPercent,
        isNull,
      );
    },
  );

  testWidgets(
    'shared chart shows uncapped stock / sales and handles unavailable stock',
    (tester) async {
      await show(
        tester,
        const CatalogStockChart(
          item: StockManagementItem({'total_stock': 129, 'recent_sales': 26}),
        ),
      );
      expect(find.text('496.2% stock / sales'), findsOneWidget);
      expect(find.text('Sales (45D)'), findsOneWidget);
      await show(
        tester,
        const CatalogStockChart(
          item: StockManagementItem({
            'total_stock': 129,
            'recent_sales': 26,
            'stock_unavailable': true,
          }),
        ),
      );
      expect(find.text('Stock unavailable'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    },
  );

  testWidgets(
    'overview uses new columns and retains actual partial order counts',
    (tester) async {
      final now = DateTime.now().toUtc().add(const Duration(hours: 4));
      final item = StockCatalogItem({
        'item_code': 'A',
        'item_name': 'PRODUCT A',
        'store_stock': 25,
        'total_stock': 100,
        'recent_sales': 45,
        'distribution': {
          'complete': false,
          'observed': 60,
          'run_date':
              '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
          'reorder': 2,
          'final': 3,
          'reorder_qty': 6,
          'final_qty': 9,
        },
      });
      await show(tester, StockCatalogGrid(items: [item], onOpen: (_) {}));
      final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
      final names = grid.columns.map((c) => c.columnName);
      expect(names, contains('recent_sales'));
      for (final removed in [
        'baseline_daily',
        'growth',
        'distribution',
        'store_receipt_date',
        'days_in_store',
        'stocked_branches',
      ]) {
        expect(names, isNot(contains(removed)));
      }
      final cells = {
        for (final c in grid.source.rows.single.getCells())
          c.columnName: c.value,
      };
      expect(cells['ratio'], 25);
      expect(cells['recent_sales'], 45);
      expect(cells['reorder_branches'], 2);
      expect(cells['final_order_branches'], 3);
      expect(item.distributionStatus.known, isFalse);
      expect(item.distributionStatus.needsDistribution, isFalse);
      final csv = catalogExportRow(item);
      expect(csv['STORE / Total Stock %'], 25);
      expect(csv['Reorder Qty'], 6);
      expect(csv['Final Reorder Qty'], 9);
      expect(csv['Order data complete'], 'No');
    },
  );

  testWidgets('MRN export preserves Excel filters and numeric sort', (
    tester,
  ) async {
    List<Map<String, dynamic>>? exported;
    String? fileName;
    await show(
      tester,
      StockManagementPage(
        dataSource: ExportSource(),
        exporter: (rows, file) async {
          exported = rows;
          fileName = file;
        },
      ),
    );
    final data = tester.widget<SfDataGrid>(find.byType(SfDataGrid)).source;
    data.addFilter(
      'total_stock',
      const FilterCondition(type: FilterType.greaterThan, value: 15),
    );
    data.sortedColumns.add(
      const SortColumnDetails(
        name: 'total_stock',
        sortDirection: DataGridSortDirection.descending,
      ),
    );
    await data.sort();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mrn-export')));
    await tester.pumpAndSettle();
    expect(fileName, 'mrn_overview.xlsx');
    expect(exported!.map((r) => r['Item code']), ['B', 'C']);
    expect(exported!.first['Created date'], '01/01/2025');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'expiry export preserves filters, sort, receipt dates and quantities',
    (tester) async {
      List<Map<String, dynamic>>? exported;
      final source = expiry.FakeExpirySource()
        ..items = [
          expiry.expiryAlert(
            code: 'A',
            orderedQty: 100,
            receivedQty: 40,
            note: 'Check batch',
          ),
          expiry.expiryAlert(code: 'B', orderedQty: 70, receivedQty: 60),
          expiry.expiryAlert(code: 'C', receivedQty: 10),
        ];
      await show(
        tester,
        StockExpiryPage(
          dataSource: source,
          exporter: (rows, file) async {
            exported = rows;
            expect(file, 'near_expiry.xlsx');
          },
        ),
      );
      final data = tester.widget<SfDataGrid>(find.byType(SfDataGrid)).source;
      data.addFilter(
        'received_qty',
        const FilterCondition(type: FilterType.greaterThan, value: 30),
      );
      data.sortedColumns.clear();
      data.sortedColumns.add(
        const SortColumnDetails(
          name: 'received_qty',
          sortDirection: DataGridSortDirection.descending,
        ),
      );
      await data.sort();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('expiry-export')));
      await tester.pumpAndSettle();
      expect(exported!.map((r) => r['Item code']), ['B', 'A']);
      expect(exported![1]['Ordered Qty'], 100);
      expect(exported![1]['Total Qty'], 40);
      expect(exported![1]['MRN date'], '03/10/2026');
      expect(exported![1]['Expiry date'], '01/11/2026');
      expect(exported![1]['Note'], 'Check batch');
      expect(tester.takeException(), isNull);
    },
  );

  test('missing stock stays unavailable in expiry exports', () {
    final alert = expiry.expiryAlert();
    final row = stockExpiryExportRow(
      StockExpiryAlert({
        ...alert.data,
        'product_data': {...alert.product.data, 'stock_unavailable': true},
      }),
    );
    expect(row['Total stock'], isNull);
    expect(row['Store stock'], isNull);
    expect(row['Stock / Sales %'], isNull);
    expect(row['Total Qty'], 25);
    expect(row['Sales 45D'], isNotNull);
  });
}
