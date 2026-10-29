import 'package:daily_order/core/utils/stock_catalog_export.dart';
import 'package:daily_order/core/utils/stock_excel_report.dart';
import 'package:daily_order/domain/entities/stock_catalog.dart';
import 'package:daily_order/domain/entities/stock_expiry.dart';
import 'package:daily_order/domain/entities/stock_management.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_catalog_grid.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_expiry_grid.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_management_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

void main() {
  testWidgets(
    'all Stock Management grids filter and sort by the Dubai created date',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final products = [
        for (var i = 0; i < 4; i++)
          StockManagementItem({
            'item_code': '$i',
            'item_name': 'PRODUCT $i',
            'added_date_time': [
              '2025-01-01T00:00:00+04:00',
              '2025-01-01T19:59:59Z',
              '2025-01-01T20:00:00Z',
              null,
            ][i],
          }),
      ];
      for (final type in ['catalog', 'mrn', 'expiry']) {
        final controller = ScrollController();
        final Widget grid = switch (type) {
          'catalog' => StockCatalogGrid(
            items: products.map((p) => StockCatalogItem(p.data)).toList(),
            onOpen: (_) {},
          ),
          'mrn' => StockManagementGrid(
            items: products,
            horizontalController: controller,
            onOpen: (_) {},
            onViewChanged: (_, _) {},
          ),
          _ => StockExpiryGrid(
            alerts: products
                .map(
                  (p) => StockExpiryAlert({
                    'item_code': p.code,
                    'expiry_date': '2026-12-01',
                    'product_data': p.data,
                  }),
                )
                .toList(),
            busy: const {},
            fading: const {},
            horizontalController: controller,
            onOpen: (_) {},
            onReview: (_) {},
            riskColor: (_) => Colors.orange,
            onViewChanged: (_, _) {},
          ),
        };
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.windows),
            home: Scaffold(body: grid),
          ),
        );
        await tester.pumpAndSettle();
        final table = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
        final dates = table.source.rows
            .map(
              (r) => r
                  .getCells()
                  .singleWhere((c) => c.columnName == 'added_date_time')
                  .value,
            )
            .toList();
        expect(dates, [
          DateTime(2025, 1, 1),
          DateTime(2025, 1, 1),
          DateTime(2025, 1, 2),
          null,
        ], reason: type);
        final columnIndex = table.columns.indexWhere(
          (c) => c.columnName == 'added_date_time',
        );
        final offset = table.columns
            .take(columnIndex)
            .fold<double>(0, (sum, c) => sum + c.width);
        final scroll = table.horizontalScrollController!;
        final frozenWidth = table.columns
            .take(table.frozenColumnsCount)
            .fold<double>(0, (sum, c) => sum + c.width);
        scroll.jumpTo(
          (offset - frozenWidth).clamp(0, scroll.position.maxScrollExtent),
        );
        await tester.pumpAndSettle();
        expect(find.text('01/01/2025'), findsWidgets, reason: type);
        expect(find.text('02/01/2025'), findsWidgets, reason: type);
        await tester.tap(
          find.byKey(
            const ValueKey('datagrid_filtering_added_date_time_filterIcon'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Date Filters'), findsOneWidget, reason: type);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        table.source.addFilter(
          'added_date_time',
          FilterCondition(type: FilterType.equals, value: DateTime(2025, 1, 1)),
        );
        await tester.pumpAndSettle();
        expect(table.source.effectiveRows.length, 2, reason: type);
        table.source.clearFilters();
        table.source.sortedColumns.clear();
        table.source.sortedColumns.add(
          const SortColumnDetails(
            name: 'added_date_time',
            sortDirection: DataGridSortDirection.descending,
          ),
        );
        await table.source.sort();
        await tester.pumpAndSettle();
        final orderedDates = table.source.effectiveRows
            .map(
              (r) => r
                  .getCells()
                  .singleWhere((c) => c.columnName == 'added_date_time')
                  .value,
            )
            .whereType<DateTime>()
            .toList();
        expect(orderedDates.first, DateTime(2025, 1, 2), reason: type);
        expect(tester.takeException(), isNull, reason: type);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
      final row = catalogExportRow(StockCatalogItem(products.first.data));
      expect(row['Created date'], '01/01/2025');
      final report = StockExcelReport([row], 'stock_overview');
      final dateColumn = report.keys.indexOf('Created date');
      expect(report.types[dateColumn], 'date');
      expect(report.values.single[dateColumn], '2025-01-01T00:00:00.000Z');
      expect(row['Created date'], isNot(contains('00:00')));
    },
  );
}
