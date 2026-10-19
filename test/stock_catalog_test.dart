import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:daily_order/core/utils/stock_catalog_export.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/data/datasources/remote/stock_catalog_remote_ds.dart';
import 'package:daily_order/domain/entities/stock_catalog.dart';
import 'package:daily_order/domain/entities/inventory_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_catalog_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_catalog_product_dialog.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_catalog_grid.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_catalog_visuals.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_management_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

StockCatalogItem fixture() => StockCatalogItem(
  jsonDecode(File('test/data/stock_catalog_product.json').readAsStringSync())
      as Map<String, dynamic>,
);

class FakeCatalog extends StockCatalogDataSource {
  final queries = <StockCatalogQuery>[];
  final itemStatuses = <String>[];
  bool fail = false;
  int detailCalls = 0;
  String? lastDetailCode;
  int refreshes = 0;
  String? status;
  Completer<StockCatalogResult>? pending;
  @override
  Future<StockCatalogResult> fetchPage(StockCatalogQuery query) async {
    queries.add(query);
    if (fail) throw StateError('Disconnected');
    if (pending != null) return pending!.future;
    final item = fixture();
    return StockCatalogResult.fromMap({
      'rows': [
        for (var i = 0; i < 8; i++)
          {
            ...item.data,
            if (itemStatuses.isNotEmpty)
              'item_status': itemStatuses[i % itemStatuses.length],
            'item_code': '${item.code}-$i',
            'item_name': i == 0
                ? item.name
                : [
                    'JULMENTIN 1 G TABS 15 S',
                    'AZI-ONCE 250 MG CAP 6 S',
                    'ARTELAC ADVANCED EYE DROPS',
                    'PARACETAMOL 500 MG TABS',
                  ][i % 4],
            'demand_surge': i % 3 == 0,
            'growth_percent': i % 3 == 0 ? 1571.9 : 74.78,
            'last_3_sales': i % 3 == 0 ? 199 : 102,
          },
      ].skip(query.offset).take(query.limit).toList(),
      'summary': {'items': 8, 'surge': 504, 'shortage': 1691, 'low_cover': 980},
      'meta': item.data['meta'],
      'categories': [item.text('category')],
      'suppliers': [item.text('supplier')],
    });
  }

  @override
  Future<StockCatalogItem> fetchItem(String code) async {
    detailCalls++;
    lastDetailCode = code;
    return fixture();
  }

  @override
  Future<void> requestRefresh() async {
    refreshes++;
    status = 'queued';
  }

  @override
  Future<Map<String, dynamic>?> refreshState() async =>
      status == null ? null : {'status': status};
}

class MultiBatchCatalog extends FakeCatalog {
  bool changed = false;
  final offsets = <int>[];
  @override
  Future<StockCatalogResult> fetchPage(StockCatalogQuery query) async =>
      StockCatalogResult(
        rows: const [],
        summary: const {'items': 151},
        meta: const {'refreshed_at': 'snapshot-1'},
      );
  @override
  Future<StockCatalogRegisterBatch> fetchRegisterBatch(int offset) async {
    offsets.add(offset);
    return StockCatalogRegisterBatch(
      rows: [
        for (var i = offset; i < 151 && i < offset + 100; i++)
          StockCatalogItem({'item_code': '$i'}),
      ],
      total: 151,
      snapshotAt: changed && offset > 0 ? 'snapshot-2' : 'snapshot-1',
    );
  }
}

