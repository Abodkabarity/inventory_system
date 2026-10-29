// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_expiry_grid.dart';
import 'package:daily_order/data/datasources/remote/stock_expiry_remote_ds.dart';
import 'package:daily_order/data/datasources/remote/stock_management_remote_ds.dart';
import 'package:daily_order/domain/entities/stock_management.dart';
import 'package:daily_order/domain/entities/stock_expiry.dart';
import 'package:daily_order/domain/entities/inventory_page.dart';
import 'package:daily_order/core/utils/stock_register_export.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_expiry_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_management_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_management_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'stock_management_test.dart' as stock;

StockExpiryAlert expiryAlert({
  String code = '16-01-00362',
  bool reviewed = false,
  String note = '',
  int days = 25,
  num orderedQty = 30,
  num receivedQty = 25,
  String mrnDate = '2026-10-03',
  String stockStatus = 'low_cover',
}) => StockExpiryAlert({
  'product_data': stock.product(code: code, status: stockStatus).data,
  'item_code': code,
  'item_name': 'artelac advanced sdu eye drops 0.5 ml 30 s',
  'expiry_date': '2026-11-01',
  'days_left': days,
  'supplier': 'Lunatus Drug Store LLC',
  'company': 'Bausch & Lomb',
  'category': 'Medicine',
  'ordered_qty': orderedQty,
  'received_qty': receivedQty,
  'vendor': 'older-vendor-name',
  'total_stock': 1908.19,
  'store_stock': 561,
  'branches_stock': 1347.19,
  'receipt_count': 1,
  'mrn_numbers': '105058',
  'last_receipt_date': mrnDate,
  'receipt_fingerprint': 'receipt-v1',
  'is_reviewed': reviewed,
  'note': note,
  'review_updated_at': null,
  'new_receipts': false,
  'receipts': [
    {
      'mrn_no': '105058',
      'mrn_date': mrnDate,
      'warehouse': 'store',
      'ordered_qty': orderedQty,
      'received_qty': receivedQty,
    },
  ],
});

class FakeExpirySource implements StockExpiryDataSource {
  List<StockExpiryAlert> items = [
    expiryAlert(),
    expiryAlert(code: '16-01-00410', days: -6),
    expiryAlert(
      code: '16-01-00500',
      reviewed: true,
      note: 'Checked with the store',
    ),
  ];
  final queries = <StockExpiryQuery>[];
  final writes = <Map<String, dynamic>>[];
  bool fail = false, failSave = false;
  int revision = 0;
  Map<String, dynamic> get summary => {
    'pending': items.where((a) => !a.reviewed).length,
    'reviewed': items.where((a) => a.reviewed).length,
    'expired': items.where((a) => !a.reviewed && a.days < 0).length,
    'urgent': items
        .where((a) => !a.reviewed && a.days >= 0 && a.days <= 30)
        .length,
    'near_expiry': items.where((a) => !a.reviewed && a.days >= 0).length,
  };
  @override
  Future<StockExpiryResult> fetchPage(StockExpiryQuery query) async {
    queries.add(query);
    if (fail) throw StateError('Network unavailable');
    final filtered = items
        .where(
          (a) =>
              (query.reviewState == 'all' ||
                  (query.reviewState == 'reviewed'
                      ? a.reviewed
                      : !a.reviewed)) &&
              (query.search.isEmpty ||
                  '${a.code} ${a.text('item_name')}'.toLowerCase().contains(
                    query.search.toLowerCase(),
                  )) &&
              (query.urgency.isEmpty ||
                  (query.urgency == 'near'
                      ? a.days >= 0
                      : query.urgency == 'expired'
                      ? a.days < 0
                      : query.urgency == 'urgent'
                      ? a.days >= 0 && a.days <= 30
                      : query.urgency == 'soon'
                      ? a.days > 30 && a.days <= 90
                      : a.days > 90)),
        )
        .toList();
    return StockExpiryResult(
      rows: filtered.skip(query.offset).take(query.limit).toList(),
      total: filtered.length,
      summary: summary,
      meta: const {
        'as_of': '2026-10-08',
        'before': '2027-04-08',
        'window_from': '2026-10-01',
        'window_through': '2026-10-07',
        'receipt_start': '2026-10-01',
        'batch_stock_available': false,
      },
    );
  }

