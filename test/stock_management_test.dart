// The app already uses the Supabase client's transitive http dependency.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';

import 'package:daily_order/data/datasources/remote/stock_management_remote_ds.dart';
import 'package:daily_order/domain/entities/stock_management.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_management_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_management_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

StockManagementItem product({
  String code = '16-01-00362',
  String status = 'low_cover',
}) => StockManagementItem({
  'item_code': code,
  'item_name': 'artelac advanced sdu eye drops 0.5 ml 30 s',
  'supplier': 'Lunatus Drug Store LLC',
  'company': 'Bausch & Lomb',
  'category': 'Medicine',
  'added_date_time': '2025-01-01T00:00:00+04:00',
  'stock_status': status,
  'total_stock': status == 'no_stock' ? 0 : 1908.19,
  'store_stock': 561,
  'branches_stock': 1347.19,
  'stocked_branches': 60,
  'store_branches_ratio': .4164,
  'days_on_hand': status == 'no_sales' ? null : 25.72,
  'last_mrn_date': '2026-10-06',
  'last_mrn_no': '105058',
  'reference': 'in26217285',
  'last_mrn_qty': 500,
  'received_quantity': 500,
  'ordered_quantity': 500,
  'expiry_date': code == '16-01-00362' ? '2026-12-01' : '2028-01-01',
  'recent_sales': 3337.6665,
  'daily_sales': 74.17,
  'years': {
    '2025': {
      'cash': 5288.9957,
      'insurance': 17936.7167,
      'online': 2076.3333,
      'total': 25302.0457,
      'best_month': '09/2025',
      'best_qty': 3309.6661,
    },
    '2026': {
      'cash': 3319.3298,
      'insurance': 14431.678,
      'online': 2374,
      'total': 20125.0078,
      'best_month': '04/2026',
      'best_qty': 2465.9998,
    },
  },
  'meta': {
    'demand_from': '2026-08-22',
    'demand_through': '2026-10-05',
    'demand_days': 45,
  },
  'branches': [
    {
      'branch': 'AL AIN MAIN',
      'stock': 52,
      'company': 'APG',
      'sales_2025': 1360.33,
      'sales_2026': 990.67,
    },
  ],
  'monthly_sales': [
    for (var month = 1; month <= 12; month++)
      {
        'month': '${month.toString().padLeft(2, '0')}/2025',
        'total': month * 170.5,
      },
    for (var month = 1; month <= 10; month++)
      {
        'month': '${month.toString().padLeft(2, '0')}/2026',
        'total': month * 152.3,
      },
  ],
});

class FakeStockSource extends StockManagementDataSource {
  final queries = <StockManagementQuery>[];
  bool fail = false;
  int refreshes = 0;
  String? jobStatus;
  Completer<StockManagementResult>? pending;
  @override
  Future<StockManagementResult> fetchPage(StockManagementQuery query) async {
    queries.add(query);
    if (fail) throw StateError('Network unavailable');
    if (pending != null) return pending!.future;
    return StockManagementResult(
      rows: [
        product(),
        product(code: '16-01-00363', status: 'no_stock'),
      ],
      summary: const {'items': 2, 'no_stock': 1, 'low_cover': 1, 'no_sales': 0},
      meta: const {
        'stock_updated_at': '2026-10-06',
        'mrn_through': '2026-10-06',
        'demand_through': '2026-10-05',
      },
      categories: const ['Medicine'],
      suppliers: const ['Lunatus Drug Store LLC'],
    );
  }

  @override
  Future<StockManagementItem> fetchItem(String itemCode) async =>
      product(code: itemCode);
  @override
  Future<void> requestRefresh() async {
    refreshes++;
    jobStatus = 'queued';
  }

  @override
  Future<Map<String, dynamic>?> refreshState() async =>
      jobStatus == null ? null : {'status': jobStatus};
}

class PagedStockSource extends FakeStockSource {
  final offsets = <int>[];
  bool changeSnapshot = false;
  String? canonicalSnapshot;
  String refreshedAt = '2026-10-07T15:42:00+04:00';

  @override
  Future<StockManagementResult> fetchPage(StockManagementQuery query) async =>
      StockManagementResult(
        rows: [],
        summary: {'items': 3},
        meta: {
          'refreshed_at': refreshedAt,
          if (canonicalSnapshot != null) 'snapshot_at': canonicalSnapshot,
        },
      );

