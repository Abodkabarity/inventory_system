import 'dart:io';
import 'dart:ui' as ui;
import 'package:daily_order/domain/entities/stock_daily_sales.dart';
import 'package:daily_order/domain/entities/stock_catalog.dart';
import 'package:daily_order/core/utils/stock_excel_report.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_catalog_product_dialog.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_catalog_visuals.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_daily_sales_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'stock_catalog_test.dart' as catalog;

Map<String, dynamic> dailyFixture() => {
  'item_code': 'DAILY',
  'item_name': 'Daily sales product',
  'daily_sales_45d_available': true,
  'meta': {'demand_from': '2026-09-06', 'demand_through': '2026-10-20'},
  'recent_sales': 11.75,
  'daily_sales_45d': [
    {
      'date': '2026-09-06',
      'cash': 2.5,
      'online': 1,
      'insurance_basic': 3,
      'insurance_thiqa': 4,
      'other_insurance': 2,
      'total': 12.5,
    },
    {
      'date': '2026-10-20',
      'cash': -2,
      'online': 0.25,
      'insurance_basic': 0.5,
      'insurance_thiqa': -0.5,
      'other_insurance': 1,
      'total': -0.75,
    },
  ],
};

void main() {
  setUpAll(() async {
    final root = Platform.environment['CATALOG_FONT_ROOT'];
    if (root == null) return;
    for (final (family, file) in [
      ('Roboto', 'roboto-regular.ttf'),
      ('MaterialIcons', 'MaterialIcons-Regular.otf'),
    ]) {
      final font = FontLoader(family)
        ..addFont(
          Future.value(
            ByteData.sublistView(File('$root/$file').readAsBytesSync()),
          ),
        );
      await font.load();
    }
  });
  test(
    'fills every calendar date, retains signed fractions, reconciles and exports typed channels',
    () {
      final mix = StockDailySalesMix.fromMap(dailyFixture());
      expect(mix.available, true);
      expect(mix.days.length, 45);
      expect(mix.days.first.isoDate, '2026-09-06');
      expect(mix.days.last.isoDate, '2026-10-20');
      expect(mix.days[1].total, 0);
      expect(mix.days.last.qty(StockSalesChannel.cash), -2);
      expect(mix.total, 11.75);
      expect(mix.totalFor(StockSalesChannel.insuranceThiqa), 3.5);
      final report = StockExcelReport(
        mix.days.map((d) => d.exportRow).toList(),
        'item_daily_sales_45_days.xlsx',
      );
      expect(report.rows.length, 45);
      expect(report.sheetName, 'Daily Sales 45 Days');
      expect(report.types.first, 'date');
      expect(report.types.skip(1).toSet(), {'number'});
      expect(report.rows.last['Other Insurance'], 1);
      expect(report.rows.last['Total Qty'], -0.75);
      expect(report.rows.last.keys, [
        'Date',
        'Cash',
        'Online',
        'Insurance Basic',
        'Insurance Thiqa',
        'Other Insurance',
        'Total Qty',
      ]);
    },
  );
  test(
    'absent, inconsistent, duplicated and invalid source data never claims zero sales',
    () {
      expect(StockDailySalesMix.fromMap({}).available, false);
      expect(
        StockDailySalesMix.fromMap({
          ...dailyFixture(),
          'recent_sales': 999,
        }).available,
        false,
      );
      final duplicate = dailyFixture();
      (duplicate['daily_sales_45d'] as List).add(
        (duplicate['daily_sales_45d'] as List).first,
      );
      expect(StockDailySalesMix.fromMap(duplicate).available, false);
      expect(
        StockDailySalesMix.fromMap({
          ...dailyFixture(),
          'meta': {'demand_from': '2026-08-01', 'demand_through': '2026-10-20'},
        }).available,
        false,
      );
      final empty = StockDailySalesMix.fromMap({
        ...dailyFixture(),
        'recent_sales': 0,
        'daily_sales_45d': [],
      });
      expect(empty.available, true);
      expect(empty.days.length, 45);
      expect(empty.total, 0);
      final partial = StockDailySalesMix.fromMap({
        ...dailyFixture(),
        'meta': {'demand_from': '2026-10-19', 'demand_through': '2026-10-20'},
        'recent_sales': 0,
        'daily_sales_45d': [],
      });
      expect(partial.days.length, 2);
    },
  );
  for (final width in [1400.0, 390.0]) {
    testWidgets('daily chart hover, tap, navigation and zero days at $width', (
      tester,
    ) async {
      final boundary = GlobalKey();
      final mix = StockDailySalesMix.fromMap(dailyFixture());
      await catalog.app(
        tester,
        SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: CatalogPanel(
              title: 'Sales 45 Days',
              subtitle: '06 Sep 2026 – 20 Oct 2026 • Daily net Qty',
              child: StockDailySalesChart(mix: mix),
            ),
          ),
        ),
        size: Size(width, 900),
        boundary: boundary,
      );
      final selection = find.byKey(const ValueKey('daily-sales-selection'));
      expect(
        find.descendant(
          of: selection,
          matching: find.textContaining('06 Sep 2026'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: selection,
          matching: find.textContaining('07 Sep 2026'),
        ),
        findsOneWidget,
      );
      final plot = find.byKey(const ValueKey('daily-sales-plot'));
      final origin = tester.getTopLeft(plot);
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: origin + const Offset(116, 50));
      await mouse.moveTo(origin + const Offset(116, 90));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: selection,
          matching: find.textContaining('07 Sep 2026'),
        ),
        findsOneWidget,
      );
      await tester.tapAt(origin + const Offset(156, 90));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: selection,
          matching: find.textContaining('08 Sep 2026'),
        ),
        findsOneWidget,
      );
      await mouse.removePointer();
      if (Platform.environment['UPDATE_CATALOG_PREVIEW'] == '1') {
        await catalog.capture(
          tester,
          boundary,
          'stock_daily_sales_${width.toInt()}',
        );
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('shared product dialog places daily chart after monthly chart', (
    tester,
  ) async {
    final row = StockCatalogItem({
      ...catalog.fixture().data,
      ...dailyFixture(),
    });
    await catalog.app(
      tester,
      StockCatalogProductDialog(item: row, loadItem: () async => row),
    );
    final daily = find.byKey(const ValueKey('daily-sales-panel'));
    final monthly = find.text('Monthly sales & momentum');
    expect(daily, findsOneWidget);
    expect(
      tester.getTopLeft(daily).dy,
      greaterThan(tester.getTopLeft(monthly).dy),
    );
    await tester.ensureVisible(daily);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Export daily sales'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
