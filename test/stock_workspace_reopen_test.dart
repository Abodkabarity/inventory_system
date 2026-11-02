// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/data/datasources/remote/stock_catalog_remote_ds.dart';
import 'package:daily_order/data/datasources/remote/stock_expiry_remote_ds.dart';
import 'package:daily_order/data/datasources/remote/stock_management_remote_ds.dart';
import 'package:daily_order/domain/entities/stock_expiry.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_catalog_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_expiry_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_management_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

class ReopenServer {
  final calls = <String>[];
  final limits = <int>[];
  String revision = 'v1', name = 'Saved product';
  bool denied = false;
  int discoveries = 0;
  Completer<void>? validation;
  late final client = SupabaseClient(
    'https://example.supabase.co',
    'test-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      final rpc = request.url.pathSegments.last;
      final decoded = request.body.isEmpty ? null : jsonDecode(request.body);
      final params = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      calls.add(rpc);
      final checking =
          rpc == 'get_stock_workspace_cache_state' ||
          rpc == 'get_stock_catalog_page' ||
          rpc == 'prepare_stock_expiry_workspace';
      if (checking) await validation?.future;
      if (checking && denied) {
        return http.Response(
          jsonEncode({'code': '42501', 'message': 'Inventory access required'}),
          403,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }
      final cd = rpc.contains('mrn_cd');
      final row = {
        'item_code': 'A',
        'item_name': name,
        'total_stock': 12,
        'warehouse': 'Raw Branch',
        if (cd) 'register_key': jsonEncode(['Raw Branch', 'A']),
        'last_mrn_date': '2026-10-29',
        'last_receipt_date': '2026-10-29',
        'expiry_date': '2027-01-01',
        'days_left': 60,
        'receipt_fingerprint': 'receipt-v1',
      };
      Object result;
      if (rpc == 'get_stock_workspace_cache_state' ||
          rpc == 'prepare_stock_expiry_workspace') {
        if (rpc == 'prepare_stock_expiry_workspace' &&
            params['p_known_discovery_version'] != revision) {
          discoveries++;
        }
        result = {
          'mrn': revision,
          'mrn_cd': revision,
          'expiry': revision,
          'details': revision,
          'discovery': revision,
        };
      } else if (rpc.endsWith('_page') || rpc.endsWith('_register_batch')) {
        limits.add(params['p_limit'] as int);
        result = {
          'rows': [row],
          'total': 1,
          'summary': {'items': 1, 'pending': 1},
          'snapshot_at': revision,
          'meta': {
            'refreshed_at': revision,
            'snapshot_at': revision,
            'catalog_cache_version': revision,
          },
        };
      } else if (rpc == 'branches') {
        result = <Object>[];
      } else {
        result = <String, Object>{};
      }
      return http.Response(
        jsonEncode(result),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }),
  );

  StockCatalogRemoteDs get catalog => StockCatalogRemoteDs(client);
  StockManagementRemoteDs mrn({bool cd = false}) =>
      StockManagementRemoteDs(client, cd: cd);
  StockExpiryRemoteDs get expiry => StockExpiryRemoteDs(client);

  int bulkCalls(String kind) => calls
      .where(
        (name) => kind == 'expiry'
            ? name == 'get_stock_expiry_page'
            : name ==
                  'get_stock_${kind == 'catalog'
                      ? 'catalog'
                      : kind == 'cd'
                      ? 'mrn_cd'
                      : 'management'}_register_batch',
      )
      .length;

  Widget page(String kind) => switch (kind) {
    'catalog' => StockCatalogPage(dataSource: catalog),
    'expiry' => StockExpiryPage(dataSource: expiry),
    _ => StockManagementPage(
      dataSource: mrn(cd: kind == 'cd'),
      cd: kind == 'cd',
    ),
  };

  Object? preview(String kind) => switch (kind) {
    'catalog' => catalog.previewRegister,
    'expiry' => expiry.previewRegister(const StockExpiryQuery()),
    _ => mrn(cd: kind == 'cd').previewRegister,
  };
}