  @override
  Future<StockManagementRegisterBatch> fetchRegisterBatch(int offset) async {
    offsets.add(offset);
    return StockManagementRegisterBatch(
      rows: offset == 0
          ? [product(code: 'A'), product(code: 'B')]
          : [product(code: 'C')],
      total: 3,
      snapshotAt: changeSnapshot && offset > 0
          ? '2026-10-07T16:00:00+04:00'
          : '2026-10-07T15:42:00+04:00',
    );
  }
}

class AutoRefreshStockSource extends FakeStockSource {
  DateTime completedAt = DateTime.utc(2026, 10, 7, 11, 42);

  @override
  Future<Map<String, dynamic>?> refreshState() async => {
    'status': 'complete',
    'completed_at': completedAt.toIso8601String(),
  };
}

class BranchSortingStockSource extends FakeStockSource {
  @override
  Future<StockManagementItem> fetchItem(
    String itemCode,
  ) async => StockManagementItem({
    ...product().data,
    'branches': [
      {'branch': 'BRANCH A', 'stock': 5, 'sales_2025': 80, 'sales_2026': 10},
      {'branch': 'BRANCH B', 'stock': 20, 'sales_2025': 30, 'sales_2026': 90},
    ],
  });
}

Future<void> showPage(
  WidgetTester tester,
  FakeStockSource source, {
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(body: StockManagementPage(dataSource: source)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('branch stock and yearly sales toggle numeric sort direction', (
    tester,
  ) async {
    await showPage(tester, BranchSortingStockSource());
    await tester.tap(find.byKey(const ValueKey('mrn-date:16-01-00362')));
    await tester.pumpAndSettle();
    final stockHeader = find.byKey(const ValueKey('branch-sort:stock'));
    await tester.ensureVisible(stockHeader);
    await tester.pumpAndSettle();
    bool aFirst() =>
        tester.getTopLeft(find.text('BRANCH A')).dy <
        tester.getTopLeft(find.text('BRANCH B')).dy;
    expect(aFirst(), isFalse);
    await tester.tap(stockHeader);
    await tester.pumpAndSettle();
    expect(aFirst(), isTrue);
    await tester.tap(find.byKey(const ValueKey('branch-sort:sales_2025')));
    await tester.pumpAndSettle();
    expect(aFirst(), isTrue);
    await tester.tap(find.byKey(const ValueKey('branch-sort:sales_2025')));
    await tester.pumpAndSettle();
    expect(aFirst(), isFalse);
    await tester.tap(find.byKey(const ValueKey('branch-sort:sales_2026')));
    await tester.pumpAndSettle();
    expect(aFirst(), isFalse);
    await tester.tap(find.byKey(const ValueKey('branch-sort:sales_2026')));
    await tester.pumpAndSettle();
    expect(aFirst(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overview product fields are uppercase and selectable', (
    tester,
  ) async {
    await showPage(tester, FakeStockSource());
    final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
    final cells = grid.source.rows.first.getCells();
    String value(String key) =>
        cells.singleWhere((c) => c.columnName == key).value as String;

    expect(value('item_name'), 'ARTELAC ADVANCED SDU EYE DROPS 0.5 ML 30 S');
    expect(value('supplier'), 'LUNATUS DRUG STORE LLC');
    expect(value('company'), 'BAUSCH & LOMB');
    expect(value('category'), 'MEDICINE');
    final selectable = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableText &&
          widget.textSpan?.toPlainText() ==
              '16-01-00362 · LUNATUS DRUG STORE LLC',
    );
    expect(selectable, findsOneWidget);
    final codeStyle =
        tester.widget<SelectableText>(selectable).textSpan!.children!.first
            as TextSpan;
    expect(codeStyle.style?.fontWeight, FontWeight.w800);
    await tester.longPress(selectable);
    await tester.pumpAndSettle();
    final selectedText = tester.widget<EditableText>(
      find.descendant(of: selectable, matching: find.byType(EditableText)),
    );
    expect(selectedText.controller.selection.isCollapsed, isFalse);
  });

  test('expiry warning uses six calendar months, not 180 days', () {
    final today = DateTime.utc(2026, 10, 8);
    expect(stockMrnExpiryIsNear(DateTime.utc(2027, 4, 7), today), isTrue);
    expect(stockMrnExpiryIsNear(DateTime.utc(2027, 4, 8), today), isFalse);
    expect(stockMrnExpiryIsNear(null, today), isFalse);
    final monthEnd = DateTime.utc(2026, 8, 31);
    expect(stockMrnExpiryIsNear(DateTime.utc(2027, 2, 27), monthEnd), isTrue);
    expect(stockMrnExpiryIsNear(DateTime.utc(2027, 2, 28), monthEnd), isFalse);
  });

  test('query transmits server-side filters, dates and bounded page', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'rows': [product(status: 'no_sales').data],
            'summary': {'items': 1},
            'meta': {},
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    final result = await StockManagementRemoteDs(client).fetchPage(
      const StockManagementQuery(
        search: ' ARTELAC ',
        status: 'no_sales',
        category: 'Medicine',
        supplier: 'Lunatus',
        receivedFrom: '2026-10-01',
        receivedTo: '2026-10-06',
        sort: 'days_low',
        offset: 50,
        limit: 50,
      ),
    );
    expect(requests.single.url.path, '/rest/v1/rpc/get_stock_management_page');
    expect(jsonDecode(requests.single.body), {
      'p_search': 'ARTELAC',
      'p_status': 'no_sales',
      'p_category': 'Medicine',
      'p_supplier': 'Lunatus',
      'p_received_from': '2026-10-01',
      'p_received_to': '2026-10-06',
      'p_sort': 'days_low',
      'p_offset': 50,
      'p_limit': 50,
    });
    expect(result.rows.single.days, isNull);
    expect(result.rows.single.year(2025)['best_month'], '09/2025');
  });

  test('complete-register RPC carries expiry and a bounded batch', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'rows': [product().data],
            'total': 9581,
            'snapshot_at': '2026-10-07T15:42:00+04:00',
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    final batch = await StockManagementRemoteDs(
      client,
    ).fetchRegisterBatch(5000);
    expect(
      requests.single.url.path,
      '/rest/v1/rpc/get_stock_management_register_batch',
    );
    expect(jsonDecode(requests.single.body), {
      'p_offset': 5000,
      'p_limit': 5000,
    });
    expect(batch.rows.single.text('expiry_date'), '2026-12-01');
    expect(batch.total, 9581);
  });

  test(
    'complete register assembles batches and rejects mixed snapshots',
    () async {
      final source = PagedStockSource();
      final complete = await source.fetchAll();
      expect(source.offsets, [0, 2]);
      expect(complete.rows.map((row) => row.code), ['A', 'B', 'C']);
      source.offsets.clear();
      source.changeSnapshot = true;
      await expectLater(source.fetchAll(), throwsStateError);
    },
  );

  test('canonical snapshot permits stale source refresh metadata', () async {
    final source = PagedStockSource()
      ..refreshedAt = '2026-10-06T15:42:00+04:00'
      ..canonicalSnapshot = '2026-10-07T11:42:00Z';
    final complete = await source.fetchAll();
    expect(complete.rows.map((row) => row.code), ['A', 'B', 'C']);
    source.offsets.clear();
    source.changeSnapshot = true;
    await expectLater(source.fetchAll(), throwsStateError);
  });

  test('canonical snapshot rejects batches from another version', () async {
    final source = PagedStockSource()
      ..canonicalSnapshot = '2026-10-08T15:42:00+04:00';
    await expectLater(source.fetchAll(), throwsStateError);
  });

  testWidgets('desktop grid shows expiry, filters locally and opens details', (
    tester,
  ) async {
    final source = FakeStockSource();
    await showPage(tester, source, size: const Size(1640, 900));
    expect(tester.takeException(), isNull);
    expect(find.text('MRN Overview'), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-excel-grid')), findsOneWidget);
    expect(find.text('Expiry'), findsOneWidget);
    expect(find.byTooltip('Next page'), findsNothing);
    final dateBadge = find.byKey(const ValueKey('mrn-date:16-01-00362'));
    expect(
      find.descendant(of: dateBadge, matching: find.text('06 Oct 2026')),
      findsOneWidget,
    );
    expect(
      tester.getRect(dateBadge).right,
      lessThan(tester.view.physicalSize.width),
    );
    final initialQueries = source.queries.length;
    await tester.enterText(find.byType(TextField), 'ARTELAC');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(source.queries.length, initialQueries);
    await tester.tap(find.byKey(const ValueKey('mrn-date:16-01-00362')));
    await tester.pumpAndSettle();
    final details = find.byType(StockManagementProductDialog);
    expect(
      find.descendant(
        of: details,
        matching: find.text('ARTELAC ADVANCED SDU EYE DROPS 0.5 ML 30 S'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: details,
        matching: find.text(
          '16-01-00362  ·  LUNATUS DRUG STORE LLC  ·  BAUSCH & LOMB',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Monthly sales'), findsOneWidget);
    expect(find.text('Best month: Sep 2025'), findsOneWidget);
    expect(find.text('Best month: Apr 2026'), findsOneWidget);
    expect(find.textContaining('Reference  IN26217285'), findsOneWidget);
    expect(find.text('Total Sales 2025'), findsOneWidget);
    expect(find.text('Created date  01/01/2025'), findsOneWidget);
    expect(find.text('Total Sales 2026'), findsOneWidget);
    expect(find.text('1,360.33'), findsOneWidget);
    expect(find.text('990.67'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close details'));
    await tester.pumpAndSettle();
  });

  testWidgets('stock totals and status badges share a center line', (
    tester,
  ) async {
    await showPage(tester, FakeStockSource());
    final grid = find.byType(StockManagementGrid);
    Finder cellText(String value) =>
        find.descendant(of: grid, matching: find.text(value));

    final center = tester.getCenter(cellText('1,908.19')).dx;
    for (final label in ['0', 'Below 30 days', 'No Stock']) {
      expect(tester.getCenter(cellText(label)).dx, closeTo(center, 0.5));
    }
  });

  testWidgets('compact layout and filtered state have no overflow', (
    tester,
  ) async {
    final source = FakeStockSource();
    await showPage(tester, source, size: const Size(760, 900));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Below 30 days').first);
    await tester.pumpAndSettle();
    expect(find.text('No date on latest MRN'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Overview has the Near Expiry Excel-style filter controls', (
    tester,
  ) async {
    await showPage(tester, FakeStockSource());
    final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
    expect(grid.allowFiltering, isTrue);
    expect(grid.allowSorting, isTrue);
    expect(grid.allowColumnsResizing, isTrue);
    await tester.tap(
      find.byKey(const ValueKey('datagrid_filtering_item_name_filterIcon')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Text Filters'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('overview focus view expands the register and restores summary', (
    tester,
  ) async {
    await showPage(tester, FakeStockSource());
    final tableBefore = tester.getSize(find.byType(StockManagementGrid)).height;
    await tester.tap(find.byKey(const ValueKey('overview-focus-view')));
    await tester.pumpAndSettle();
    expect(find.text('Show summary'), findsOneWidget);
    expect(find.byType(StockManagementGrid), findsOneWidget);
    expect(
      tester.getSize(find.byType(StockManagementGrid)).height,
      greaterThan(tableBefore),
    );
    await tester.tap(find.byKey(const ValueKey('overview-focus-view')));
    await tester.pumpAndSettle();
    expect(find.text('Expand table'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed load preserves retry without a manual refresh button', (
    tester,
  ) async {
    final source = FakeStockSource()..fail = true;
    await showPage(tester, source);
    expect(find.textContaining('Network unavailable'), findsOneWidget);
    source.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mrn-date:16-01-00362')), findsOneWidget);
    expect(find.text('Refresh data'), findsNothing);
    expect(find.byTooltip('Refresh stock and sales snapshot'), findsNothing);
    expect(source.refreshes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an open overview reloads after an automatic snapshot refresh', (
    tester,
  ) async {
    final source = AutoRefreshStockSource();
    await showPage(tester, source);
    final initialQueries = source.queries.length;

    source.completedAt = source.completedAt.add(const Duration(days: 1));
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();

    expect(source.queries.length, greaterThan(initialQueries));
    expect(tester.takeException(), isNull);
  });

  testWidgets('stock management desktop visual', (tester) async {
    await showPage(tester, FakeStockSource());
    await expectLater(
      find.byType(StockManagementPage),
      matchesGoldenFile('goldens/stock_management_desktop.png'),
    );
  });
}
