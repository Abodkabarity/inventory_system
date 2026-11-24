// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:daily_order/core/config/stock_management_load_config.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/data/datasources/remote/stock_catalog_remote_ds.dart';
import 'package:daily_order/data/datasources/remote/zone_stock_catalog_remote_ds.dart';
import 'package:daily_order/domain/entities/inventory_page.dart';
import 'package:daily_order/domain/entities/stock_catalog.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_management_navigation.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_catalog_product_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Server {
  final calls = <String>[];
  final parameters = <String, Map>{};
  var version = 'zone-1';
  var deny = false;
  late final client = SupabaseClient(
    'https://example.supabase.co',
    'test',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      final name = request.url.path.split('/').last;
      final params = request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Map? ?? {};
      calls.add(name);
      parameters[name] = params;
      var status = 200;
      Object? data;
      if (name.startsWith('get_zone_') && deny) {
        status = 403;
        data = {'code': '42501', 'message': 'Zone access required'};
      } else if (name == 'get_zone_overview_header') {
        expect(params, isEmpty);
        data = {
          'rows': [],
          'summary': {'items': 1},
          'meta': {
            'scope_kind': 'zone',
            'catalog_cache_version': version,
            'reference_version': version,
            'refreshed_at': version,
          },
          'categories': ['Medicine'],
          'suppliers': ['Supplier'],
        };
      } else if (name == 'get_zone_overview_batch' ||
          name == 'get_zone_overview_item') {
        if (params['p_version'] != version) {
          status = 409;
          data = {'code': 'PT409', 'message': 'Scope changed'};
        } else {
          final row = {
            'item_code': 'A',
            'item_name': 'Your product',
            'total_stock': 12,
            'branches': [
              {'branch': 'Your branch', 'branch_group': '71', 'stock': 2},
            ],
          };
          if (name == 'get_zone_overview_batch') {
            expect(params['p_limit'], StockManagementLoadConfig.batchSize);
            expect(params['p_limit'], lessThanOrEqualTo(5000));
            data = {
              'rows': [row],
              'total': 1,
              'snapshot_at': version,
              'reference_version': version,
            };
          } else {
            data = {...row, '_cache_version': version};
          }
        }
      } else if (name == 'get_stock_catalog_page') {
        data = {
          'rows': [],
          'summary': {'items': 1},
          'meta': {'catalog_cache_version': 'global', 'refreshed_at': 'global'},
        };
      } else if (name == 'get_stock_catalog_register_batch') {
        data = {
          'rows': [
            {
              'item_code': 'SECRET',
              'item_name': 'Other branches stock',
              'total_stock': 99999,
            },
          ],
          'total': 1,
          'snapshot_at': 'global',
        };
      } else if (name == 'zone-stock-product-gallery') {
        data = {'images': []};
      } else {
        throw StateError('Unexpected endpoint $name');
      }
      return http.Response(
        jsonEncode(data),
        status,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

void main() {
  test(
    'zone cache and RPCs are isolated from global/Main data; all batches/details are pinned',
    () async {
      final originalGroups = StoreBranchIdentityRegistry.groups.value;
      addTearDown(
        () => StoreBranchIdentityRegistry.groups.value = originalGroups,
      );
      final server = _Server();
      addTearDown(server.client.dispose);
      final global = StockCatalogRemoteDs(server.client);
      await global.fetchAll();
      final saved = global.previewRegister;
      final zone = ZoneStockCatalogRemoteDs(server.client);
      server.calls.clear();
      expect(zone.previewRegister, isNull);
      final first = await zone.fetchAll();
      expect(first.rows.single.code, 'A');
      expect(global.previewRegister, same(saved));
      expect(global.previewRegister!.rows.single.code, 'SECRET');
      expect(await zone.refreshState(), isNull);
      final detail = await zone.fetchItem('A');
      expect(detail.list('branches').single['branch'], 'Your branch');
      expect(
        StoreBranchIdentityRegistry.displayName('Your branch'),
        '71 Your branch',
      );
      expect(
        StoreBranchIdentityRegistry.exportValue('branch', 'Your branch'),
        '71 Your branch',
      );
      expect(
        StoreBranchIdentityRegistry.displayName('Other branch'),
        'Other branch',
      );
      await zone.imageService.gallery('A');
      expect(server.calls, everyElement(isNot(startsWith('get_stock_'))));
      expect(server.calls, contains('zone-stock-product-gallery'));
      expect(
        server.calls.where((c) => c == 'get_zone_overview_batch').length,
        1,
      );
      await zone.fetchAll();
      expect(
        server.calls.where((c) => c == 'get_zone_overview_batch').length,
        1,
      );
      expect(zone.previewRegister, isNull);
      server.version = 'zone-2';
      await zone.fetchAll();
      expect(
        server.calls.where((c) => c == 'get_zone_overview_batch').length,
        2,
      );
      expect(
        server.parameters['get_zone_overview_batch']!['p_version'],
        'zone-2',
      );
      server.version = 'zone-3';
      await expectLater(
        zone.fetchRegisterBatch(0),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', 'PT409'),
        ),
      );
      await expectLater(
        zone.fetchItem('A'),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', 'PT409'),
        ),
      );
      final before = server.calls.length;
      await expectLater(zone.requestRefresh(), throwsUnsupportedError);
      expect(server.calls.length, before);
      server.deny = true;
      await expectLater(
        zone.fetchAll(),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '42501'),
        ),
      );
      expect(zone.memoryCache.previewRegister, isNull);
      expect(global.previewRegister, same(saved));
    },
  );

  testWidgets(
    'zone product dialog uses its scoped metadata without querying the branch directory',
    (tester) async {
      final server = (await tester.runAsync(() async {
        final server = _Server();
        server.client;
        return server;
      }))!;
      addTearDown(() => tester.runAsync(server.client.dispose));
      final originalGroups = StoreBranchIdentityRegistry.groups.value;
      addTearDown(
        () => StoreBranchIdentityRegistry.groups.value = originalGroups,
      );
      StoreBranchIdentityRegistry.groups.value = const {'YOUR BRANCH': '71'};
      tester.view.physicalSize = const Size(1500, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final zone = ZoneStockCatalogRemoteDs(server.client);
      final detail = StockCatalogItem({
        'item_code': 'A',
        'item_name': 'Your product',
        'total_stock': 12,
        'branches': [
          {'branch': 'Your branch', 'branch_group': '71', 'stock': 2},
        ],
        'meta': {'scope_kind': 'zone'},
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StockCatalogProductDialog(
              item: detail,
              source: zone,
              loadItem: () async => detail,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(server.calls, isEmpty);
      expect(
        find.text('Total = STORE + your assigned branches.'),
        findsOneWidget,
      );
      expect(find.text('Total = STORE + all branches.'), findsNothing);
      expect(StoreBranchIdentityRegistry.groups.value.keys, ['YOUR BRANCH']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ordinary zones get only Overview; Main retains the original four-page menu',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var selected = InventoryPageType.stockManagement;
      Widget app(bool zone) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 270,
            child: StockManagementNavigation(
              selectedPage: selected,
              overviewOnly: zone,
              showOnlineOverview: false,
              onSelected: (page) => selected = page,
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      expect(find.text('Overview'), findsOneWidget);
      for (final name in [
        'MRN Overview',
        'MRN CD Overview',
        'Near Expiry',
        'Online Overview',
      ]) {
        expect(find.text(name), findsNothing);
      }
      await tester.tap(find.text('Overview'));
      expect(selected, InventoryPageType.stockManagement);
      await tester.tap(find.text('Stock Management'));
      await tester.pumpAndSettle();
      expect(find.text('Overview'), findsNothing);
      await tester.tap(find.text('Stock Management'));
      await tester.pumpAndSettle();
      expect(find.text('Overview'), findsOneWidget);
      await tester.pumpWidget(app(false));
      await tester.pumpAndSettle();
      for (final name in [
        'Overview',
        'MRN Overview',
        'MRN CD Overview',
        'Near Expiry',
      ]) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('Online Overview'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
