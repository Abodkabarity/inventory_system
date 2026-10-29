// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'package:daily_order/data/datasources/remote/stock_management_remote_ds.dart';
import 'package:daily_order/data/datasources/remote/stock_expiry_remote_ds.dart';
import 'package:daily_order/domain/entities/stock_expiry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WorkspaceServer {
  final calls = <String>[];
  final params = <Map<String, dynamic>>[];
  String revision = 'r1', details = 'd1', note = '';
  int stock = 10, rows = 2, scans = 0, logins = 0;
  bool fail = false, missing = false, legacy = false, changeDuringLoad = false;
  Completer<void>? delay;
  final started = Completer<void>();
  late final client = SupabaseClient(
    'https://example.supabase.co',
    'test-key',
    httpClient: MockClient((request) async {
      final name = request.url.path.split('/').last;
      calls.add(name);
      final decoded = request.body.isEmpty ? null : jsonDecode(request.body);
      final p = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      params.add(p);
      Object? result;
      var status = 200;
      Map<String, dynamic> state() => {
        'mrn': revision,
        'expiry': revision,
        'discovery': revision,
        'details': details,
      };
      Map<String, dynamic> product(String code) => {
        'item_code': code,
        'item_name': code,
        'total_stock': stock,
        'reference': 'REF-1',
        'last_3_sales': 3,
        'mrn_details': {'reference': 'REF-1', 'last_mrn_no': 'M1'},
      };
      Map<String, dynamic> alert() => {
        'item_code': 'A',
        'expiry_date': '2026-11-01',
        'last_receipt_date': '2026-10-03',
        'note': note,
        'review_updated_at': revision,
        'product_data': product('A'),
      };
      if (fail &&
          (name == 'get_stock_workspace_cache_state' ||
              name == 'prepare_stock_expiry_workspace')) {
        status = 403;
        result = {'code': '42501', 'message': 'Inventory access required'};
      } else if (legacy &&
          [
            'get_stock_workspace_cache_state',
            'prepare_stock_expiry_workspace',
            'get_stock_management_product_details',
          ].contains(name)) {
        status = 404;
        result = {'code': 'PGRST202', 'message': 'RPC not installed'};
      } else {
        switch (name) {
          case 'token':
            final id = (++logins).toString().padLeft(36, '0');
            String part(Object value) => base64Url
                .encode(utf8.encode(jsonEncode(value)))
                .replaceAll('=', '');
            result = {
              'access_token':
                  '${part({'alg': 'HS256'})}.${part({'sub': id, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.signature',
              'refresh_token': 'refresh-$id',
              'expires_in': 3600,
              'token_type': 'bearer',
              'user': {
                'id': id,
                'aud': 'authenticated',
                'email': p['email'],
                'app_metadata': {},
                'user_metadata': {},
                'created_at': '2026-10-01T00:00:00Z',
              },
            };
          case 'get_stock_workspace_cache_state':
            result = state();
          case 'prepare_stock_expiry_workspace':
            if (p['p_known_discovery_version'] != revision) scans++;
            result = state();
          case 'get_stock_management_page':
            result = {
              'rows': [],
              'summary': {'items': rows},
              'meta': {'snapshot_at': '2026-10-20T00:00:00Z'},
            };
          case 'get_stock_management_register_batch':
            expect(p['p_limit'], 5000);
            final offset = p['p_offset'] as int;
            result = {
              'rows': [
                for (var i = offset; i < rows && i < offset + 5000; i++)
                  product('$i'),
              ],
              'total': rows,
              'snapshot_at': '2026-10-20T00:00:00Z',
            };
            if (changeDuringLoad) {
              revision = 'r2';
              changeDuringLoad = false;
            }
          case 'get_stock_expiry_page':
            expect(p['p_limit'], 5000);
            result = {
              'rows': [alert()],
              'total': 1,
              'summary': {'pending': 1},
              'meta': {'as_of': '2026-10-20'},
            };
          case 'get_stock_management_product_details' ||
              'get_stock_management_item':
            if (!started.isCompleted) started.complete();
            await delay?.future;
            result = missing ? null : product(p['p_item_code']);
          case 'get_stock_expiry_item':
            result = missing ? null : alert();
          case 'save_stock_expiry_review':
            note = p['p_note'];
            revision = 'r2';
            result = {'updated_at': revision};
          default:
            result = {};
        }
      }
      return http.Response(
        jsonEncode(result),
        status,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }),
  );
  StockManagementRemoteDs get mrn => StockManagementRemoteDs(client);
  StockExpiryRemoteDs get expiry => StockExpiryRemoteDs(client);
  int count(String name) => calls.where((c) => c == name).length;
}

