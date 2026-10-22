import 'package:daily_order/domain/entities/inventory_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_catalog_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_expiry_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_management_page.dart';
import 'package:daily_order/presentation/widgets/retained_page_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'stock_catalog_test.dart' as catalog;
import 'stock_expiry_test.dart' as expiry;
import 'stock_management_test.dart' as mrn;

const _pages = [
  InventoryPageType.stockManagement,
  InventoryPageType.mrnOverview,
  InventoryPageType.nearExpiry,
  InventoryPageType.availabilityKpi,
  InventoryPageType.fillRateKpi,
];

void main() {
  testWidgets('pages load lazily, retain state and receive updated inputs', (
    tester,
  ) async {
    var selected = _pages.first;
    var reportDate = '2026-10-22';
    final opened = <InventoryPageType, int>{};
    final closed = <InventoryPageType, int>{};
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return Scaffold(
              body: RetainedPageStack<InventoryPageType>(
                pages: _pages,
                selectedPage: selected,
                pageBuilder: (_, page) => _ProbePage(
                  page: page,
                  reportDate: reportDate,
                  opened: opened,
                  closed: closed,
                ),
              ),
            );
          },
        ),
      ),
    );
    expect(opened, {_pages.first: 1});
    await tester.enterText(find.byType(TextField), 'Keep this filter');
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final originalState = tester.state<_ProbePageState>(
      find.byType(_ProbePage),
    );
    final scrollOffset = originalState.scroll.offset;
    expect(scrollOffset, greaterThan(0));
    for (final page in _pages.skip(1)) {
      rebuild(() => selected = page);
      await tester.pump();
      expect(opened[page], 1);
      expect(closed, isEmpty);
    }
    rebuild(() {
      selected = _pages.first;
      reportDate = '2026-10-23';
    });
    await tester.pump();
    expect(tester.state(find.byType(_ProbePage)), same(originalState));
    expect(originalState.scroll.offset, scrollOffset);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep this filter',
    );
    expect(find.text('2026-10-23'), findsOneWidget);
    expect(opened.values, everyElement(1));
    for (final element
        in find.byType(_ProbePage, skipOffstage: false).evaluate()) {
      final page = (element.widget as _ProbePage).page;
      expect(TickerMode.valuesOf(element).enabled, page == selected);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(closed.length, _pages.length);
    expect(closed.values, everyElement(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('stock pages return without fetching or resetting their filters', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final overview = catalog.FakeCatalog();
    final register = mrn.FakeStockSource();
    final alerts = expiry.FakeExpirySource();
    var selected = _pages.first;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) {
            rebuild = setState;
            return Scaffold(
              body: RetainedPageStack<InventoryPageType>(
                pages: _pages,
                selectedPage: selected,
                pageBuilder: (_, page) => switch (page) {
                  InventoryPageType.stockManagement => StockCatalogPage(
                    dataSource: overview,
                    readOnly: true,
                  ),
                  InventoryPageType.mrnOverview => StockManagementPage(
                    dataSource: register,
                    onOpenExpiry: () =>
                        rebuild(() => selected = InventoryPageType.nearExpiry),
                  ),
                  InventoryPageType.nearExpiry => StockExpiryPage(
                    dataSource: alerts,
                    readOnly: true,
                    embedded: true,
                    productDataSource: register,
                  ),
                  _ => const Scaffold(body: Text('KPI')),
                },
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(register.queries, isEmpty);
    expect(alerts.queries, isEmpty);
    final pageStates = <InventoryPageType, State>{};
    final filters = <InventoryPageType, String>{};
    for (final page in _pages.take(3)) {
      rebuild(() => selected = page);
      await tester.pumpAndSettle();
      final type = switch (page) {
        InventoryPageType.stockManagement => StockCatalogPage,
        InventoryPageType.mrnOverview => StockManagementPage,
        _ => StockExpiryPage,
      };
      pageStates[page] = tester.state(find.byType(type));
      filters[page] = 'artelac';
      await tester.enterText(find.byType(TextField).first, filters[page]!);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
    }
    final counts = (
      overview.queries.length,
      register.queries.length,
      alerts.queries.length,
    );
    for (final page in [..._pages.reversed, _pages.first]) {
      rebuild(() => selected = page);
      await tester.pumpAndSettle();
      if (filters.containsKey(page)) {
        expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          filters[page],
        );
      }
    }
    expect((
      overview.queries.length,
      register.queries.length,
      alerts.queries.length,
    ), counts);
    expect(
      tester.state(find.byType(StockCatalogPage)),
      same(pageStates[_pages.first]),
    );
    // Manual reload remains available and still uses the normal validated loader.
    await tester.tap(find.text('Reload'));
    await tester.pumpAndSettle();
    expect(overview.queries.length, greaterThan(counts.$1));
    expect(alerts.writes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _ProbePage extends StatefulWidget {
  final InventoryPageType page;
  final String reportDate;
  final Map<InventoryPageType, int> opened, closed;
  const _ProbePage({
    required this.page,
    required this.reportDate,
    required this.opened,
    required this.closed,
  });
  @override
  State<_ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<_ProbePage> {
  final filter = TextEditingController();
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    widget.opened.update(widget.page, (count) => count + 1, ifAbsent: () => 1);
  }

  @override
  void dispose() {
    widget.closed.update(widget.page, (count) => count + 1, ifAbsent: () => 1);
    filter.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(widget.reportDate),
      TextField(controller: filter),
      Expanded(
        child: ListView.builder(
          controller: scroll,
          itemCount: 50,
          itemBuilder: (_, index) =>
              SizedBox(height: 40, child: Text('Row $index')),
        ),
      ),
    ],
  );
}
