import 'package:daily_order/core/utils/stock_catalog_export.dart';
import 'package:daily_order/core/utils/stock_register_export.dart';
import 'package:daily_order/domain/entities/stock_catalog.dart';
import 'package:daily_order/domain/entities/stock_expiry.dart';
import 'package:daily_order/domain/entities/stock_management.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_catalog_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'stock_catalog_test.dart' as catalog;

const january = StockCatalogItem({
  'item_code': 'ROLLOVER',
  'meta': {
    'monthly_sales_through': '2027-01-01',
    'monthly_current_month': '2027-01-01',
    'monthly_current_source': 'sales_last_45_days',
    'sales_2026_through': '2026-12-01',
  },
  'monthly_sales': [
    {'month': '11/2026', 'total': 30, 'source': 'sales_history'},
    {'month': '12/2026', 'total': 50, 'source': 'sales_history'},
    {
      'month': '01/2027',
      'total': 8,
      'cash': 6,
      'insurance': 3,
      'online': -1,
      'source': 'sales_last_45_days',
      'through': '2027-01-01',
    },
  ],
  'years': {
    '2026': {'total': 80},
    '2027': {'total': 8, 'cash': 6, 'insurance': 3, 'online': -1},
  },
});

void main() {
  test(
    'current-month metadata extends the chart past the historical source date',
    () {
      final series = catalogMonthlySeries(january);
      expect(series.length, 25);
      expect(series.last['month'], '01/2027');
      expect(series.last['total'], 8);
      expect(series.last['source'], 'sales_last_45_days');
      expect(catalogMovingAverage(series).last, closeTo(88 / 3, 0.00001));
      expect(catalogSalesYears(january), [2025, 2026, 2027]);
      final export = catalogExportRow(january);
      expect(export['Sales 2027'], 8);
      expect(export['Cash 2027'], 6);
      expect(export['Insurance 2027'], 3);
      expect(export['Online 2027'], -1);
      final mrn = stockRegisterExportRow(StockManagementItem(january.data));
      expect(mrn['Sales 2027'], 8);
      expect(mrn['Insurance 2027'], 3);
      final expiry = stockExpiryExportRow(
        StockExpiryAlert({'product_data': january.data}),
      );
      expect(expiry['Sales 2027'], 8);
      expect(expiry['Online 2027'], -1);
      // List payloads omit meta; annual keys still keep Excel complete.
      expect(
        stockSalesYears(StockManagementItem({'years': january.data['years']})),
        [2025, 2026, 2027],
      );
    },
  );
  test(
    'legacy cached metadata stays readable until a new snapshot is loaded',
    () {
      const legacy = StockCatalogItem({
        'meta': {'sales_2026_through': '2026-09-01'},
        'monthly_sales': [
          {'month': '09/2026', 'total': 109},
        ],
      });
      expect(catalogMonthlySeries(legacy).last['total'], 109);
      expect(catalogSalesYears(legacy), [2025, 2026]);
    },
  );
  testWidgets('monthly chart explains the current-month source on selection', (
    tester,
  ) async {
    await catalog.app(
      tester,
      const Padding(
        padding: EdgeInsets.all(20),
        child: CatalogPanel(
          title: 'Monthly sales & momentum',
          child: CatalogMonthlyChart(item: january),
        ),
      ),
    );
    final horizontal = tester.widget<SingleChildScrollView>(
      find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      ),
    );
    horizontal.controller!.jumpTo(
      horizontal.controller!.position.maxScrollExtent,
    );
    await tester.pumpAndSettle();
    final plot = find.byWidgetPredicate(
      (w) => w is GestureDetector && w.onTapDown != null,
    );
    final origin = tester.getTopLeft(plot), size = tester.getSize(plot);
    await tester.tapAt(origin + Offset(size.width - 30, 80));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Daily sales through 01 Jan 2027'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
