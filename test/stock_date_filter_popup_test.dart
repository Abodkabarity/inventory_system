import 'dart:io';
import 'dart:ui' as ui;
import 'package:daily_order/domain/entities/stock_management.dart';
import 'package:daily_order/core/utils/stock_grid_date.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_management_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

void main() {
  setUpAll(() async {
    final root = Platform.environment['CATALOG_FONT_ROOT'];
    if (root == null) return;
    for (final family in ['Roboto', 'MaterialIcons']) {
      final name = family == 'Roboto'
          ? 'roboto-regular.ttf'
          : 'MaterialIcons-Regular.otf';
      await (FontLoader(family)..addFont(
            Future.value(
              ByteData.sublistView(File('$root/$name').readAsBytesSync()),
            ),
          ))
          .load();
    }
    for (final family in ['FilterIcon', 'UnsortIcon']) {
      await (FontLoader('packages/syncfusion_flutter_datagrid/$family')
            ..addFont(
              rootBundle.load(
                'packages/syncfusion_flutter_datagrid/assets/font/$family.ttf',
              ),
            ))
          .load();
    }
  });
  for (final showWarehouse in [false, true]) {
    testWidgets(
      'complete numeric dates in MRN filters, warehouse=$showWarehouse',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final scroll = ScrollController();
        final captureKey = GlobalKey();
        final products = [
          for (final date in ['2026-01-07', '2026-02-07', '2025-12-31'])
            StockManagementItem({
              'item_code': date,
              'item_name': 'PRODUCT $date',
              'warehouse': 'STORE',
              'last_mrn_date': date,
              'expiry_date': date,
              'added_date_time': date,
            }),
        ];
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: MaterialApp(
              theme: ThemeData(platform: TargetPlatform.windows),
              home: Scaffold(
                body: StockManagementGrid(
                  showWarehouse: showWarehouse,
                  items: products,
                  horizontalController: scroll,
                  onOpen: (_) {},
                  onViewChanged: (_, _) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
        for (final field in [
          'last_mrn_date',
          'expiry_date',
          'added_date_time',
        ]) {
          final index = grid.columns.indexWhere((c) => c.columnName == field);
          final offset = grid.columns
              .take(index)
              .fold<double>(0, (sum, c) => sum + c.width);
          final frozen = grid.columns
              .take(grid.frozenColumnsCount)
              .fold<double>(0, (sum, c) => sum + c.width);
          scroll.jumpTo(
            (offset - frozen).clamp(0, scroll.position.maxScrollExtent),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(ValueKey('datagrid_filtering_${field}_filterIcon')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Date Filters'), findsOneWidget);
          if (!showWarehouse && field == 'last_mrn_date') {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(captureKey),
            );
            await tester.runAsync(() async {
              final snapshot = await boundary.toImage();
              final png = await snapshot.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('test-results/stock_numeric_date_filter.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(png!.buffer.asUint8List());
              snapshot.dispose();
            });
          }
          final checklist = find.byKey(
            const ValueKey('datagrid_filtering_checkbox_listView'),
          );
          for (final date in ['07/01/2026', '07/02/2026', '31/12/2025']) {
            expect(
              find.descendant(of: checklist, matching: find.text(date)),
              findsWidgets,
            );
          }
          await tester.enterText(
            find.byKey(const ValueKey('datagrid_filtering_search_textfield')),
            '02/2026',
          );
          await tester.pumpAndSettle();
          expect(
            find.descendant(of: checklist, matching: find.text('07/02/2026')),
            findsWidgets,
          );
          expect(
            find.descendant(of: checklist, matching: find.text('07/01/2026')),
            findsNothing,
          );
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();
          expect(grid.source.effectiveRows.length, 1);
          expect(
            grid.source.effectiveRows.single
                .getCells()
                .singleWhere((c) => c.columnName == field)
                .value
                .toString(),
            '07/02/2026',
          );
          grid.source.clearFilters();
          grid.source.sortedColumns.clear();
          grid.source.sortedColumns.add(
            SortColumnDetails(
              name: field,
              sortDirection: DataGridSortDirection.ascending,
            ),
          );
          await grid.source.sort();
          await tester.pumpAndSettle();
          expect(
            grid.source.effectiveRows.first
                .getCells()
                .singleWhere((c) => c.columnName == field)
                .value
                .toString(),
            '31/12/2025',
          );
          grid.source.addFilter(
            field,
            FilterCondition(
              type: FilterType.greaterThan,
              value: stockGridDate(DateTime.utc(2026, 1, 8)),
            ),
          );
          await tester.pumpAndSettle();
          expect(grid.source.effectiveRows.length, 1);
          grid.source.clearFilters();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        scroll.dispose();
      },
    );
  }
}
