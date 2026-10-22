import 'package:daily_order/presentation/inventory_dashboard/page/stock_catalog_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_expiry_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_management_page.dart';
import 'package:daily_order/presentation/widgets/inventory_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'stock_catalog_test.dart' as catalog;
import 'stock_expiry_test.dart' as expiry;
import 'stock_management_test.dart' as mrn;

void main() {
  Finder search(String hint) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.hintText == hint,
  );
  Future<void> select(
    WidgetTester tester,
    String label,
    String query,
    String option,
  ) async {
    await tester.tap(find.byTooltip('Choose $label'));
    await tester.pumpAndSettle();
    await tester.enterText(search('Search $label...'), query);
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .ancestor(
            of: find.text(option).last,
            matching: find.byType(InkResponse),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Overview enables search for all five filters', (tester) async {
    final source = catalog.FakeCatalog();
    await catalog.app(tester, StockCatalogPage(dataSource: source));
    final filters = tester.widgetList<InventoryDropdown<String>>(
      find.byType(InventoryDropdown<String>),
    );
    expect(filters.length, 5);
    expect(filters.every((filter) => filter.searchable), isTrue);
    final reads = source.queries.length;
    final supplier = catalog.fixture().text('supplier');
    await select(tester, 'Supplier', supplier.substring(0, 4), supplier);
    expect(
      tester
          .widgetList<InventoryDropdown<String>>(
            find.byType(InventoryDropdown<String>),
          )
          .singleWhere((filter) => filter.label == 'Supplier')
          .value,
      supplier,
    );
    expect(source.queries.length, reads);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MRN enables search for all four filters', (tester) async {
    final source = mrn.FakeStockSource();
    await catalog.app(tester, StockManagementPage(dataSource: source));
    final filters = tester.widgetList<InventoryDropdown<String>>(
      find.byType(InventoryDropdown<String>),
    );
    expect(filters.length, 4);
    expect(filters.every((filter) => filter.searchable), isTrue);
    final reads = source.queries.length;
    await select(tester, 'Stock status', 'No Stock', 'No Stock');
    expect(
      tester
          .widgetList<InventoryDropdown<String>>(
            find.byType(InventoryDropdown<String>),
          )
          .singleWhere((filter) => filter.label == 'Stock status')
          .value,
      'no_stock',
    );
    expect(source.queries.length, reads);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Near Expiry searches labels and keeps raw urgency filter', (
    tester,
  ) async {
    final source = expiry.FakeExpirySource();
    await catalog.app(
      tester,
      StockExpiryPage(
        dataSource: source,
        productDataSource: mrn.FakeStockSource(),
      ),
    );
    final filters = tester.widgetList<InventoryDropdown<String>>(
      find.byType(InventoryDropdown<String>),
    );
    expect(filters.length, 1);
    expect(filters.single.searchable, isTrue);
    await tester.tap(find.byTooltip('Choose option'));
    await tester.pumpAndSettle();
    await tester.enterText(search('Search options...'), 'Expired');
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .ancestor(
            of: find.text('Expired').last,
            matching: find.byType(InkResponse),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(source.queries.last.urgency, 'expired');
    expect(tester.takeException(), isNull);
  });
}