void main() {
  late WorkspaceServer server;
  setUp(() {
    server = WorkspaceServer();
  });
  tearDown(() async {
    await server.client.dispose();
  });

  test(
    'MRN caches only a complete 5000-row register and validates every reopen',
    () async {
      server.rows = 5001;
      final first = await server.mrn.fetchAll();
      expect(first.rows.length, 5001);
      expect(server.count('get_stock_management_register_batch'), 2);
      final again = await server.mrn.fetchAll();
      expect(identical(first, again), isTrue);
      expect(server.count('get_stock_management_register_batch'), 2);
      expect(server.count('get_stock_workspace_cache_state'), 3);
    },
  );
  test('changed source reloads same-count stock register', () async {
    await server.mrn.fetchAll();
    server.revision = 'r2';
    server.stock = 77;
    final current = await server.mrn.fetchAll();
    expect(current.rows.first.number('total_stock'), 77);
    expect(server.count('get_stock_management_register_batch'), 2);
  });
  test(
    'source changes during loading reject mixed snapshots and do not cache',
    () async {
      server.changeDuringLoad = true;
      await expectLater(server.mrn.fetchAll(), throwsStateError);
      await server.mrn.fetchAll();
      expect(server.count('get_stock_management_register_batch'), 2);
    },
  );
  test(
    'expiry reopens validate without rescanning receipts or reloading rows',
    () async {
      final first = await server.expiry.fetchAll(const StockExpiryQuery());
      final second = await server.expiry.fetchAll(const StockExpiryQuery());
      expect(identical(first, second), isTrue);
      expect(server.scans, 1);
      expect(server.count('get_stock_expiry_page'), 1);
      server.revision = 'next-day';
      await server.expiry.fetchAll(const StockExpiryQuery());
      expect(server.scans, 2);
      expect(server.count('get_stock_expiry_page'), 2);
    },
  );
  test('expiry query keys isolate reviewed and pending results', () async {
    await server.expiry.fetchAll(const StockExpiryQuery());
    await server.expiry.fetchAll(
      const StockExpiryQuery(reviewState: 'reviewed'),
    );
    await server.expiry.fetchAll(const StockExpiryQuery());
    expect(server.count('get_stock_expiry_page'), 3);
  });
  test(
    'saving a review invalidates both notes and register before dispatch',
    () async {
      final first = await server.expiry.fetchAll(const StockExpiryQuery());
      final alert = await server.expiry.fetchItem(first.rows.single);
      await server.expiry.save(alert, note: 'Inspect batch', action: 'note');
      final refreshed = await server.expiry.fetchItem(alert);
      expect(refreshed.note, 'Inspect batch');
      expect(server.count('get_stock_expiry_item'), 2);
      await server.expiry.fetchAll(const StockExpiryQuery());
      expect(server.count('get_stock_expiry_page'), 2);
    },
  );
  test(
    'unified details keep reference and MRN evidence and reuse memory',
    () async {
      final a = await server.mrn.fetchItem('A');
      final b = await server.mrn.fetchItem('A');
      expect(identical(a, b), isTrue);
      expect(a.text('reference'), 'REF-1');
      expect(a.data['mrn_details']['last_mrn_no'], 'M1');
      expect(a.number('last_3_sales'), 3);
      expect(server.count('get_stock_management_product_details'), 1);
      server.details = 'annual-sales-corrected';
      server.stock = 20;
      expect((await server.mrn.fetchItem('A')).number('total_stock'), 20);
    },
  );
  test('validation errors never return saved stock or expiry notes', () async {
    await server.mrn.fetchAll();
    final first = await server.expiry.fetchAll(const StockExpiryQuery());
    await server.expiry.fetchItem(first.rows.single);
    server.fail = true;
    await expectLater(
      server.mrn.fetchAll(),
      throwsA(isA<PostgrestException>()),
    );
    await expectLater(
      server.expiry.fetchItem(first.rows.single),
      throwsA(isA<PostgrestException>()),
    );
    await expectLater(
      server.expiry.fetchAll(const StockExpiryQuery()),
      throwsA(isA<PostgrestException>()),
    );
  });
  test('same-product requests share one in-flight detail request', () async {
    server.delay = Completer<void>();
    final first = server.mrn.fetchItem('A');
    await server.started.future;
    final second = server.mrn.fetchItem('A');
    server.delay!.complete();
    expect(identical(await first, await second), isTrue);
    expect(server.count('get_stock_management_product_details'), 1);
  });
  test(
    'refresh clears pending requests and late results cannot repopulate cache',
    () async {
      server.delay = Completer<void>();
      final first = server.mrn.fetchItem('A');
      final failed = expectLater(first, throwsStateError);
      await server.started.future;
      await server.mrn.requestRefresh();
      server.delay!.complete();
      await failed;
      await server.mrn.fetchItem('A');
      expect(server.count('get_stock_management_product_details'), 2);
    },
  );
  test(
    'deleted product does not fall back to previously cached facts',
    () async {
      await server.mrn.fetchItem('A');
      server.details = 'd2';
      server.missing = true;
      await expectLater(server.mrn.fetchItem('A'), throwsStateError);
    },
  );
  test(
    'LRU limits detail memory and client instances never share quantities',
    () async {
      for (var i = 0; i < 29; i++) {
        await server.mrn.fetchItem('$i');
      }
      await server.mrn.fetchItem('0');
      expect(server.count('get_stock_management_product_details'), 30);
      final other = WorkspaceServer()..stock = 99;
      try {
        expect((await other.mrn.fetchItem('0')).number('total_stock'), 99);
      } finally {
        await other.client.dispose();
      }
    },
  );
  test('older servers retain uncached loading and original item RPC', () async {
    server.legacy = true;
    await server.mrn.fetchItem('A');
    await server.mrn.fetchItem('A');
    expect(server.count('get_stock_management_item'), 2);
    await server.expiry.fetchAll(const StockExpiryQuery());
    await server.expiry.fetchAll(const StockExpiryQuery());
    expect(server.count('refresh_stock_expiry_watch'), 2);
    expect(server.count('get_stock_expiry_page'), 2);
  });
  test('cancelled register is not remembered', () async {
    var cancelled = false;
    await expectLater(
      server.mrn.fetchAll(
        isCancelled: () => cancelled,
        onProgress: (_, _) => cancelled = true,
      ),
      throwsA(isA<StockManagementLoadCancelled>()),
    );
    await server.mrn.fetchAll();
    expect(server.count('get_stock_management_register_batch'), 2);
  });
  test(
    'actual account changes and sign-out clear a shared client cache',
    () async {
      await server.client.auth.signInWithPassword(
        email: 'one@example.com',
        password: 'test',
      );
      await server.mrn.fetchItem('A');
      server.stock = 99;
      await server.client.auth.signInWithPassword(
        email: 'two@example.com',
        password: 'test',
      );
      expect((await server.mrn.fetchItem('A')).number('total_stock'), 99);
      expect(server.count('get_stock_management_product_details'), 2);
      await server.client.auth.signOut();
      server.stock = 55;
      expect((await server.mrn.fetchItem('A')).number('total_stock'), 55);
      expect(server.count('get_stock_management_product_details'), 3);
    },
  );
}
