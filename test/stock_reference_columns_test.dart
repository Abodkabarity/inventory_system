import 'dart:async';
import 'package:daily_order/core/utils/stock_catalog_export.dart';
import 'package:daily_order/core/utils/stock_register_export.dart';
import 'package:daily_order/core/utils/stock_excel_report.dart';
import 'package:daily_order/data/datasources/remote/stock_catalog_remote_ds.dart';
import 'package:daily_order/domain/entities/stock_catalog.dart';
import 'package:daily_order/domain/entities/stock_expiry.dart';
import 'package:daily_order/domain/entities/stock_management.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_catalog_grid.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_management_grid.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_expiry_grid.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_catalog_product_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'stock_catalog_test.dart' as catalog;

class ReferenceVersionCatalog extends catalog.MultiBatchCatalog {
  bool mixed = false;
  @override
  Future<StockCatalogResult> fetchPage(StockCatalogQuery query) async {
    final result = await super.fetchPage(query);
    return StockCatalogResult(
      rows: result.rows,
      summary: result.summary,
      meta: {...result.meta, 'reference_version': 'ref-1'},
    );
  }

  @override
  Future<StockCatalogRegisterBatch> fetchRegisterBatch(int offset) async {
    final page = await super.fetchRegisterBatch(offset);
    return StockCatalogRegisterBatch(
      rows: page.rows,
      total: page.total,
      snapshotAt: page.snapshotAt,
      referenceVersion: mixed && offset > 0 ? 'ref-2' : 'ref-1',
    );
  }
}

