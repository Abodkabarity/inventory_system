import 'package:daily_order/core/config/online_overview_local_config.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/domain/entities/inventory_page.dart';
import 'package:daily_order/domain/entities/online_overview.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/online_overview_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_catalog_product_dialog.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/online_overview_grid.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_catalog_visuals.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_management_navigation.dart';
import 'package:daily_order/presentation/widgets/inventory_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'online_overview_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts =
        '${Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter'}/bin/cache/artifacts/material_fonts';
    for (final entry in {
      'Roboto': 'roboto-regular.ttf',
      'Ahem': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      final file = File('$fonts/${entry.value}');
      if (file.existsSync()) {
        final loader = FontLoader(entry.key)
          ..addFont(file.readAsBytes().then(ByteData.sublistView));
        await loader.load();
      }
    }
  });
  setUpAll(() async {
    for (final name in ['UnsortIcon', 'FilterIcon']) {
      final loader = FontLoader('packages/syncfusion_flutter_datagrid/$name')
        ..addFont(
          rootBundle.load(
            'packages/syncfusion_flutter_datagrid/assets/font/$name.ttf',
          ),
        );
      await loader.load();
    }
  });
  tearDown(() => StoreBranchIdentityRegistry.groups.value = {});
  Future<void> showPage(
    WidgetTester tester, {
    double width = 1440,
    double height = 900,
    FakeOnlineOverviewSource? source,
    Future<void> Function(List<Map<String, dynamic>>, String)? export,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('online-app-preview'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            fontFamily: 'Roboto',
            colorSchemeSeed: const Color(0xFF008A83),
          ),
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('online-preview'),
              child: OnlineOverviewPage(
                dataSource: source ?? FakeOnlineOverviewSource(),
                export: export,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(
    WidgetTester tester,
    String name, {
    bool dialog = false,
  }) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(ValueKey(dialog ? 'online-app-preview' : 'online-preview')),
    );
    final path = 'outputs/online_overview/$name.png';
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(path).parent.create(recursive: true);
      await File(path).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'navigation places Online Overview immediately below Near Expiry',
    (tester) async {
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      InventoryPageType? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StockManagementNavigation(
                onlineUserId: OnlineOverviewLocalConfig.allowedUserId,
                selectedPage: InventoryPageType.onlineOverview,
                onSelected: (page) => selected = page,
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.text('Online Overview')).dy,
        greaterThan(tester.getTopLeft(find.text('Near Expiry')).dy),
      );
      await tester.tap(find.text('Online Overview'));
      expect(selected, InventoryPageType.onlineOverview);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop shows rank, separate statuses and sources without overflow',
    (tester) async {
      await showPage(
        tester,
        width: 1637,
        source: FakeOnlineOverviewSource(
          onlineSnapshot(
            serverMeta: {
              'excluded_branches': [
                {'name': 'PIXEL - AD'},
              ],
            },
          ),
        ),
      );
      expect(find.text('Online Overview'), findsOneWidget);
      expect(find.text('Online stock'), findsOneWidget);
      expect(find.text('A · High priority'), findsOneWidget);
      expect(find.text('M · No stock or sales'), findsOneWidget);
      expect(find.text('S · In-house'), findsOneWidget);
      expect(find.text('Purchase status'), findsWidgets);
      expect(find.textContaining('PIXEL - AD'), findsNothing);
      expect(find.textContaining('Sales through'), findsNothing);
      final firstRow = tester.getTopLeft(find.text('Products shown')).dy;
      final secondRow = tester
          .getTopLeft(find.text('Estimated sales (AED)'))
          .dy;
      expect(secondRow, greaterThan(firstRow));
      for (final label in [
        'A · High priority',
        'B · Medium sales',
        'C · Low sales',
        'N · New, no online stock',
      ]) {
        expect(tester.getTopLeft(find.text(label)).dy, firstRow);
      }
      for (final label in [
        'M · No stock or sales',
        'T · Stock with no recent sales',
        'S · In-house',
        'Needs review',
      ]) {
        expect(tester.getTopLeft(find.text(label)).dy, secondRow);
      }
      expect(find.textContaining('6 products · Stock as of'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'desktop');
      await tester.tap(find.byTooltip('What the letters mean'));
      await tester.pumpAndSettle();
      expect(find.text('Retail AED 1,000 or more'), findsOneWidget);
      expect(find.text('Top 25% by Qty'), findsOneWidget);
      expect(find.text('Top 10% by sales value'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await screenshot(tester, 'rank_guide_desktop', dialog: true);
    },
  );

  for (final width in [1440.0, 360.0]) {
    testWidgets(
      'availability shows ABC counts, branch search and 71 names at $width',
      (tester) async {
        const branches = [
          OnlineBranch('Web Shop', '71'),
          OnlineBranch('Online Two', 'APG'),
        ];
        final source = FakeOnlineOverviewSource(
          onlineSnapshot(branches: branches),
        );
        source.availabilityResponse = {
          'generation': 'prepared-v1',
          'stock_day': '2026-11-17',
          'rows': [
            for (final branch in branches)
              for (final rank in ['a', 'b', 'c'])
                {
                  'branch_name': branch.name,
                  'rank': rank,
                  'total': rank == 'a'
                      ? 1000
                      : rank == 'b'
                      ? 200
                      : 50,
                  'available': rank == 'a'
                      ? (branch.name == 'Web Shop' ? 800 : 600)
                      : rank == 'b'
                      ? 50
                      : 0,
                  'unknown': rank == 'a' && branch.name == 'Web Shop' ? 100 : 0,
                },
          ],
        };
        await showPage(
          tester,
          width: width,
          height: width == 360 ? 800 : 1000,
          source: source,
        );
        if (width == 1440) {
          await tester.tap(find.text('C · Low sales'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byTooltip('Branch availability'));
        await tester.pumpAndSettle();
        expect(source.availabilityGenerations, ['prepared-v1']);
        expect(find.text('Branch availability'), findsOneWidget);
        expect(find.textContaining('Stock as of 17 Nov 2026'), findsOneWidget);
        final web = find.byKey(const ValueKey('availability-Web Shop'));
        expect(
          find.descendant(of: web, matching: find.text('80.0%')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: web,
            matching: find.text('800 of 1,000 available'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: web,
            matching: find.textContaining('100 stock reports missing'),
          ),
          findsOneWidget,
        );
        expect(find.text('Retail outlet'), findsNothing);
        if (width == 360) {
          await screenshot(
            tester,
            'branch_availability_mobile_top',
            dialog: true,
          );
        }
        await tester.ensureVisible(web);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await screenshot(
          tester,
          width == 1440
              ? 'branch_availability_desktop'
              : 'branch_availability_mobile',
          dialog: true,
        );
        StoreBranchIdentityRegistry.groups.value = {
          'WEB SHOP': '71',
          'ONLINE TWO': 'APG',
        };
        await tester.pumpAndSettle();
        expect(find.text('71 Web Shop'), findsOneWidget);
        final search = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        );
        await tester.ensureVisible(search);
        await tester.enterText(search, '71 Web');
        await tester.pumpAndSettle();
        expect(web, findsOneWidget);
        expect(
          find.byKey(const ValueKey('availability-Online Two')),
          findsNothing,
        );
        expect(find.text('1 of 2 branches'), findsOneWidget);
        await tester.enterText(search, 'not a branch');
        await tester.pumpAndSettle();
        expect(find.text('No matching branches.'), findsOneWidget);
        await tester.tap(find.byTooltip('Close availability'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'availability retries failed requests and reload uses the latest generation',
    (tester) async {
      final source = FakeOnlineOverviewSource()..failAvailability = true;
      await showPage(tester, source: source);
      await tester.tap(find.byTooltip('Branch availability'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not load availability'),
        findsOneWidget,
      );
      source.failAvailability = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Average availability per branch'), findsOneWidget);
      expect(find.text('No products'), findsOneWidget);
      expect(source.availabilityGenerations, ['prepared-v1', 'prepared-v1']);
      await tester.tap(find.byTooltip('Close availability'));
      await tester.pumpAndSettle();
      source.rebuilt = true;
      await tester.tap(find.text('Reload'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Branch availability'));
      await tester.pumpAndSettle();
      expect(source.availabilityGenerations.last, 'prepared-v2');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stock cover bars show the weekly and monthly color boundaries', (
    tester,
  ) async {
    final examples = [
      (null, catalogMuted, '—', 0.0),
      (6.9, catalogRose, '6 days', 6.9 / 90),
      (7.0, catalogOrange, '7 days', 7 / 90),
      (14.0, catalogBlue, '14 days', 14 / 90),
      (30.0, catalogTeal, '30 days', 30 / 90),
      (120.0, catalogTeal, '120 days', 1.0),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final (days, _, _, _) in examples)
                OnlineStockCoverBar(days: days),
            ],
          ),
        ),
      ),
    );
    final bars = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .toList();
    for (final (index, (_, color, label, progress)) in examples.indexed) {
      expect(bars[index].color, color);
      expect(bars[index].value, closeTo(progress, 1e-6));
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('narrow view wraps controls and keeps a usable scrolling grid', (
    tester,
  ) async {
    await showPage(tester, width: 360, height: 740);
    expect(find.byType(SfDataGrid), findsOneWidget);
    expect(tester.takeException(), isNull);
    await screenshot(tester, 'narrow');
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    expect(find.text('All online branches'), findsOneWidget);
    expect(find.text('All purchase statuses'), findsOneWidget);
    await tester.tap(find.byTooltip('What the letters mean'));
    await tester.pumpAndSettle();
    await screenshot(tester, 'rank_guide_narrow', dialog: true);
    final review = find.descendant(
      of: find.byType(Dialog),
      matching: find.text('Needs review'),
    );
    await tester.ensureVisible(review);
    await tester.pumpAndSettle();
    expect(review.hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [1440.0, 360.0]) {
    testWidgets(
      'six-month trial shows forecast dates, plan and online-only branches at $width',
      (tester) async {
        final forecast = {
          'status': 'ready',
          'horizon_months': 6,
          'qty': 42,
          'estimated_value': 420,
          'product_age': {
            'status': 'new',
            'first_mrn': '2026-09-08',
            'new_until': '2027-03-08',
            'as_of': '2026-10-31',
            'first_online_sale_month': '2026-09-01',
          },
          'forecast_from': '2026-11-01',
          'forecast_to': '2027-04-30',
          'reason':
              'Expected online sales over 6 months: 42 Qty. High expected Qty.',
          'suggested_branches': ['Web Shop'],
          'branches': [
            {
              'branch': 'Web Shop',
              'qty': 42,
              'sale_chance': .8,
              'required': true,
            },
            {
              'branch': 'Retail outlet',
              'qty': 999,
              'sale_chance': 1,
              'required': true,
            },
          ],
        };
        final source = FakeOnlineOverviewSource(
          onlineSnapshot(
            serverMeta: {
              'forecast': {
                'status': 'ready',
                'policy': [.65, .85, .40, .70],
                'mrn_age_rule': 'first-mrn-six-calendar-months-v1',
                'forecast_from': '2026-11-01',
                'forecast_to': '2027-04-30',
              },
            },
            items: [
              onlineItem('FAST', extra: {'test_forecast': forecast}),
              onlineItem(
                'MEDIUM',
                extra: {
                  'test_forecast': {
                    ...forecast,
                    'qty': 14,
                    'reason':
                        'Expected sales of 14 Qty. Medium expected sales.',
                  },
                },
              ),
              onlineItem(
                'EXPENSIVE',
                retail: 1500,
                extra: {
                  'test_forecast': {
                    ...forecast,
                    'qty': 1,
                    'estimated_value': 1500,
                    'reason': 'Expected sales of 1 Qty. Low expected sales.',
                  },
                },
              ),
              onlineItem('NEW'),
              onlineItem('NEW-N', extra: {'test_forecast': forecast}),
              onlineItem('SLOW'),
              onlineItem('HOUSE', extra: {'sales_orientation': 'INHOUSE'}),
              onlineItem('UNTESTED'),
            ],
          ),
        );
        await showPage(tester, source: source, width: width);
        expect(find.textContaining('Sales through'), findsNothing);
        if (width == 360) {
          expect(find.text('6-month forecast trial'), findsOneWidget);
        }
        await tester.tap(find.byTooltip('What the letters mean'));
        await tester.pumpAndSettle();
        expect(find.text('Top 35% by expected Qty'), findsOneWidget);
        expect(find.text('Top 15% by expected value'), findsOneWidget);
        expect(find.text('Why 35%?'), findsOneWidget);
        expect(find.text('New products'), findsOneWidget);
        expect(find.textContaining('top 60% by expected Qty'), findsOneWidget);
        for (final code in [
          'FAST',
          'MEDIUM',
          'EXPENSIVE',
          'NEW',
          'NEW-N',
          'SLOW',
          'HOUSE',
          'UNTESTED',
        ]) {
          expect(
            find.textContaining(
              RegExp(
                '^Current example · ${RegExp.escape(code)}'
                r'(?: ·|$)',
              ),
            ),
            findsOneWidget,
          );
        }
        await screenshot(
          tester,
          width == 1440
              ? 'rank_guide_forecast_desktop'
              : 'rank_guide_forecast_mobile',
          dialog: true,
        );
        final lastExample = find.textContaining('Current example · UNTESTED');
        await tester.ensureVisible(lastExample);
        await tester.pumpAndSettle();
        expect(lastExample.hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('FAST Product'));
        await tester.pumpAndSettle();
        expect(find.text('Next 6 months'), findsOneWidget);
        expect(find.text('New product'), findsOneWidget);
        expect(find.text('First MRN 08 Sep 2026'), findsOneWidget);
        expect(find.text('First online sales: Sep 2026.'), findsOneWidget);
        expect(find.text('Expected sales 42 Qty'), findsOneWidget);
        expect(
          find.text('Current stock in 1 of 1 planned branch.'),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('online-six-month-forecast')),
            matching: find.textContaining('01 Nov 2026 – 30 Apr 2027'),
          ),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.text('Expected sales by online branch'),
        );
        await tester.tap(find.text('Expected sales by online branch'));
        await tester.pumpAndSettle();
        expect(find.text('Web Shop'), findsWidgets);
        expect(find.text('Retail outlet'), findsNothing);
        expect(tester.takeException(), isNull);
        await screenshot(
          tester,
          width == 1440
              ? 'six_month_forecast_dialog'
              : 'six_month_forecast_mobile',
          dialog: true,
        );
      },
    );
  }

  testWidgets('search and Excel export share the complete filtered rows', (
    tester,
  ) async {
    StoreBranchIdentityRegistry.groups.value = {'WEB SHOP': '71'};
    List<Map<String, dynamic>>? exported;
    await showPage(
      tester,
      export: (rows, name) async {
        expect(name, 'online_overview.xlsx');
        exported = rows;
      },
    );
    await tester.enterText(find.byType(TextField).first, 'EXPENSIVE');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('EXPENSIVE Product'), findsOneWidget);
    expect(find.text('FAST Product'), findsNothing);
    await tester.tap(find.text('Export Excel'));
    await tester.pumpAndSettle();
    expect(exported!.single['item_code'], 'EXPENSIVE');
    expect(exported!.single['estimated_retail_value_2026'], 4000);
    expect(exported!.single['online_branches'], '71 Web Shop');
    expect(exported!.single['purchase_status'], 'AVAILABLE');
    expect(tester.takeException(), isNull);
  });

  testWidgets('S filter exports only INHOUSE products with their orientation', (
    tester,
  ) async {
    List<Map<String, dynamic>>? exported;
    await showPage(
      tester,
      source: FakeOnlineOverviewSource(
        onlineSnapshot(
          items: [
            onlineItem('FAST', extra: {'sales_orientation': 'INHOUSE'}),
            onlineItem('NEW'),
          ],
        ),
      ),
      export: (rows, _) async => exported = rows,
    );
    await tester.tap(find.text('S · In-house'));
    await tester.pumpAndSettle();
    expect(find.text('FAST Product'), findsOneWidget);
    expect(find.text('NEW Product'), findsNothing);
    await tester.tap(find.text('Export Excel'));
    await tester.pumpAndSettle();
    expect(exported, hasLength(1));
    expect(exported!.single['rank'], 'S');
    expect(exported!.single['sales_orientation'], 'INHOUSE');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'other branch stock stays numeric in the grid, dialog and filtered export',
    (tester) async {
      List<Map<String, dynamic>>? exported;
      await showPage(
        tester,
        source: FakeOnlineOverviewSource(
          onlineSnapshot(
            items: [
              onlineItem('FAST', extra: {'other_branch_stock': 120.5}),
              onlineItem('EXPENSIVE', extra: {'other_branch_stock': null}),
            ],
          ),
        ),
        export: (rows, _) async => exported = rows,
      );
      expect(find.text('Other branch stock'), findsOneWidget);
      final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
      final cells = grid.source.rows
          .map(
            (row) => row
                .getCells()
                .firstWhere((cell) => cell.columnName == 'other_branch_stock')
                .value,
          )
          .toList();
      expect(cells, [120.5, 0]);
      await tester.tap(find.text('FAST Product'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Other branch stock'),
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Other branch stock: 120.5 Qty'));
      await tester.pumpAndSettle();
      expect(
        find.text('Other branch stock: 120.5 Qty').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Close details'));
      await tester.pumpAndSettle();
      grid.source.addFilter(
        'other_branch_stock',
        const FilterCondition(type: FilterType.greaterThan, value: 0),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export Excel'));
      await tester.pumpAndSettle();
      expect(exported, hasLength(1));
      expect(exported!.single['item_code'], 'FAST');
      expect(exported!.single['other_branch_stock'], 120.5);
      expect(exported!.single['online_plus_store_stock'], 45);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'N filter exports new products with zero online stock and MRN age',
    (tester) async {
      List<Map<String, dynamic>>? exported;
      await showPage(
        tester,
        source: FakeOnlineOverviewSource(
          onlineSnapshot(
            items: [
              onlineItem(
                'NEW-N',
                purchase: 'OOS',
                extra: {
                  'test_forecast': {
                    'status': 'ready',
                    'qty': 42,
                    'product_age': {
                      'status': 'new',
                      'first_mrn': '2026-09-08',
                      'new_until': '2027-03-08',
                      'as_of': '2026-11-18',
                    },
                  },
                },
              ),
              onlineItem('NEW'),
              onlineItem('FAST', extra: {'sales_orientation': 'INHOUSE'}),
            ],
          ),
        ),
        export: (rows, _) async => exported = rows,
      );
      await tester.tap(find.text('N · New, no online stock'));
      await tester.pumpAndSettle();
      expect(find.text('NEW-N Product'), findsOneWidget);
      expect(find.text('NEW Product'), findsNothing);
      expect(find.text('FAST Product'), findsNothing);
      await tester.tap(find.text('Export Excel'));
      await tester.pumpAndSettle();
      expect(exported, hasLength(1));
      expect(exported!.single['rank'], 'N');
      expect(exported!.single['purchase_status'], 'OOS');
      expect(exported!.single['online_physical_stock'], 0);
      expect(exported!.single['first_mrn_date'], '2026-09-08');
      expect(exported!.single['forecast_qty'], isNull);
      expect(exported!.single['ml_use'], isNot('six_month_forecast'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('column filter and sorting are respected by exports', (
    tester,
  ) async {
    List<Map<String, dynamic>>? exported;
    await showPage(tester, export: (rows, _) async => exported = rows);
    final source = tester.widget<SfDataGrid>(find.byType(SfDataGrid)).source;
    source.addFilter(
      'purchase_status',
      const FilterCondition(type: FilterType.equals, value: 'OOS'),
    );
    source.sortedColumns.add(
      const SortColumnDetails(
        name: 'sales26',
        sortDirection: DataGridSortDirection.descending,
      ),
    );
    await source.sort();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export Excel'));
    await tester.pumpAndSettle();
    expect(exported!.map((r) => r['item_code']), ['HISTORICAL']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'prepared rebuild preserves ABCMT and Purchase Status without raw audits',
    (tester) async {
      final source = FakeOnlineOverviewSource();
      List<Map<String, dynamic>>? exported;
      await showPage(
        tester,
        source: source,
        export: (rows, _) async => exported = rows,
      );
      await tester.tap(find.text('Update data'));
      await tester.pumpAndSettle();
      expect(source.audits, 0);
      expect(source.refreshes, 1);
      await tester.tap(find.text('Export Excel'));
      await tester.pumpAndSettle();
      expect(
        exported!.singleWhere((r) => r['item_code'] == 'SLOW')['rank'],
        'T',
      );
      final historical = exported!.singleWhere(
        (r) => r['item_code'] == 'HISTORICAL',
      );
      expect(historical['rank'], 'T');
      expect(historical['purchase_status'], 'OOS');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late branch metadata refreshes evidence labels and branch search',
    (tester) async {
      final data = onlineSnapshot(
        branches: const [
          OnlineBranch('Web Shop', '71'),
          OnlineBranch('Online Two', 'APG'),
        ],
      );
      await showPage(tester, source: FakeOnlineOverviewSource(data));
      await tester.tap(find.text('FAST Product'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Stock by branch'));
      await tester.tap(find.text('Stock by branch'));
      await tester.pumpAndSettle();
      expect(find.text('Web Shop'), findsWidgets);
      StoreBranchIdentityRegistry.groups.value = {
        'WEB SHOP': '71',
        'ONLINE TWO': 'APG',
      };
      await tester.pumpAndSettle();
      expect(find.text('71 Web Shop'), findsWidgets);
      expect(find.text('Online Two'), findsWidgets);
      await tester.tap(find.byTooltip('Close details'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is InventoryDropdown<String> && w.label == 'Online branch',
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '71 Web');
      await tester.pumpAndSettle();
      expect(find.text('71 Web Shop'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [1440.0, 360.0]) {
    testWidgets('Full Overview details open with online sales at $width', (
      tester,
    ) async {
      final source = FakeOnlineOverviewSource();
      await showPage(
        tester,
        width: width,
        height: width == 360 ? 740 : 900,
        source: source,
      );
      await tester.tap(find.text('FAST Product'));
      await tester.pumpAndSettle();
      expect(find.byType(StockCatalogProductDialog), findsOneWidget);
      expect(source.monthlyLoads, 1);
      expect(find.text('Monthly online sales'), findsOneWidget);
      expect(find.text('Product overview · Online branches'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('product-profile-panel')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('daily-sales-panel')), findsNothing);
      final annual = find.byKey(const ValueKey('annual-sales-panel'));
      for (final label in [
        '2025',
        '3 Qty',
        '1 month',
        '2026',
        '4 Qty',
        '2 months',
      ]) {
        expect(
          find.descendant(of: annual, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(find.text('Stock / Sales'), findsOneWidget);
      expect(find.text('Online stock cover · 2 days'), findsOneWidget);
      expect(find.text('Retail outlet'), findsNothing);
      final gauge = tester.widget<CatalogStockChart>(
        find.byType(CatalogStockChart),
      );
      expect(gauge.onlineSales, isTrue);
      expect(gauge.item.number('total_stock'), 45);
      expect(gauge.item.number('recent_sales'), 50);
      expect(find.text('Why is this A?'), findsOneWidget);
      expect(
        find.textContaining(
          'Online sales: 210 Qty in 1 branch. Top 25% by Qty.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining(RegExp(r'Cash|Insurance')), findsNothing);
      expect(find.text('View full product details'), findsNothing);
      final chart = tester.widget<CatalogMonthlyChart>(
        find.byType(CatalogMonthlyChart),
      );
      expect(chart.item.list('monthly_sales').map((month) => month['total']), [
        3,
        5,
        -1,
      ]);
      expect(tester.takeException(), isNull);
      await screenshot(
        tester,
        width == 1440 ? 'product_desktop' : 'product_narrow',
        dialog: true,
      );
      await tester.ensureVisible(annual);
      await tester.pumpAndSettle();
      await screenshot(
        tester,
        width == 1440 ? 'annual_sales_desktop' : 'annual_sales_narrow',
        dialog: true,
      );

      await tester.ensureVisible(find.text('Stock by branch'));
      await tester.tap(find.text('Stock by branch'));
      await tester.pumpAndSettle();
      expect(find.text('Stock cover · 2 days'), findsOneWidget);
      await tester.ensureVisible(find.text('Check stock history'));
      await tester.tap(find.text('Check stock history'));
      await tester.pumpAndSettle();
      expect(source.audits, 1);
      expect(find.textContaining('days with stock'), findsOneWidget);
      expect(source.monthlyLoads, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'product detail load errors retry without showing an invented product',
    (tester) async {
      final source = FakeOnlineOverviewSource()..failMonthly = true;
      await showPage(tester, source: source);
      await tester.tap(find.text('FAST Product'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not load product details'),
        findsOneWidget,
      );
      source.failMonthly = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(source.monthlyLoads, 2);
      expect(
        find.byKey(const ValueKey('online-monthly-sales-panel')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed load has a working retry and no partial assortment', (
    tester,
  ) async {
    final source = FakeOnlineOverviewSource()..fail = true;
    await showPage(tester, source: source);
    expect(find.text('Could not load products. Tap Retry.'), findsOneWidget);
    expect(find.byType(SfDataGrid), findsNothing);
    source.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('FAST Product'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