Future<void> showPage(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  late ReopenServer server;
  setUp(() {
    server = ReopenServer();
    // Initialize and dispose SDK isolates outside the widget's fake clock.
    addTearDown(server.client.dispose);
  });
  for (final kind in ['catalog', 'mrn', 'cd', 'expiry']) {
    for (final denied in [false, true]) {
      testWidgets(
        '$kind reopens immediately and handles denied=$denied validation',
        (tester) async {
          tester.view.physicalSize = const Size(1440, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          StoreBranchIdentityRegistry.groups.value = {'RAW BRANCH': '71'};
          addTearDown(
            () => StoreBranchIdentityRegistry.groups.value = const {},
          );
          await showPage(tester, server.page(kind));
          await tester.pumpAndSettle();
          expect(
            find.byType(SfDataGrid),
            findsOneWidget,
            reason: tester
                .widgetList<Text>(find.byType(Text))
                .map((w) => w.data)
                .join(' | '),
          );
          expect(server.bulkCalls(kind), 1);
          expect(server.preview(kind), isNotNull);
          await showPage(tester, const SizedBox());
          final pending = server.validation = Completer<void>();
          server.denied = denied;
          await showPage(tester, server.page(kind));
          // The server has not replied, but complete saved rows are already visible.
          expect(find.byType(SfDataGrid), findsOneWidget);
          expect(
            find.textContaining(RegExp('Saved product', caseSensitive: false)),
            findsWidgets,
          );
          expect(find.byType(LinearProgressIndicator), findsWidgets);
          final exportButton = find.ancestor(
            of: find.text('Export Excel'),
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton,
            ),
          );
          expect(
            tester.widget<ButtonStyleButton>(exportButton).onPressed,
            isNull,
          );
          expect(server.bulkCalls(kind), 1);
          if (kind == 'cd') expect(find.text('71 RAW BRANCH'), findsWidgets);
          pending.complete();
          server.validation = null;
          await tester.pumpAndSettle();
          if (denied) {
            expect(find.byType(SfDataGrid), findsNothing);
            expect(server.preview(kind), isNull);
            expect(
              find.textContaining('Inventory access required'),
              findsWidgets,
            );
          } else {
            expect(server.bulkCalls(kind), 1);
            await showPage(tester, const SizedBox());
            server.revision = 'v2';
            server.name = 'Updated product';
            final changed = server.validation = Completer<void>();
            await showPage(tester, server.page(kind));
            expect(
              find.textContaining(
                RegExp('Saved product', caseSensitive: false),
              ),
              findsWidgets,
            );
            changed.complete();
            server.validation = null;
            await tester.pumpAndSettle();
            expect(
              find.textContaining(
                RegExp('Updated product', caseSensitive: false),
              ),
              findsWidgets,
            );
            expect(server.bulkCalls(kind), 2);
          }
          expect(tester.takeException(), isNull);
          await showPage(tester, const SizedBox());
        },
      );
    }
  }

  test(
    'expiry summary and register share discovery without mixing query caches',
    () async {
      await server.expiry.fetchSummary();
      await server.expiry.fetchAll(const StockExpiryQuery());
      await server.expiry.fetchSummary();
      expect(server.discoveries, 1);
      expect(server.limits, [1, 4000]);
      expect(
        server.expiry.previewRegister(const StockExpiryQuery()),
        isNotNull,
      );
      expect(
        server.expiry.previewRegister(
          const StockExpiryQuery(reviewState: 'reviewed'),
        ),
        isNull,
      );
      expect(server.mrn().previewRegister, isNull);
      expect(server.mrn(cd: true).previewRegister, isNull);
      server.revision = 'v2';
      await server.expiry.fetchSummary();
      expect(server.discoveries, 2);
      expect(server.limits, [1, 4000, 1]);
    },
  );
}