void main() {
  Map<String, dynamic> product(String code, String reference) => {
    'item_code': code,
    'item_name': 'Product $code',
    'reference': reference,
    'purchase_status_items': code == 'A' ? 'AVAILABLE' : 'NOT AVAILABLE',
    'last_mrn_date': '2026-10-26',
    'last_receipt_date': '2026-10-26',
    'expiry_date': '2027-02-01',
  };
  test('all exports keep reference text, zeros and expiry row scope', () {
    final item = product('A', '00017');
    final near = StockExpiryAlert({
      ...item,
      'reference': 'EXP-OLD',
      'product_data': item,
    });
    final exports = [
      catalogExportRow(StockCatalogItem(item)),
      stockRegisterExportRow(StockManagementItem(item)),
      stockExpiryExportRow(near),
    ];
    expect(exports.map((r) => r['Reference']).toList(), [
      '00017',
      '00017',
      'EXP-OLD',
    ]);
    for (final row in exports) {
      expect(row['Purchase Status'], 'AVAILABLE');
      final keys = row.keys.toList();
      expect(
        keys.indexOf('Purchase Status'),
        lessThan(keys.indexWhere((k) => k.startsWith('Sales '))),
      );
      final report = StockExcelReport([row], 'report.xlsx');
      final index = report.keys.indexOf('Reference');
      expect(report.types[index], 'text');
      expect(report.values.single[index], row['Reference']);
      expect(report.types[report.keys.indexOf('Purchase Status')], 'text');
    }
    expect(const StockManagementItem({}).purchaseStatus, 'Not assigned');
  });
  test('Overview refuses references from mixed import revisions', () async {
    expect((await ReferenceVersionCatalog().fetchAll()).rows.length, 151);
    await expectLater(
      (ReferenceVersionCatalog()..mixed = true).fetchAll(),
      throwsStateError,
    );
  });
  for (final scope in ['Overview', 'MRN', 'Near Expiry']) {
    testWidgets(
      '$scope reference is a text column after product, sortable, filterable and selectable',
      (tester) async {
        final data = [product('A', '00017 · PO-X'), product('B', '00003')];
        final horizontal = ScrollController();
        addTearDown(horizontal.dispose);
        var opens = 0;
        late Widget grid;
        if (scope == 'Overview') {
          grid = StockCatalogGrid(
            items: data.map(StockCatalogItem.new).toList(),
            onOpen: (_) => opens++,
          );
        } else if (scope == 'MRN') {
          grid = StockManagementGrid(
            items: data.map(StockManagementItem.new).toList(),
            horizontalController: horizontal,
            onOpen: (_) => opens++,
            onViewChanged: (_, _) {},
          );
        } else {
          grid = StockExpiryGrid(
            alerts: data.map(StockExpiryAlert.new).toList(),
            horizontalController: horizontal,
            busy: {},
            fading: {},
            onOpen: (_) => opens++,
            onReview: (_) {},
            onViewChanged: (_, _) {},
            riskColor: (_) => Colors.orange,
          );
        }
        await catalog.app(tester, grid, size: const Size(1500, 600));
        final widget = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
        expect(widget.columns[1].columnName, 'reference');
        final statusIndex = widget.columns.indexWhere(
          (c) => c.columnName == 'purchase_status_items',
        );
        expect(widget.columns[statusIndex + 1].columnName, 'sales_2025');
        final source = widget.source;
        expect(
          source.rows.first
              .getCells()
              .singleWhere((c) => c.columnName == 'reference')
              .value,
          '00017 · PO-X',
        );
        expect(widget.allowFiltering, true);
        expect(widget.allowSorting, true);
        source.sortedColumns.add(
          const SortColumnDetails(
            name: 'reference',
            sortDirection: DataGridSortDirection.ascending,
          ),
        );
        await source.sort();
        await tester.pumpAndSettle();
        expect(
          source.effectiveRows.first
              .getCells()
              .singleWhere((c) => c.columnName == 'reference')
              .value,
          '00003',
        );
        source.addFilter(
          'reference',
          const FilterCondition(
            type: FilterType.contains,
            value: 'PO-X',
            filterBehavior: FilterBehavior.stringDataType,
          ),
        );
        await tester.pumpAndSettle();
        expect(source.effectiveRows.length, 1);
        expect(
          find.byWidgetPredicate(
            (w) => w is SelectableText && w.data == '00017 · PO-X',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('00017 · PO-X'));
        await tester.pumpAndSettle();
        expect(opens, 1);
        source.clearFilters();
        source.sortedColumns.clear();
        source.sortedColumns.add(
          const SortColumnDetails(
            name: 'purchase_status_items',
            sortDirection: DataGridSortDirection.descending,
          ),
        );
        await source.sort();
        await tester.pumpAndSettle();
        expect(
          source.effectiveRows.first
              .getCells()
              .singleWhere((c) => c.columnName == 'purchase_status_items')
              .value,
          'NOT AVAILABLE',
        );
        source.addFilter(
          'purchase_status_items',
          const FilterCondition(
            type: FilterType.equals,
            value: 'NOT AVAILABLE',
            filterBehavior: FilterBehavior.stringDataType,
          ),
        );
        await tester.pumpAndSettle();
        expect(source.effectiveRows.length, 1);
        final beforeStatus = widget.columns
            .take(statusIndex)
            .fold<double>(0, (width, c) => width + c.width);
        final frozenWidth = widget.columns
            .take(widget.frozenColumnsCount)
            .fold<double>(0, (width, c) => width + c.width);
        widget.horizontalScrollController!.jumpTo(beforeStatus - frozenWidth);
        await tester.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (w) => w is SelectableText && w.data == 'NOT AVAILABLE',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('NOT AVAILABLE'));
        await tester.pumpAndSettle();
        expect(opens, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [1440.0, 500.0]) {
    testWidgets(
      'dialog shows purchase status beside reference and refreshes at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final saved = StockCatalogItem({
          ...catalog.fixture().data,
          'reference': 'REF-1',
          'purchase_status_items': 'NOT AVAILABLE',
        });
        final loading = Completer<StockCatalogItem>();
        await tester.pumpWidget(
          MaterialApp(
            home: StockCatalogProductDialog(
              item: saved,
              loadItem: () => loading.future,
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Purchase Status  NOT AVAILABLE'), findsOneWidget);
        final parent = find
            .ancestor(
              of: find.byKey(const ValueKey('product-purchase-status')),
              matching: find.byType(Wrap),
            )
            .first;
        expect(
          find.descendant(of: parent, matching: find.text('Reference  REF-1')),
          findsOneWidget,
        );
        loading.complete(
          StockCatalogItem({
            ...saved.data,
            'purchase_status_items': 'AVAILABLE',
          }),
        );
        await tester.pumpAndSettle();
        expect(find.text('Purchase Status  AVAILABLE'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