Future<void> app(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1440, 900),
  GlobalKey? boundary,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          platform: TargetPlatform.windows,
          useMaterial3: true,
          fontFamily: Platform.environment['CATALOG_FONT_ROOT'] == null
              ? null
              : 'Roboto',
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF069D95)),
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['UPDATE_CATALOG_PREVIEW'] != '1') return;
  await tester.runAsync(() async {
    final render =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('validation').create();
    await File(
      'validation/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  test(
    'continuous register includes every batch and rejects a mixed snapshot',
    () async {
      final source = MultiBatchCatalog();
      final progress = <int>[];
      final result = await source.fetchAll(
        onProgress: (loaded, total) => progress.add(loaded),
      );
      expect(result.rows.length, 151);
      expect(result.rows.last.code, '150');
      expect(source.offsets, [0, 100]);
      expect(progress, [100, 151]);
      await expectLater(
        (MultiBatchCatalog()..changed = true).fetchAll(),
        throwsStateError,
      );
    },
  );
  setUpAll(() async {
    final root = Platform.environment['CATALOG_FONT_ROOT'];
    if (root == null) return;
    final font = FontLoader('Roboto');
    for (final name in ['roboto-regular.ttf', 'roboto-bold.ttf']) {
      font.addFont(
        Future.value(
          ByteData.sublistView(File('$root/$name').readAsBytesSync()),
        ),
      );
    }
    await font.load();
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
    'coverage, signed returns, no baseline and percentage ratio remain truthful',
    () {
      final item = StockCatalogItem({
        'branches_stock': 75,
        'store_stock': 25,
        'total_stock': 100,
        'recent_sales': 101,
        'days_on_hand': 45,
        'growth_percent': null,
      });
      expect(item.branchesStorePercent, 300);
      expect(item.salesExceedStock, isTrue);
      expect(item.growth, isNull);
      expect(StockCatalogItem({'store_stock': 0}).branchesStorePercent, isNull);
      final branches = catalogBranchRows(
        StockCatalogItem({
          'meta': {'baseline_days': 42, 'recent_days': 3},
          'branches': [
            {'stock': 100, 'recent_sales': 90, 'baseline_sales': 84},
            {'stock': 10, 'recent_sales': -2, 'baseline_sales': -4},
            {'stock': 0, 'recent_sales': 5},
          ],
        }),
      );
      expect(branches[0]['cover'], 50);
      expect(branches[0]['baseline_daily'], 2);
      expect(branches[1]['cover'], isNull);
      expect(branches[1]['baseline_daily'], closeTo(-4 / 42, 1e-10));
      expect(branches[2]['cover'], 0);
    },
  );
  test(
    'monthly moving average includes missing calendar months and signed returns',
    () {
      final series = catalogMonthlySeries(
        const StockCatalogItem({
          'monthly_sales': [
            {'month': '01/2025', 'total': 120},
            {'month': '03/2025', 'total': -30},
          ],
          'meta': {'sales_2026_through': '2025-03-01'},
        }),
      );
      expect(series.length, 3);
      expect(series[1]['total'], 0);
      expect(catalogMovingAverage(series), [null, null, 30]);
    },
  );
  test(
    'CSV decorates only authoritative 71 branches, preserves identities and totals',
    () {
      StoreBranchIdentityRegistry.groups.value = {
        'AL AIN': '71',
        'CITY': 'APG',
      };
      final raw = [
        {'branch': 'AL AIN', 'stock': 23.5},
        {'branch': 'CITY', 'stock': 8.0},
      ];
      final csv = catalogCsv(raw);
      expect(csv, contains('71 AL AIN'));
      expect(csv, contains('CITY'));
      expect(csv, contains('23.5'));
      expect(raw.first['branch'], 'AL AIN');
      final exported = catalogExportRow(fixture());
      expect(exported['Item status'], fixture().itemStatus);
      expect(
        exported['APG stock'],
        fixture().number('store_stock') +
            fixture().number('apg_branches_stock') +
            fixture().number('stock_71'),
      );
    },
  );
  testWidgets(
    'desktop Overview shows one continuous register with compact cards and local filters',
    (tester) async {
      final source = FakeCatalog();
      final key = GlobalKey();
      await app(tester, StockCatalogPage(dataSource: source), boundary: key);
      expect(tester.takeException(), isNull);
      expect(find.text('Overview'), findsOneWidget);
      expect(source.detailCalls, 0);
      expect(source.queries.first.limit, 1);
      expect(source.queries.last.limit, 100);
      expect(find.byTooltip('Next page'), findsNothing);
      expect(find.byTooltip('Previous page'), findsNothing);
      expect(find.text('Page 1'), findsNothing);
      final grid = find.byKey(const ValueKey('stock-catalog-grid'));
      expect(tester.getRect(grid).top, lessThan(300));
      expect(tester.getRect(grid).bottom, greaterThan(875));
      await capture(tester, key, 'stock_catalog_desktop');
      await tester.tap(find.byTooltip('Choose Category'));
      await tester.pumpAndSettle();
      await capture(tester, key, 'stock_catalog_filter_menu');
      await tester.tap(find.text(fixture().text('category')).last);
      await tester.pumpAndSettle();
      expect(source.queries.length, 2);
      await tester.tap(find.byTooltip('Clear filters'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'SELTAFLU');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(source.queries.length, 2);
      expect(find.text('AZI-ONCE 250 MG CAP 6 S'), findsNothing);
      await tester.tap(find.text('SALES INCREASE'));
      await tester.pumpAndSettle();
      expect(source.queries.length, 2);
      await tester.tap(find.text(fixture().name).first);
      await tester.pumpAndSettle();
      expect(source.detailCalls, 1);
      expect(find.text('Monthly sales & momentum'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(StockCatalogProductDialog),
          matching: find.text('01/01/2025'),
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close details'));
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'Item Status filters the full register and sorts both ways with blanks last',
    (tester) async {
      final source = FakeCatalog()
        ..itemStatuses.addAll([
          '2#SPECIAL PURCHASE',
          ' 1#NORMAL PURCHASE ',
          '',
        ]);
      await app(tester, StockCatalogPage(dataSource: source));
      List<StockCatalogItem> rows() =>
          tester.widget<StockCatalogGrid>(find.byType(StockCatalogGrid)).items;
      expect(find.text('Item status A–Z'), findsOneWidget);
      expect(rows().map((item) => item.itemStatus), [
        ...List.filled(3, '1#NORMAL PURCHASE'),
        ...List.filled(3, '2#SPECIAL PURCHASE'),
        '',
        '',
      ]);
      Future<void> choose(String label, String value) async {
        await tester.tap(find.byTooltip('Choose $label'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(value).last);
        await tester.pumpAndSettle();
      }

      await choose('Item Status', '1#NORMAL PURCHASE');
      expect(rows().length, 3);
      expect(
        rows().every((item) => item.itemStatus == '1#NORMAL PURCHASE'),
        isTrue,
      );
      expect(find.text('MATCHING PRODUCTS'), findsOneWidget);
      // Status options remain available after filtering to another status.
      await choose('Item Status', '2#SPECIAL PURCHASE');
      expect(rows().length, 3);
      await choose('Item Status', '1#NORMAL PURCHASE');
      await tester.enterText(find.byType(TextField).first, 'AZI-ONCE');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(rows().single.name, 'AZI-ONCE 250 MG CAP 6 S');
      await tester.enterText(find.byType(TextField).first, 'ARTELAC');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('No products match these filters.'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear filters'));
      await tester.pumpAndSettle();
      expect(rows().length, 8);
      await choose('Item Status', 'Not specified');
      expect(rows().length, 2);
      expect(rows().every((item) => item.itemStatus.isEmpty), isTrue);
      await choose('Item Status', 'All statuses');
      await choose('Sort', 'Item status A–Z');
      expect(rows().map((item) => item.itemStatus), [
        ...List.filled(3, '1#NORMAL PURCHASE'),
        ...List.filled(3, '2#SPECIAL PURCHASE'),
        '',
        '',
      ]);
      expect(rows().take(3).map((item) => item.name), [
        'AZI-ONCE 250 MG CAP 6 S',
        'JULMENTIN 1 G TABS 15 S',
        'PARACETAMOL 500 MG TABS',
      ]);
      await choose('Sort', 'Item status Z–A');
      expect(rows().map((item) => item.itemStatus), [
        ...List.filled(3, '2#SPECIAL PURCHASE'),
        ...List.filled(3, '1#NORMAL PURCHASE'),
        '',
        '',
      ]);
      await tester.tap(find.byTooltip('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('Item status A–Z'), findsOneWidget);
      expect(
        rows().take(3).every((item) => item.itemStatus == '1#NORMAL PURCHASE'),
        isTrue,
      );
      expect(source.queries.length, 2);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Excel column filters combine with search, survive sorting and open the correct product',
    (tester) async {
      final source = FakeCatalog()
        ..itemStatuses.addAll(['2#SPECIAL PURCHASE', '1#NORMAL PURCHASE', '']);
      final key = GlobalKey();
      await app(tester, StockCatalogPage(dataSource: source), boundary: key);
      StockCatalogGridState state() =>
          tester.state<StockCatalogGridState>(find.byType(StockCatalogGrid));
      await tester.tap(
        find.byKey(const ValueKey('datagrid_filtering_product_filterIcon')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Text Filters'), findsOneWidget);
      await capture(tester, key, 'stock_catalog_excel_text_filter');
      await tester.enterText(
        find.byKey(const ValueKey('datagrid_filtering_search_textfield')),
        'AZI-ONCE',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(state().visibleItems.length, 2);
      expect(find.text('MATCHING PRODUCTS'), findsOneWidget);
      final filteredCodes = state().visibleItems.map((r) => r.code).toList();
      await tester.tap(find.text('AZI-ONCE 250 MG CAP 6 S').last);
      await tester.pumpAndSettle();
      expect(source.lastDetailCode, filteredCodes.last);
      await tester.tap(find.byTooltip('Close details'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'JULMENTIN');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(state().visibleItems, isEmpty);
      expect(find.text('No products match these filters.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(state().visibleItems.map((r) => r.code), filteredCodes);
      await tester.tap(find.byTooltip('Choose Sort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Highest growth'));
      await tester.pumpAndSettle();
      expect(state().visibleItems.length, 2);
      final csv = catalogCsv(
        state().visibleItems.map(catalogExportRow).toList(),
      );
      expect(csv, contains('AZI-ONCE'));
      expect(csv, isNot(contains('ARTELAC')));
      await tester.tap(find.byTooltip('Clear filters'));
      await tester.pumpAndSettle();
      expect(state().visibleItems.length, 8);
      expect(find.text('ALL PRODUCTS'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('datagrid_filtering_item_status_filterIcon')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('datagrid_filtering_search_textfield')),
        '1#NORMAL',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(state().visibleItems.length, 3);
      expect(
        state().visibleItems.every((r) => r.itemStatus == '1#NORMAL PURCHASE'),
        isTrue,
      );
      expect(source.queries.length, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Excel numeric filters use quantities, retain nulls and survive data updates',
    (tester) async {
      final key = GlobalKey<StockCatalogGridState>();
      final boundary = GlobalKey();
      final items = [
        const StockCatalogItem({
          'item_code': '900',
          'item_name': 'ALPHA',
          'total_stock': 2,
          'growth_percent': 3,
        }),
        const StockCatalogItem({
          'item_code': '1',
          'item_name': 'BETA',
          'total_stock': 10,
          'growth_percent': 5,
        }),
        const StockCatalogItem({
          'item_code': '5',
          'item_name': 'GAMMA',
          'total_stock': 100,
          'growth_percent': null,
        }),
      ];
      StockCatalogItem? opened;
      await app(
        tester,
        StockCatalogGrid(
          key: key,
          items: items,
          onOpen: (item) => opened = item,
        ),
        boundary: boundary,
      );
      final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
      grid.horizontalScrollController!.jumpTo(180);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('datagrid_filtering_total_stock_filterIcon')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Number Filters'), findsOneWidget);
      await capture(tester, boundary, 'stock_catalog_excel_number_filter');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      grid.source.addFilter(
        'total_stock',
        const FilterCondition(
          type: FilterType.greaterThan,
          value: 9,
          filterOperator: FilterOperator.and,
        ),
      );
      grid.source.addFilter(
        'total_stock',
        const FilterCondition(
          type: FilterType.lessThan,
          value: 100,
          filterOperator: FilterOperator.and,
        ),
      );
      await tester.pumpAndSettle();
      expect(key.currentState!.visibleItems.single.code, '1');
      await tester.tap(find.text('BETA'));
      await tester.pumpAndSettle();
      expect(opened?.code, '1');
      final updated = [
        ...items,
        const StockCatalogItem({
          'item_code': '8',
          'item_name': 'DELTA',
          'total_stock': 50,
        }),
      ];
      await app(
        tester,
        StockCatalogGrid(
          key: key,
          items: updated,
          onOpen: (item) => opened = item,
        ),
        boundary: boundary,
      );
      expect(key.currentState!.visibleItems.map((r) => r.code), ['1', '8']);
      final updatedGrid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
      updatedGrid.source.sortedColumns.add(
        const SortColumnDetails(
          name: 'total_stock',
          sortDirection: DataGridSortDirection.descending,
        ),
      );
      await updatedGrid.source.sort();
      await tester.pumpAndSettle();
      expect(key.currentState!.visibleItems.map((r) => r.code), ['8', '1']);
      await tester.tap(find.text('DELTA'));
      await tester.pumpAndSettle();
      expect(opened?.code, '8');
      key.currentState!.clearFilters();
      updatedGrid.source.addFilter(
        'growth',
        const FilterCondition(type: FilterType.equals, value: null),
      );
      await tester.pumpAndSettle();
      expect(key.currentState!.visibleItems.map((r) => r.code).toSet(), {
        '5',
        '8',
      });
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Growth distinguishes decrease, increase, zero, unavailable and new sales',
    (tester) async {
      const cases = [
        (-44.0, false, 'Sales decreasing'),
        (200.0, false, 'Sales increasing'),
        (0.0, false, 'Sales unchanged'),
        (null, false, 'Growth unavailable'),
        (null, true, 'Sales increasing'),
      ];
      final boundary = GlobalKey();
      await app(
        tester,
        Center(
          child: Wrap(
            spacing: 12,
            children: [
              for (var i = 0; i < cases.length; i++)
                SizedBox(
                  width: 220,
                  child: CatalogGrowthMetric(
                    key: ValueKey('growth-case-$i'),
                    item: StockCatalogItem({
                      'growth_percent': cases[i].$1,
                      'new_demand': cases[i].$2,
                    }),
                  ),
                ),
            ],
          ),
        ),
        size: const Size(1240, 210),
        boundary: boundary,
      );
      Finder card(int i) => find.byKey(ValueKey('growth-case-$i'));
      Finder within(int i, Finder match) =>
          find.descendant(of: card(i), matching: match);
      for (var i = 0; i < cases.length; i++) {
        expect(within(i, find.byTooltip(cases[i].$3)), findsOneWidget);
        expect(tester.getSize(card(i)).height, tester.getSize(card(0)).height);
      }
      expect(
        within(0, find.byIcon(Icons.trending_down_rounded)),
        findsOneWidget,
      );
      expect(within(0, find.text('-44.0%')), findsOneWidget);
      final decrease = tester.widget<CatalogMetric>(
        within(0, find.byType(CatalogMetric)),
      );
      expect(decrease.color.r, greaterThan(decrease.color.g));
      expect(within(1, find.byIcon(Icons.trending_up_rounded)), findsOneWidget);
      final increase = tester.widget<CatalogMetric>(
        within(1, find.byType(CatalogMetric)),
      );
      expect(increase.color.g, greaterThan(increase.color.r));
      expect(within(2, find.byIcon(Icons.trending_up_rounded)), findsNothing);
      expect(within(2, find.byIcon(Icons.trending_down_rounded)), findsNothing);
      expect(within(2, find.byType(CustomPaint)), findsWidgets);
      expect(within(2, find.text('0.0%')), findsOneWidget);
      expect(
        tester
            .widget<CatalogMetric>(within(2, find.byType(CatalogMetric)))
            .color,
        catalogOrange,
      );
      expect(within(3, find.text('—')), findsOneWidget);
      expect(within(3, find.byIcon(Icons.more_horiz_rounded)), findsOneWidget);
      expect(within(4, find.text('New demand')), findsOneWidget);
      expect(within(4, find.byIcon(Icons.trending_up_rounded)), findsOneWidget);
      expect(tester.takeException(), isNull);
      await capture(tester, boundary, 'stock_catalog_growth_states');
      // Match the one-decimal display so a rounded zero never looks negative.
      await app(
        tester,
        const Center(
          child: SizedBox(
            width: 220,
            child: CatalogGrowthMetric(
              item: StockCatalogItem({'growth_percent': -0.01}),
            ),
          ),
        ),
        size: const Size(1240, 210),
      );
      expect(find.text('0.0%'), findsOneWidget);
      expect(find.byTooltip('Sales unchanged'), findsOneWidget);
      expect(find.byIcon(Icons.trending_down_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('compact Overview and product dialog render without overflow', (
    tester,
  ) async {
    final source = FakeCatalog();
    final key = GlobalKey();
    await app(
      tester,
      StockCatalogPage(dataSource: source),
      size: const Size(430, 900),
      boundary: key,
    );
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'stock_catalog_compact');
    await tester.tap(
      find.byKey(const ValueKey('datagrid_filtering_product_filterIcon')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Text Filters'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, key, 'stock_catalog_excel_compact_filter');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ARTELAC ADVANCED EYE DROPS').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Created date  01/01/2025'), findsOneWidget);
    expect(
      tester.getRect(find.byKey(const ValueKey('product-created-at'))).top,
      lessThan(250),
    );
    await capture(tester, key, 'stock_catalog_product_compact');
    await tester.tap(find.byTooltip('Close details'));
    await tester.pumpAndSettle();
  });
  testWidgets(
    'detail charts, rankings and 71 branch labels refresh after metadata arrives',
    (tester) async {
      final key = GlobalKey();
      await app(
        tester,
        StockCatalogProductDialog(item: fixture(), source: FakeCatalog()),
        size: const Size(1480, 1100),
        boundary: key,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Created date  01/01/2025'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('product-created-at'))).top,
        lessThan(200),
      );
      await capture(tester, key, 'stock_catalog_product_desktop');
      final branch = fixture()
          .list('branches')
          .firstWhere((r) => r['branch_group'] == '71')['branch']
          .toString();
      StoreBranchIdentityRegistry.groups.value = {branch.toUpperCase(): '71'};
      await tester.pumpAndSettle();
      expect(find.text('71 $branch'), findsWidgets);
      final search = find.byType(TextField).last;
      await tester.ensureVisible(search);
      await tester.pumpAndSettle();
      await capture(tester, key, 'stock_catalog_product_branches');
      await tester.enterText(search, '71 $branch');
      await tester.pumpAndSettle();
      expect(find.text('71 $branch'), findsWidgets);
      expect(
        find.text(
          '1 active branches • Stock and recent demand share one snapshot • Click a column to rank',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'error recovery, queued rebuild and page disposal cancel polling',
    (tester) async {
      final source = FakeCatalog()..fail = true;
      await app(tester, StockCatalogPage(dataSource: source));
      expect(find.text('Retry'), findsOneWidget);
      source.fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byTooltip(
          'Rebuild Item Report stock and sales snapshot in the background',
        ),
      );
      await tester.pump();
      expect(source.refreshes, 1);
      source.status = 'complete';
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'sidebar offers independent Overview, MRN Overview and Near Expiry routes',
    (tester) async {
      InventoryPageType? selected;
      await app(
        tester,
        SizedBox(
          width: 280,
          child: StockManagementNavigation(
            selectedPage: InventoryPageType.stockManagement,
            onSelected: (v) => selected = v,
          ),
        ),
      );
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('MRN Overview'), findsOneWidget);
      expect(find.text('Near Expiry'), findsOneWidget);
      await tester.tap(find.text('MRN Overview'));
      expect(selected, InventoryPageType.mrnOverview);
    },
  );
}
