// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:daily_order/core/config/stock_management_load_config.dart';
import 'package:daily_order/core/utils/stock_excel_report.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/data/datasources/remote/stock_management_remote_ds.dart';
import 'package:daily_order/domain/entities/inventory_page.dart';
import 'package:daily_order/domain/entities/stock_management.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_management_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_management_grid.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_management_navigation.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_receipt_quantity.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_mrn_receipt_summary.dart';
import 'stock_catalog_test.dart' as catalog;

StockManagementItem cdItem(String warehouse, {num qty = 12, num bonus = 2}) =>
    StockManagementItem({
      ...catalog.fixture().data,
      'item_code': 'A',
      'item_name': 'Product A',
      'warehouse': warehouse,
      'receipt_source': 'mrn_cd_apg_2026',
      'register_key': jsonEncode([warehouse, 'A']),
      'last_mrn_date': '2026-10-29',
      'received_quantity': 999,
      'total_qty': qty,
      'bonus': bonus,
    });

class CdSource extends StockManagementDataSource {
  @override
  Future<StockManagementResult> fetchPage(StockManagementQuery query) async =>
      StockManagementResult(
        rows: [
          cdItem('Alpha'),
          cdItem('Beta', qty: 8, bonus: 0),
        ].skip(query.offset).take(query.limit).toList(),
        summary: const {'items': 2},
        meta: const {'source': 'mrn_cd_apg_2026', 'snapshot_at': 'cd-v1'},
      );
  @override
  Future<StockManagementItem> fetchItem(String itemCode) async =>
      cdItem('Alpha');
  @override
  Future<void> requestRefresh() async {}
  @override
  Future<Map<String, dynamic>?> refreshState() async => null;
}

class NavigationSource extends CdSource {
  NavigationSource(this.cd);
  final bool cd;
  Completer<void>? pending;
  int requests = 0;

  @override
  Future<StockManagementResult> fetchPage(StockManagementQuery query) async {
    requests++;
    await pending?.future;
    if (cd) return super.fetchPage(query);
    return StockManagementResult(
      rows: [
        StockManagementItem({
          ...catalog.fixture().data,
          'item_code': 'STORE',
          'item_name': 'STORE product',
          'total_qty': 70,
        }),
      ].skip(query.offset).take(query.limit).toList(),
      summary: const {'items': 1},
      meta: const {'source': 'mrn_apg_2026', 'snapshot_at': 'store-v1'},
    );
  }
}

