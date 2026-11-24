import 'dart:async';

import 'package:daily_order/data/datasources/remote/stock_catalog_remote_ds.dart';
import 'package:daily_order/domain/entities/inventory_page.dart';
import 'package:daily_order/domain/entities/stock_catalog.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_catalog_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/inventory_overview_stack.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_catalog_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'stock_catalog_memory_cache_test.dart' show CatalogServer;

class _Source extends StockCatalogRemoteDs {
  _Source(super.client);
  Completer<void>? waitForHeader;

  @override
  Future<StockCatalogResult> fetchPage(StockCatalogQuery query) async {
    await waitForHeader?.future;
    return super.fetchPage(query);
  }
}

void main() {
  late CatalogServer server;
  setUpAll(() async {
    server = CatalogServer();
    server.client.auth.stopAutoRefresh();
    // Start the client's JSON worker outside the widget-test fake clock.
    await server.source.fetchAll();
    await server.source.requestRefresh();
    server.calls.clear();
  });
  tearDownAll(() => server.client.dispose());
  testWidgets(
    'Inventory keeps Overview filters and scroll, validates in background and reloads changed data',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = _Source(server.client);
      var selected = InventoryPageType.dashboard;
      late StateSetter rebuild;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              rebuild = setState;
              return Scaffold(
                body: InventoryOverviewStack(
                  selectedPage: selected,
                  pageBuilder: (_, page) =>
                      page == InventoryPageType.stockManagement
                      ? StockCatalogPage(
                          dataSource: source,
                          active: selected == page,
                        )
                      : Text('Other page: $page'),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(server.calls, isEmpty);
      rebuild(() => selected = InventoryPageType.stockManagement);
      await tester.pumpAndSettle();
      final originalState = tester.state(find.byType(StockCatalogPage));
      final originalBatchCount = server.count(
        'get_stock_catalog_register_batch',
      );
      expect(originalBatchCount, 1);
      await tester.enterText(find.byType(TextField).first, 'Product A');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<SfDataGrid>(find.byType(SfDataGrid))
          .horizontalScrollController!;
      scroll.jumpTo(240);
      await tester.pumpAndSettle();
      final offset = scroll.offset;
      expect(offset, greaterThan(0));
      rebuild(() => selected = InventoryPageType.mrnOverview);
      await tester.pumpAndSettle();
      expect(find.byType(StockCatalogPage), findsNothing);
      final headers = server.count('get_stock_catalog_page');
      source.waitForHeader = Completer<void>();
      rebuild(() => selected = InventoryPageType.stockManagement);
      await tester.pump();
      expect(tester.state(find.byType(StockCatalogPage)), same(originalState));
      expect(find.text('Product A'), findsWidgets);
      expect(scroll.offset, offset);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Reload'),
            )
            .onPressed,
        isNotNull,
      );
      // The existing table stays visible while the small server check waits.
      expect(find.byType(StockCatalogGrid), findsOneWidget);
      source.waitForHeader!.complete();
      await tester.pumpAndSettle();
      expect(server.count('get_stock_catalog_page'), headers + 1);
      expect(
        server.count('get_stock_catalog_register_batch'),
        originalBatchCount,
      );
      expect(scroll.offset, offset);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Product A',
      );

      rebuild(() => selected = InventoryPageType.dashboard);
      await tester.pumpAndSettle();
      server.revision = 'r2';
      rebuild(() => selected = InventoryPageType.stockManagement);
      await tester.pumpAndSettle();
      expect(
        server.count('get_stock_catalog_register_batch'),
        originalBatchCount + 1,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Product A',
      );
      final checked = server.count('get_stock_catalog_page');
      await tester.tap(find.text('Reload'));
      await tester.pumpAndSettle();
      expect(server.count('get_stock_catalog_page'), checked + 1);

      rebuild(() => selected = InventoryPageType.dashboard);
      await tester.pumpAndSettle();
      server.failHeader = true;
      rebuild(() => selected = InventoryPageType.stockManagement);
      await tester.pumpAndSettle();
      expect(find.textContaining('Unable to load Overview.'), findsOneWidget);
      expect(find.byType(StockCatalogGrid), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('only Overview is retained and changing accounts clears it', (
    tester,
  ) async {
    var selected = InventoryPageType.dashboard;
    var account = 'first';
    var opened = 0;
    var closed = 0;
    late StateSetter rebuild;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) {
            rebuild = setState;
            return InventoryOverviewStack(
              key: ValueKey(account),
              selectedPage: selected,
              pageBuilder: (_, page) => _Probe(
                key: ValueKey(page),
                onOpen: () => opened++,
                onClose: () => closed++,
              ),
            );
          },
        ),
      ),
    );
    expect(opened, 1);
    rebuild(() => selected = InventoryPageType.stockManagement);
    await tester.pump();
    expect(opened, 2);
    expect(closed, 1);
    rebuild(() => selected = InventoryPageType.mrnOverview);
    await tester.pump();
    expect(opened, 3);
    expect(closed, 1);
    rebuild(() => account = 'second');
    await tester.pump();
    expect(closed, 3);
    expect(opened, 4);
    await tester.pumpWidget(const SizedBox());
    expect(closed, 4);
  });
}

class _Probe extends StatefulWidget {
  const _Probe({super.key, required this.onOpen, required this.onClose});
  final VoidCallback onOpen, onClose;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onOpen();
  }

  @override
  void dispose() {
    widget.onClose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('Page');
}