  @override
  Future<StockExpiryAlert> fetchItem(StockExpiryAlert alert) async =>
      items.firstWhere((a) => a.key == alert.key);
  @override
  Future<Map<String, dynamic>> save(
    StockExpiryAlert alert, {
    required String note,
    required String action,
  }) async {
    if (failSave) {
      throw StateError('Another user changed this note. Reload before saving.');
    }
    final index = items.indexWhere((a) => a.key == alert.key);
    if (items[index].reviewVersion != alert.reviewVersion) {
      throw StateError('Review conflict');
    }
    final version =
        '2026-10-07T12:00:${(++revision).toString().padLeft(2, '0')}Z';
    items[index] = StockExpiryAlert({
      ...items[index].data,
      'note': note,
      'is_reviewed': action == 'review'
          ? true
          : action == 'reopen'
          ? false
          : items[index].reviewed,
      'review_updated_at': version,
    });
    writes.add({'action': action, 'note': note, 'key': alert.key});
    return {'updated_at': version};
  }
}

Future<void> showExpiry(
  WidgetTester tester,
  FakeExpirySource source, {
  Size size = const Size(1360, 1000),
  StockManagementDataSource? productSource,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, platform: TargetPlatform.windows),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: StockExpiryPage(
        dataSource: source,
        productDataSource: productSource ?? stock.FakeStockSource(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _MissingProductSource extends stock.FakeStockSource {
  @override
  Future<StockManagementItem> fetchItem(String code) async =>
      throw StateError('No live product snapshot');
}

class _BrokenExpiryBatchSource extends FakeExpirySource {
  final String mode;
  _BrokenExpiryBatchSource(this.mode);
  @override
  Future<StockExpiryResult> fetchPage(StockExpiryQuery query) async {
    final result = await super.fetchPage(query);
    // An older backend may return fewer rows than requested. Keep exercising
    // partial-response failures independently of the configured batch size.
    if (query.offset == 0) {
      return StockExpiryResult(
        rows: result.rows.take(100).toList(),
        total: result.total,
        summary: result.summary,
        meta: result.meta,
      );
    }
    if (mode == 'error') throw StateError('Second batch failed');
    return StockExpiryResult(
      rows: mode == 'empty' ? [] : [items.first],
      total: mode == 'count' ? result.total + 1 : result.total,
      summary: result.summary,
      meta: result.meta,
    );
  }
}

Future<void> tapReview(WidgetTester tester, StockExpiryAlert alert) async {
  final grid = tester.widget<StockExpiryGrid>(find.byType(StockExpiryGrid));
  grid.horizontalController.jumpTo(300);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('review:${alert.key}')));
}

Future<void> revealExpiryNote(WidgetTester tester) async {
  final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
  final beforeNote = grid.columns
      .takeWhile((column) => column.columnName != 'note')
      .fold<double>(0, (width, column) => width + column.width);
  final frozenWidth = grid.columns
      .take(grid.frozenColumnsCount)
      .fold<double>(0, (width, column) => width + column.width);
  grid.horizontalScrollController!.jumpTo(beforeNote - frozenWidth);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'same expiry on separate receipt days keeps separate keys and exports',
    () async {
      final source = FakeExpirySource()
        ..items = [
          expiryAlert(mrnDate: '2026-10-02', receivedQty: 1000),
          expiryAlert(mrnDate: '2026-10-24', receivedQty: 525),
        ];
      final result = await source.fetchAll(const StockExpiryQuery());
      expect(result.rows.map((a) => a.key).toSet(), hasLength(2));
      expect(result.rows.map((a) => stockExpiryExportRow(a)['Total Qty']), [
        1000,
        525,
      ]);
      expect(
        result.rows.map((a) => stockExpiryExportRow(a)['MRN date']).toSet(),
        hasLength(2),
      );
      expect(stockExpiryExportRow(result.rows.last)['MRN number'], '105058');
      await source.save(
        result.rows.last,
        note: 'Check this delivery',
        action: 'review',
      );
      expect(source.items.first.reviewed, isFalse);
      expect(source.items.first.note, isEmpty);
      expect(source.items.last.reviewed, isTrue);
      expect(source.items.last.note, 'Check this delivery');
    },
  );

  testWidgets('near expiry product fields are uppercase and selectable', (
    tester,
  ) async {
    await showExpiry(tester, FakeExpirySource());
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

  testWidgets('same product and expiry show independent MRN day rows', (
    tester,
  ) async {
    final source = FakeExpirySource()
      ..items = [
        expiryAlert(mrnDate: '2026-10-02', receivedQty: 1000),
        expiryAlert(mrnDate: '2026-10-24', receivedQty: 525),
      ];
    await showExpiry(tester, source);
    final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
    expect(grid.source.rows, hasLength(2));
    expect(
      find.byKey(ValueKey('mrn-date:${source.items.first.key}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('mrn-date:${source.items.last.key}')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(ValueKey('expiry-product:${source.items.last.key}')),
    );
    await tester.pumpAndSettle();
    final dialog = tester.widget<StockManagementProductDialog>(
      find.byType(StockManagementProductDialog),
    );
    expect(dialog.receiptDetails!.text('last_mrn_date'), '2026-10-24');
    expect(dialog.receiptDetails!.number('received_quantity'), 525);
    expect(find.text('Receipt evidence (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'detail memory separates MRN days of the same product and expiry',
    () async {
      final dates = <String>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          final name = request.url.path.split('/').last;
          Object data;
          if (name == 'get_stock_workspace_cache_state') {
            data = {
              'expiry': 'v1',
              'details': 'v1',
              'mrn': 'v1',
              'discovery': 'v1',
            };
          } else {
            final date =
                (jsonDecode(request.body) as Map)['p_mrn_date'] as String;
            dates.add(date);
            data = expiryAlert(
              mrnDate: date,
              receivedQty: date == '2026-10-24' ? 525 : 1000,
            ).data;
          }
          return http.Response(
            jsonEncode(data),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final source = StockExpiryRemoteDs(client);
      final older = expiryAlert(mrnDate: '2026-10-02');
      final recent = expiryAlert(mrnDate: '2026-10-24');
      expect((await source.fetchItem(older)).number('received_qty'), 1000);
      expect((await source.fetchItem(recent)).number('received_qty'), 525);
      expect((await source.fetchItem(older)).number('received_qty'), 1000);
      expect(dates, ['2026-10-02', '2026-10-24']);
    },
  );

  testWidgets('near expiry stock values and badges share a center line', (
    tester,
  ) async {
    final source = FakeExpirySource()
      ..items = [
        expiryAlert(code: 'A', stockStatus: 'low_cover'),
        expiryAlert(code: 'B', stockStatus: 'in_stock'),
      ];
    await showExpiry(tester, source, size: const Size(1700, 900));
    final grid = find.byType(StockExpiryGrid);
    tester.widget<StockExpiryGrid>(grid).horizontalController.jumpTo(600);
    await tester.pumpAndSettle();
    Finder cellText(String value) =>
        find.descendant(of: grid, matching: find.text(value));

    final stockNumbers = cellText('1,908.19');
    expect(stockNumbers, findsNWidgets(2));
    final center = tester.getCenter(stockNumbers.first).dx;
    expect(tester.getCenter(stockNumbers.last).dx, closeTo(center, 0.5));
    for (final label in ['Below 30 days', 'In stock']) {
      expect(tester.getCenter(cellText(label)).dx, closeTo(center, 0.5));
    }
  });

  testWidgets('review register defaults to newest MRN date first', (
    tester,
  ) async {
    StockExpiryAlert alert(String code, String mrnDate) => StockExpiryAlert({
      ...expiryAlert(code: code).data,
      'last_receipt_date': mrnDate,
    });
    final source = FakeExpirySource()
      ..items = [
        alert('A', '2026-10-02'),
        alert('B', '2026-10-08'),
        alert('C', '2026-10-06'),
      ];
    await showExpiry(tester, source);

    final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
    final data = grid.source as StockExpiryGridSource;
    expect(data.sortedColumns.single.name, 'last_receipt_date');
    expect(
      data.sortedColumns.single.sortDirection,
      DataGridSortDirection.descending,
    );
    expect(data.effectiveRows.map((row) => data.alertFor(row).code), [
      'B',
      'C',
      'A',
    ]);
  });

  test('expiry label uses calendar months, then remaining days', () {
    expect(
      expiryRemainingLabel(daysLeft: -6, expiryDate: DateTime(2026, 10, 2)),
      '6 days overdue',
    );
    expect(
      expiryRemainingLabel(daysLeft: 0, expiryDate: DateTime(2026, 10, 8)),
      'Expires today',
    );
    expect(
      expiryRemainingLabel(daysLeft: 25, expiryDate: DateTime(2026, 11, 2)),
      '25 days left',
    );
    expect(
      expiryRemainingLabel(daysLeft: 54, expiryDate: DateTime(2026, 12, 1)),
      '1 month · 23 days left',
    );
    expect(
      expiryRemainingLabel(daysLeft: 85, expiryDate: DateTime(2027, 1, 1)),
      '2 months · 24 days left',
    );
    expect(
      expiryRemainingLabel(daysLeft: 59, expiryDate: DateTime(2026, 4, 30)),
      '1 month · 28 days left',
    );
  });

  testWidgets('failed later batch preserves the previously complete register', (
    tester,
  ) async {
    final source = _BrokenExpiryBatchSource('error')
      ..items = List.generate(31, (i) => expiryAlert(code: 'ITEM-$i'));
    await showExpiry(tester, source);
    expect(
      tester.widget<SfDataGrid>(find.byType(SfDataGrid)).source.rows.length,
      31,
    );
    source.items = List.generate(105, (i) => expiryAlert(code: 'ITEM-$i'));
    await tester.tap(find.text('Active'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Second batch failed'), findsOneWidget);
    expect(
      tester.widget<SfDataGrid>(find.byType(SfDataGrid)).source.rows.length,
      31,
    );
    expect(tester.takeException(), isNull);
  });
  test('complete register loads all batches and keeps query filters', () async {
    final source = FakeExpirySource()
      ..items = List.generate(
        10005,
        (i) => expiryAlert(code: 'ITEM-$i', days: 70),
      );
    final progress = <int>[];
    final result = await source.fetchAll(
      const StockExpiryQuery(search: 'ITEM', urgency: 'soon'),
      onProgress: (loaded, total) => progress.add(loaded),
    );
    expect(result.total, 10005);
    expect(result.rows.length, 10005);
    expect(result.rows.map((row) => row.key).toSet().length, 10005);
    expect(source.queries.map((q) => q.offset), [0, 5000, 10000]);
    expect(
      source.queries.every(
        (q) => q.limit == 5000 && q.search == 'ITEM' && q.urgency == 'soon',
      ),
      isTrue,
    );
    expect(progress, [5000, 10000, 10005]);
  });
  for (final mode in ['error', 'empty', 'duplicate', 'count']) {
    test('complete register refuses a partial $mode response', () async {
      final source = _BrokenExpiryBatchSource(mode)
        ..items = List.generate(105, (i) => expiryAlert(code: 'ITEM-$i'));
      await expectLater(
        source.fetchAll(const StockExpiryQuery()),
        throwsStateError,
      );
    });
  }
  test('obsolete register load cancels before making more requests', () async {
    final source = FakeExpirySource();
    await expectLater(
      source.fetchAll(const StockExpiryQuery(), isCancelled: () => true),
      throwsA(isA<StockExpiryLoadCancelled>()),
    );
    expect(source.queries, isEmpty);
  });
  testWidgets(
    'Excel typed filters and sorting keep note actions on the right product',
    (tester) async {
      final source = FakeExpirySource()
        ..items = [
          expiryAlert(code: 'A', days: 10, receivedQty: 10),
          expiryAlert(code: 'B', days: 90, receivedQty: 90),
          expiryAlert(code: 'C', days: 70, receivedQty: 70),
        ];
      await showExpiry(tester, source);
      final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
      final data = grid.source as StockExpiryGridSource;
      expect(
        data.rows.first
            .getCells()
            .singleWhere((c) => c.columnName == 'expiry_date')
            .value,
        isA<DateTime>(),
      );
      expect(
        data.rows.first
            .getCells()
            .singleWhere((c) => c.columnName == 'store_stock')
            .value,
        isA<num>(),
      );
      data.addFilter(
        'received_qty',
        const FilterCondition(type: FilterType.greaterThan, value: 30),
      );
      data.sortedColumns.add(
        const SortColumnDetails(
          name: 'received_qty',
          sortDirection: DataGridSortDirection.descending,
        ),
      );
      await data.sort();
      await tester.pumpAndSettle();
      expect(data.effectiveRows.map((r) => data.alertFor(r).code), ['B', 'C']);
      await tester.tap(
        find.byKey(ValueKey('expiry-product:${source.items[1].key}')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('expiry-note-field')),
        'Checked the filtered product',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      expect(source.items[1].note, 'Checked the filtered product');
      expect(source.items[0].note, '');
      await tester.tap(find.byTooltip('Close details'));
      await tester.pumpAndSettle();
      expect(data.filterConditions['received_qty'], isNotEmpty);
      expect(data.effectiveRows.map((r) => data.alertFor(r).code), ['B', 'C']);
      await tapReview(tester, source.items[1]);
      await tester.pumpAndSettle();
      expect(source.items[1].reviewed, isTrue);
      expect(source.items[0].reviewed, isFalse);
      expect(data.effectiveRows.map((r) => data.alertFor(r).code), ['C']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Excel filter popup opens from a column header', (tester) async {
    await showExpiry(tester, FakeExpirySource());
    await tester.tap(
      find.byKey(const ValueKey('datagrid_filtering_item_name_filterIcon')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Text Filters'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('Excel checkbox filter updates count and can be cleared', (
    tester,
  ) async {
    final source = FakeExpirySource()
      ..items = [
        expiryAlert(code: 'A', days: 10, receivedQty: 10),
        expiryAlert(code: 'B', days: 90, receivedQty: 90),
        expiryAlert(code: 'C', days: 70, receivedQty: 70),
      ];
    await showExpiry(tester, source);
    await tester.tap(
      find.byKey(const ValueKey('datagrid_filtering_received_qty_filterIcon')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Number Filters'), findsOneWidget);
    await tester.tap(find.text('Select All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('90.0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final data =
        tester.widget<SfDataGrid>(find.byType(SfDataGrid)).source
            as StockExpiryGridSource;
    expect(data.effectiveRows.map((r) => data.alertFor(r).code), ['B']);
    expect(
      find.textContaining('expiry groups · Excel column filters'),
      findsNothing,
    );
    expect(find.textContaining('Register since'), findsNothing);
    expect(find.byTooltip('Reload expiry alerts'), findsNothing);
    expect(find.text('Refresh'), findsNothing);
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(data.filterConditions, isEmpty);
    expect(data.effectiveRows.length, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expiry palette follows day boundaries and not review state', (
    tester,
  ) async {
    final cases = <(int, Color)>[
      (-1, const Color(0xFF9F2339)),
      (0, const Color(0xFFC63E55)),
      (30, const Color(0xFFC63E55)),
      (60, const Color(0xFFC63E55)),
      (61, const Color(0xFFC45A15)),
      (90, const Color(0xFFC45A15)),
      (91, const Color(0xFF96700E)),
      (179, const Color(0xFF96700E)),
    ];
    final source = FakeExpirySource()
      ..items = [
        for (final c in cases) expiryAlert(code: 'day-${c.$1}', days: c.$1),
        expiryAlert(code: 'reviewed-red', days: 60, reviewed: true),
      ];
    await showExpiry(tester, source, size: const Size(1650, 1300));
    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await tester.pumpAndSettle();
    final gridSource =
        tester.widget<SfDataGrid>(find.byType(SfDataGrid)).source
            as StockExpiryGridSource;
    for (final c in cases) {
      final row = gridSource.rows.singleWhere(
        (r) => gridSource.alertFor(r).code == 'day-${c.$1}',
      );
      expect(gridSource.riskColor(gridSource.alertFor(row)), c.$2);
      expect(gridSource.buildRow(row).color, isNot(Colors.white));
    }
    final reviewed = gridSource.rows.singleWhere(
      (r) => gridSource.alertFor(r).code == 'reviewed-red',
    );
    expect(
      gridSource.riskColor(gridSource.alertFor(reviewed)),
      const Color(0xFFC63E55),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop gives six full rows and focus view gives seven', (
    tester,
  ) async {
    final source = FakeExpirySource()
      ..items = List.generate(20, (i) => expiryAlert(code: 'item-$i'));
    await showExpiry(tester, source, size: const Size(1650, 870));
    final list = find.byType(SfDataGrid);
    final table = tester.widget<SfDataGrid>(list);
    final initialHeight = tester.getSize(list).height;
    expect(
      initialHeight - table.headerRowHeight,
      greaterThanOrEqualTo(6 * table.rowHeight + 14),
    );
    final queryCount = source.queries.length;
    await tester.tap(find.byKey(const ValueKey('expiry-focus-view')));
    await tester.pumpAndSettle();
    expect(tester.getSize(list).height, greaterThan(initialHeight + 60));
    expect(
      tester.getSize(list).height,
      greaterThanOrEqualTo(7 * table.rowHeight + table.headerRowHeight + 14),
    );
    expect(find.text('Near Expiry'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(source.queries.length, queryCount);
    await tester.tap(find.byKey(const ValueKey('expiry-focus-view')));
    await tester.pumpAndSettle();
    expect(tester.getSize(list).height, initialHeight);
    expect(find.text('Near Expiry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('warm register fits a shorter window with enlarged text', (
    tester,
  ) async {
    final source = FakeExpirySource();
    await showExpiry(
      tester,
      source,
      size: const Size(760, 700),
      textScale: 1.2,
    );
    expect(find.text('Review register'), findsOneWidget);
    expect(find.byType(SfDataGrid), findsOneWidget);
    await revealExpiryNote(tester);
    expect(find.text('Note / details'), findsWidgets);
  });

  testWidgets(
    'a missing live snapshot never hides an alert or blocks its note',
    (tester) async {
      final source = FakeExpirySource()
        ..items = [
          StockExpiryAlert({
            ...expiryAlert().data,
            'stock_snapshot_missing': true,
            'product_data': {
              'item_code': '16-01-00362',
              'item_name': 'Saved product',
              'stock_unavailable': true,
              'last_mrn_date': '2026-10-06',
              'last_mrn_no': '105058',
              'last_mrn_qty': 25,
            },
          }),
        ];
      await showExpiry(tester, source, productSource: _MissingProductSource());
      final gridSource = tester
          .widget<SfDataGrid>(find.byType(SfDataGrid))
          .source;
      final cells = gridSource.rows.single.getCells();
      expect(
        cells.singleWhere((c) => c.columnName == 'total_stock').value,
        isNull,
      );
      expect(
        cells.singleWhere((c) => c.columnName == 'sales_2025').value,
        isNull,
      );
      expect(
        cells.singleWhere((c) => c.columnName == 'sales_2026').value,
        isNull,
      );
      await revealExpiryNote(tester);
      await tester.tap(find.text('Note / details'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Live product details unavailable'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('expiry-review-badges')),
          matching: find.text('Product stock unavailable'),
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('expiry-note-field')),
        'Check the saved batch evidence',
      );
      await tester.pump();
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      expect(source.items.single.note, 'Check the saved batch evidence');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'stock workspace dropdown has independent overview and expiry navigation',
    (tester) async {
      var selected = InventoryPageType.stockManagement;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 290,
                child: StatefulBuilder(
                  builder: (context, update) => StockManagementNavigation(
                    selectedPage: selected,
                    onSelected: (page) => update(() => selected = page),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Stock Management'), findsOneWidget);
      expect(find.text('Overview'), findsOneWidget);
      await tester.tap(find.text('Near Expiry'));
      await tester.pumpAndSettle();
      expect(selected, InventoryPageType.nearExpiry);
      await tester.tap(find.text('Stock Management'));
      await tester.pumpAndSettle();
      expect(find.text('Near Expiry'), findsNothing);
      await tester.tap(find.text('Stock Management'));
      await tester.pumpAndSettle();
      expect(find.text('Near Expiry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expiry uses Daily Order grid and the same complete product dialog',
    (tester) async {
      final source = FakeExpirySource();
      await showExpiry(tester, source);
      expect(source.queries.first.urgency, '');
      expect(find.byType(SfDataGrid), findsOneWidget);
      final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
      expect(grid.source.rows.length, 2);
      expect(grid.allowFiltering, isTrue);
      expect(grid.allowSorting, isTrue);
      expect(grid.allowColumnsResizing, isTrue);
      for (final column in [
        'last_receipt_date',
        'expiry_date',
        'ordered_qty',
        'received_qty',
        'note',
        'total_stock',
        'store_stock',
        'branches_stock',
        'days_on_hand',
        'sales_2025',
        'sales_2026',
        'supplier',
        'company',
        'category',
        'best_month_2025',
        'best_month_2026',
      ]) {
        expect(grid.columns.any((c) => c.columnName == column), isTrue);
      }
      expect(grid.columns.any((c) => c.columnName == 'days_left'), isFalse);
      final orderedIndex = grid.columns.indexWhere(
        (column) => column.columnName == 'ordered_qty',
      );
      expect(grid.columns[orderedIndex + 1].columnName, 'received_qty');
      for (final column in [
        'cash_2025',
        'insurance_2025',
        'online_2025',
        'cash_2026',
        'insurance_2026',
        'online_2026',
        'best_qty_2025',
        'best_qty_2026',
      ]) {
        expect(grid.columns.any((c) => c.columnName == column), isFalse);
      }
      expect(find.text('6 days overdue'), findsOneWidget);
      expect(find.text('03 Oct 2026'), findsNWidgets(2));
      expect(find.text('Latest: 06 Oct 2026'), findsNWidgets(2));
      expect(
        tester
            .getRect(find.byKey(ValueKey('mrn-date:${source.items.first.key}')))
            .right,
        lessThan(tester.view.physicalSize.width),
      );
      await tester.tap(
        find.text('ARTELAC ADVANCED SDU EYE DROPS 0.5 ML 30 S').first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(StockManagementProductDialog), findsOneWidget);
      final details = find.byType(StockManagementProductDialog);
      expect(
        find.descendant(
          of: details,
          matching: find.text('ARTELAC ADVANCED SDU EYE DROPS 0.5 ML 30 S'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: details, matching: find.text('SKU 16-01-00362')),
        findsOneWidget,
      );
      expect(find.textContaining('Reference  IN26217285'), findsOneWidget);
      expect(find.text('Annual sales mix'), findsOneWidget);
      expect(find.text('MRN receipt details'), findsNothing);
      expect(find.byKey(const ValueKey('mrn-receipt-cards')), findsOneWidget);
      expect(find.text('1,360.33'), findsWidgets);
      expect(find.text('990.67'), findsWidgets);
      for (final label in [
        'Monthly sales & momentum',
        'Branch intelligence',
        'AL AIN MAIN',
        'Review note',
        'Save & mark reviewed',
        'Expiry 01 Nov 2026',
      ]) {
        expect(find.text(label), findsWidgets);
      }
      expect(find.byKey(const ValueKey('expiry-note-field')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'RPC filters and review concurrency parameters are transmitted',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          final data = request.url.path.endsWith('get_stock_expiry_page')
              ? {
                  'rows': [expiryAlert().data],
                  'total': 1,
                  'summary': {},
                  'meta': {},
                }
              : request.url.path.endsWith('get_stock_expiry_item')
              ? expiryAlert().data
              : {'updated_at': '2026-10-07T12:01:00Z'};
          return http.Response(
            jsonEncode(data),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final source = StockExpiryRemoteDs(client);
      final result = await source.fetchPage(
        const StockExpiryQuery(
          search: ' eye ',
          reviewState: 'reviewed',
          urgency: 'soon',
          offset: 30,
        ),
      );
      expect(requests.first.url.path, endsWith('refresh_stock_expiry_watch'));
      expect(jsonDecode(requests.last.body), {
        'p_search': 'eye',
        'p_review_state': 'reviewed',
        'p_urgency': 'soon',
        'p_offset': 30,
        'p_limit': 30,
      });
      expect(result.rows.single.days, 25);
      final alert = await source.fetchItem(result.rows.single);
      expect(jsonDecode(requests.last.body), {
        'p_item_code': alert.code,
        'p_expiry_date': alert.expiry,
        'p_mrn_date': '2026-10-03',
      });
      await source.save(
        alert,
        note: 'Follow up with supplier',
        action: 'review',
      );
      expect(jsonDecode(requests.last.body), {
        'p_item_code': alert.code,
        'p_expiry_date': '2026-11-01',
        'p_mrn_date': '2026-10-03',
        'p_fingerprint': 'receipt-v1',
        'p_note': 'Follow up with supplier',
        'p_action': 'review',
        'p_expected_updated_at': null,
      });
    },
  );
  testWidgets('notes persist and reviewed alerts can be reopened', (
    tester,
  ) async {
    final source = FakeExpirySource();
    await showExpiry(tester, source);
    expect(tester.takeException(), isNull);
    await revealExpiryNote(tester);
    await tester.tap(find.text('Note / details').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('expiry-note-field')),
      'Return planned with supplier',
    );
    await tester.pump();
    await tester.tap(find.text('Save note'));
    await tester.pumpAndSettle();
    expect(source.items.first.note, 'Return planned with supplier');
    expect(find.text('Saved'), findsOneWidget);
    await tester.tap(find.byTooltip('Close details'));
    await tester.pumpAndSettle();
    expect(find.text('View note'), findsOneWidget);
    await tapReview(tester, source.items.first);
    await tester.pumpAndSettle();
    expect(source.items.first.reviewed, isTrue);
    expect(
      find.byKey(ValueKey('review:${source.items.first.key}')),
      findsNothing,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Reviewed'));
    await tester.pumpAndSettle();
    expect(find.text('View note'), findsAtLeastNWidgets(1));
    await tapReview(tester, source.items.first);
    await tester.pumpAndSettle();
    expect(source.items.first.reviewed, isFalse);
    expect(source.items.first.note, 'Return planned with supplier');
    expect(tester.takeException(), isNull);
  });
  testWidgets('review undo restores the active alarm', (tester) async {
    final source = FakeExpirySource();
    await showExpiry(tester, source);
    await tapReview(tester, source.items.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(source.items.first.reviewed, isFalse);
    expect(
      find.byKey(ValueKey('review:${source.items.first.key}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('compact grid loads all 31 rows without UI pagination', (
    tester,
  ) async {
    final source = FakeExpirySource()
      ..items = List.generate(31, (i) => expiryAlert(code: 'ITEM-$i'));
    await showExpiry(tester, source, size: const Size(760, 1000));
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Next expiry page'), findsNothing);
    expect(
      tester.widget<SfDataGrid>(find.byType(SfDataGrid)).source.rows.length,
      31,
    );
    expect(source.queries.single.limit, 5000);
    await tester.enterText(find.byType(TextField), 'ITEM-3');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(source.queries.last.offset, 0);
    expect(source.queries.last.search, 'ITEM-3');
    await tester.tap(find.text('Within 30 days'));
    await tester.pumpAndSettle();
    expect(source.queries.last.urgency, 'urgent');
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed save keeps typed note and does not clear the alarm', (
    tester,
  ) async {
    final source = FakeExpirySource()..failSave = true;
    await showExpiry(tester, source);
    await revealExpiryNote(tester);
    await tester.tap(find.text('Note / details').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('expiry-note-field')),
      'My unsaved note',
    );
    await tester.tap(find.text('Save & mark reviewed'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Another user changed this note'),
      findsOneWidget,
    );
    expect(find.text('My unsaved note'), findsOneWidget);
    expect(source.items.first.reviewed, isFalse);
    await tester.tap(find.byTooltip('Close details'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved note?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('My unsaved note'), findsOneWidget);
    expect(tester.takeException(), isNull);
    source.failSave = false;
    await tester.tap(find.text('Save & mark reviewed'));
    await tester.pumpAndSettle();
    expect(source.items.first.reviewed, isTrue);
    expect(source.items.first.note, 'My unsaved note');
  });
  testWidgets('load failure can retry and expired card filters separately', (
    tester,
  ) async {
    final source = FakeExpirySource()..fail = true;
    await showExpiry(tester, source);
    expect(find.textContaining('Network unavailable'), findsOneWidget);
    source.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expired dates'));
    await tester.pumpAndSettle();
    expect(source.queries.last.urgency, 'expired');
    expect(find.text('6 days overdue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unsaved notes can be discarded without affecting stored data', (
    tester,
  ) async {
    final source = FakeExpirySource();
    await showExpiry(tester, source);
    await revealExpiryNote(tester);
    await tester.tap(find.text('Note / details').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('expiry-note-field')),
      'Do not save this',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Close details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('expiry-note-field')), findsNothing);
    expect(source.items.first.note, '');
    expect(source.items.first.reviewed, isFalse);
    expect(source.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stock Management card opens a separate expiry page', (
    tester,
  ) async {
    final expiry = FakeExpirySource();
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: StockManagementPage(
            dataSource: stock.FakeStockSource(),
            expiryDataSource: expiry,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Near Expiry ·').first);
    await tester.pumpAndSettle();
    expect(find.text('Stock Management / Near Expiry'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to Stock Management'));
    await tester.pumpAndSettle();
    expect(find.text('MRN Overview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