void main() {
  tearDown(() => StoreBranchIdentityRegistry.groups.value = const {});
  for (final startCd in [false, true]) {
    testWidgets(
      'MRN navigation isolates page state starting with cd=$startCd',
      (tester) async {
        final selected = ValueNotifier(startCd);
        addTearDown(selected.dispose);
        final store = NavigationSource(false);
        final cd = NavigationSource(true);
        String? exportedFile;
        List<Map<String, dynamic>>? exportedRows;
        await catalog.app(
          tester,
          ValueListenableBuilder<bool>(
            valueListenable: selected,
            builder: (_, isCd, _) => StockManagementPage(
              cd: isCd,
              dataSource: isCd ? cd : store,
              exporter: (rows, file) async {
                exportedRows = rows;
                exportedFile = file;
              },
            ),
          ),
          size: const Size(1650, 1000),
        );
        for (final isCd in [startCd, !startCd, startCd]) {
          if (selected.value != isCd) {
            await tester.enterText(find.byType(TextField).first, 'no matches');
            await tester.pump(const Duration(milliseconds: 400));
            final previousState = tester.state(
              find.byType(StockManagementPage),
            );
            selected.value = isCd;
            await tester.pumpAndSettle();
            expect(
              tester.state(find.byType(StockManagementPage)),
              isNot(previousState),
            );
          }
          final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
          expect(
            grid.columns.first.columnName,
            isCd ? 'warehouse' : 'item_name',
          );
          expect(grid.source.effectiveRows.length, isCd ? 2 : 1);
          expect(
            tester
                .widget<TextField>(find.byType(TextField).first)
                .controller!
                .text,
            isEmpty,
          );
          final items = tester
              .state<StockManagementGridState>(find.byType(StockManagementGrid))
              .visibleItems;
          expect(items.map((item) => item.code), isCd ? ['A', 'A'] : ['STORE']);
          await tester.tap(find.text('Export Excel'));
          await tester.pumpAndSettle();
          expect(
            exportedFile,
            isCd ? 'mrn_cd_overview.xlsx' : 'mrn_overview.xlsx',
          );
          expect(exportedRows!.length, isCd ? 2 : 1);
          expect(exportedRows!.first['Total Qty'], isCd ? 12 : 70);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets(
      'Late MRN response cannot replace cd=$startCd after navigating back',
      (tester) async {
        final selected = ValueNotifier(startCd);
        addTearDown(selected.dispose);
        final ready = NavigationSource(startCd);
        final delayed = NavigationSource(!startCd)..pending = Completer<void>();
        await catalog.app(
          tester,
          ValueListenableBuilder<bool>(
            valueListenable: selected,
            builder: (_, isCd, _) => StockManagementPage(
              cd: isCd,
              dataSource: isCd == startCd ? ready : delayed,
            ),
          ),
          size: const Size(1650, 1000),
        );
        selected.value = !startCd;
        await tester.pump();
        expect(delayed.requests, 1);
        selected.value = startCd;
        await tester.pumpAndSettle();
        delayed.pending!.complete();
        await tester.pumpAndSettle();
        final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
        expect(
          grid.columns.first.columnName,
          startCd ? 'warehouse' : 'item_name',
        );
        expect(grid.source.effectiveRows.length, startCd ? 2 : 1);
        expect(delayed.requests, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'Total Qty is authoritative; bonus note only appears when positive',
    (tester) async {
      await catalog.app(
        tester,
        const StockReceiptQuantity(quantity: 12, bonus: 2),
      );
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Bonus 2'), findsOneWidget);
      expect(find.text('14'), findsNothing);
      await catalog.app(tester, const StockReceiptQuantity(quantity: 8));
      expect(find.textContaining('Bonus'), findsNothing);
      await catalog.app(tester, StockMrnReceiptSummary(item: cdItem('Beta')));
      expect(find.text('BETA'), findsOneWidget);
      StoreBranchIdentityRegistry.groups.value = {'BETA': '71', 'ALPHA': 'APG'};
      await tester.pumpAndSettle();
      expect(find.text('71 BETA'), findsOneWidget);
      expect(find.text('Bonus 2 included'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('mrn-summary-total')),
          matching: find.text('12'),
        ),
        findsOneWidget,
      );
      await catalog.app(
        tester,
        StockMrnReceiptSummary(item: cdItem('Alpha', bonus: 0)),
      );
      expect(find.text('ALPHA'), findsOneWidget);
      expect(find.text('71 ALPHA'), findsNothing);
      expect(find.textContaining('Bonus'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'CD complete register keeps equal product codes from different warehouses',
    () async {
      final rows = (await CdSource().fetchAll()).rows;
      expect(rows.length, 2);
      expect(rows.map((r) => r.registerKey).toSet().length, 2);
      expect(rows.first.receiptTotal, 12);
    },
  );
  testWidgets(
    'CD page has Warehouse first, refreshes 71 labels, searches and exports displayed branch names',
    (tester) async {
      List<Map<String, dynamic>>? exported;
      String? file;
      await catalog.app(
        tester,
        StockManagementPage(
          cd: true,
          dataSource: CdSource(),
          exporter: (rows, name) async {
            exported = rows;
            file = name;
          },
        ),
        size: const Size(1650, 1000),
      );
      expect(find.text('MRN CD Overview'), findsOneWidget);
      final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
      expect(grid.columns.first.columnName, 'warehouse');
      expect(grid.columns[1].columnName, 'item_name');
      StoreBranchIdentityRegistry.groups.value = {'ALPHA': '71', 'BETA': 'APG'};
      await tester.pumpAndSettle();
      expect(find.text('71 ALPHA'), findsOneWidget);
      expect(find.text('BETA'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '71 ALPHA');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SfDataGrid>(find.byType(SfDataGrid))
            .source
            .effectiveRows
            .length,
        1,
      );
      await tester.tap(find.text('Export Excel'));
      await tester.pumpAndSettle();
      expect(file, 'mrn_cd_overview.xlsx');
      expect(exported!.length, 1);
      final row = exported!.single;
      expect(row.keys.first, 'Warehouse');
      expect(row['Warehouse'], '71 ALPHA');
      expect(row['Total Qty'], 12);
      expect(row['Bonus Qty'], 2);
      expect(row.containsKey('Received Qty'), false);
      final report = StockExcelReport(exported!, file!);
      expect(report.sheetName, 'MRN CD Overview');
      expect(
        report.values.single[report.keys.indexOf('Warehouse')],
        '71 ALPHA',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('CD menu is directly below MRN Overview', (tester) async {
    InventoryPageType? selected;
    await catalog.app(
      tester,
      SizedBox(
        width: 270,
        child: StockManagementNavigation(
          selectedPage: InventoryPageType.mrnCdOverview,
          onSelected: (page) => selected = page,
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.text('MRN Overview')).dy,
      lessThan(tester.getTopLeft(find.text('MRN CD Overview')).dy),
    );
    expect(
      tester.getTopLeft(find.text('MRN CD Overview')).dy,
      lessThan(tester.getTopLeft(find.text('Near Expiry')).dy),
    );
    await tester.tap(find.text('MRN CD Overview'));
    expect(selected, InventoryPageType.mrnCdOverview);
  });
  test(
    'CD RPCs, warehouse-bound history and cache stay separate from STORE',
    () async {
      final calls = <String>[];
      final transport = MockClient((request) async {
        final name = request.url.pathSegments.last;
        final params = stockMap(jsonDecode(request.body));
        calls.add(name);
        dynamic result;
        if (name == 'get_stock_workspace_cache_state') {
          result = {
            'mrn': 'store-v1',
            'details': 'store-v1',
            'mrn_cd': 'cd-v1',
          };
        } else if (name.endsWith('_page')) {
          final cd = name.contains('_mrn_cd_');
          final rows = cd
              ? [cdItem('Alpha').data, cdItem('Beta', qty: 8, bonus: 0).data]
              : [
                  {'item_code': 'STORE'},
                ];
          result = {
            'rows': rows.take((params['p_limit'] as num).toInt()).toList(),
            'summary': {'items': rows.length},
            'meta': {
              'source': cd ? 'mrn_cd_apg_2026' : 'mrn_apg_2026',
              'snapshot_at': cd ? 'cd-v1' : 'store-v1',
            },
          };
        } else if (name.endsWith('_register_batch')) {
          expect(params['p_limit'], StockManagementLoadConfig.batchSize);
          final cd = name.contains('_mrn_cd_');
          result = {
            'rows': cd
                ? [cdItem('Alpha').data, cdItem('Beta', qty: 8, bonus: 0).data]
                : [
                    {'item_code': 'STORE'},
                  ],
            'total': cd ? 2 : 1,
            'snapshot_at': cd ? 'cd-v1' : 'store-v1',
          };
        } else if (name == 'get_stock_mrn_cd_item') {
          expect(params['p_warehouse'], 'Beta');
          result = cdItem('Beta', qty: 8, bonus: 0).data;
        } else if (name == 'get_stock_mrn_cd_receipt_history') {
          expect(params['p_warehouse'], 'Beta');
          expect(params['p_limit'], StockManagementLoadConfig.batchSize);
          result = {
            'item_code': 'A',
            'warehouse': 'Beta',
            'rows': [
              {'line_id': 'B-1', 'total_qty': 8, 'bonus': 0},
            ],
            'total': 1,
            'total_qty': 8,
            'bonus': 0,
            'snapshot_version': 'cd-v1',
          };
        } else {
          throw StateError('Unexpected RPC $name');
        }
        return http.Response(
          jsonEncode(result),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = SupabaseClient(
        'https://project.test',
        'public-test',
        httpClient: transport,
      );
      addTearDown(client.dispose);
      final cd = StockManagementRemoteDs(client, cd: true);
      expect((await cd.fetchAll()).rows.length, 2);
      expect(
        (await StockManagementRemoteDs(client).fetchAll()).rows.single.code,
        'STORE',
      );
      expect((await cd.fetchAll()).rows.length, 2);
      expect(
        calls.where((c) => c == 'get_stock_mrn_cd_register_batch').length,
        1,
      );
      final bound = cd.forReceipt(cdItem('Beta'));
      expect((await bound.fetchItem('A')).warehouse, 'Beta');
      expect((await bound.fetchReceiptHistory('A')).receivedQty, 8);
    },
  );
}
