import 'package:daily_order/presentation/inventory_dashboard/page/stock_catalog_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_expiry_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'stock_catalog_test.dart' as catalog;
import 'stock_expiry_test.dart' as expiry;
import 'stock_management_test.dart' as stock;

void main() {
  testWidgets('viewer can inspect expiry notes without write controls', (
    tester,
  ) async {
    final source = expiry.FakeExpirySource();
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: StockExpiryPage(
          dataSource: source,
          productDataSource: stock.FakeStockSource(),
          readOnly: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('review:${source.items.first.key}')),
      findsNothing,
    );
    await tester.tap(find.text(stock.product().name.toUpperCase()).first);
    await tester.pumpAndSettle();
    final note = find.byKey(const ValueKey('expiry-note-field'));
    expect(tester.widget<TextField>(note).readOnly, isTrue);
    expect(find.text('Save note'), findsNothing);
    expect(find.byKey(const ValueKey('expiry-review-button')), findsNothing);
    expect(source.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('viewer has reload and export but cannot rebuild stock', (
    tester,
  ) async {
    final source = catalog.FakeCatalog();
    await catalog.app(
      tester,
      StockCatalogPage(dataSource: source, readOnly: true),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.cloud_sync_outlined), findsNothing);
    expect(find.text('Reload'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
