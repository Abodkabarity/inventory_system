// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';

import 'package:daily_order/data/datasources/remote/stock_catalog_memory_cache.dart';
import 'package:daily_order/data/datasources/remote/stock_catalog_remote_ds.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> detail(
  String code, {
  String? version = 'd1',
  int stock = 10,
}) => {
  'item_code': code,
  'item_name': 'Product $code',
  'total_stock': stock,
  '_cache_version': ?version,
};

class CatalogServer {
  final calls = <String>[];
  final knownVersions = <String?>[];
  String revision = 'r1', detailRevision = 'd1';
  bool legacy = false, failHeader = false, failDetail = false, missing = false;
  bool inconsistentBatch = false, conditionalMissing = false;
  Completer<void>? delayDetail;
  int stock = 10;
  int logins = 0;
  late final SupabaseClient client = SupabaseClient(
    'https://example.supabase.co',
    'test-key',
    httpClient: MockClient((request) async {
      final name = request.url.path.split('/').last;
      calls.add(name);
      final params = request.body.isEmpty
          ? <dynamic, dynamic>{}
          : jsonDecode(request.body) as Map? ?? {};
      Object? data;
      var status = 200;
      switch (name) {
        case 'token':
          final id = (++logins).toString().padLeft(36, '0');
          String part(Object value) => base64Url
              .encode(utf8.encode(jsonEncode(value)))
              .replaceAll('=', '');
          data = {
            'access_token':
                '${part({'alg': 'HS256'})}.${part({'sub': id, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.signature',
            'refresh_token': 'refresh-$id',
            'expires_in': 3600,
            'token_type': 'bearer',
            'user': {
              'id': id,
              'aud': 'authenticated',
              'email': params['email'],
              'app_metadata': {},
              'user_metadata': {},
              'created_at': '2026-10-01T00:00:00Z',
            },
          };
        case 'logout':
          data = {};
        case 'get_stock_catalog_page':
          if (failHeader) {
            status = 403;
            data = {'code': '42501', 'message': 'Inventory access required'};
          } else {
            data = {
              'rows': [],
              'summary': {'items': 2},
              'meta': {
                'refreshed_at': revision,
                if (!legacy) 'catalog_cache_version': revision,
              },
              'categories': ['Medicine'],
              'suppliers': ['Supplier'],
            };
          }
        case 'get_stock_catalog_register_batch':
          data = {
            'rows': [detail('A'), detail('B')],
            'total': inconsistentBatch ? 3 : 2,
            'snapshot_at': revision,
          };
        case 'get_stock_catalog_item' || 'get_stock_catalog_item_if_changed':
          await delayDetail?.future;
          final known = params['p_known_version']?.toString();
          knownVersions.add(known);
          if (conditionalMissing &&
              name == 'get_stock_catalog_item_if_changed') {
            status = 404;
            data = {'code': 'PGRST202', 'message': 'Function not found'};
          } else if (failDetail) {
            status = 403;
            data = {'code': '42501', 'message': 'Inventory access required'};
          } else if (missing) {
            data = null;
          } else if (!legacy && known == detailRevision) {
            data = {
              '_cache_not_modified': true,
              '_cache_version': detailRevision,
            };
          } else {
            data = detail(
              params['p_item_code'] as String,
              version: legacy ? null : detailRevision,
              stock: stock,
            );
          }
        case 'refresh_stock_catalog':
          data = {'status': 'queued'};
        default:
          throw StateError('Unexpected request $name');
      }
      return http.Response(
        jsonEncode(data),
        status,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }),
  );
  StockCatalogRemoteDs get source => StockCatalogRemoteDs(client);
  int count(String name) => calls.where((call) => call == name).length;
}

void main() {
  test(
    'reopening Overview validates header but reuses the complete rows',
    () async {
      final server = CatalogServer();
      addTearDown(server.client.dispose);
      final first = await server.source.fetchAll();
      final progress = <int>[];
      final second = await server.source.fetchAll(
        onProgress: (n, total) => progress.add(n),
      );
      expect(identical(first.rows, second.rows), isTrue);
      expect(server.count('get_stock_catalog_page'), 2);
      expect(server.count('get_stock_catalog_register_batch'), 1);
      expect(progress, [2]);
      expect(second.categories, ['Medicine']);
      server.revision = 'r2';
      await server.source.fetchAll();
      expect(server.count('get_stock_catalog_register_batch'), 2);
    },
  );

  test(
    'legacy servers keep normal full loading, without extra requests',
    () async {
      final server = CatalogServer()..legacy = true;
      addTearDown(server.client.dispose);
      await server.source.fetchAll();
      await server.source.fetchAll();
      await server.source.fetchItem('A');
      await server.source.fetchItem('A');
      expect(server.count('get_stock_catalog_register_batch'), 2);
      expect(server.count('get_stock_catalog_item'), 2);
      expect(server.count('get_stock_catalog_item_if_changed'), 0);
    },
  );

  test(
    'reopening a product validates its revision and avoids the full payload',
    () async {
      final server = CatalogServer();
      addTearDown(server.client.dispose);
      final first = await server.source.fetchItem('A');
      final second = await server.source.fetchItem('A');
      expect(identical(first, second), isTrue);
      expect(first.data.containsKey('_cache_version'), isFalse);
      expect(server.knownVersions, [null, 'd1']);
      server.detailRevision = 'd2';
      server.stock = 42;
      final changed = await server.source.fetchItem('A');
      expect(changed.number('total_stock'), 42);
      expect(identical(first, changed), isFalse);
      expect(server.count('get_stock_catalog_item'), 1);
      expect(server.count('get_stock_catalog_item_if_changed'), 2);
    },
  );

  test('simultaneous detail requests share one network operation', () async {
    final server = CatalogServer()..delayDetail = Completer<void>();
    addTearDown(server.client.dispose);
    final one = server.source.fetchItem('A');
    final two = server.source.fetchItem('A');
    expect(identical(one, two), isTrue);
    server.delayDetail!.complete();
    final result = await Future.wait([one, two]);
    expect(identical(result.first, result.last), isTrue);
    expect(server.count('get_stock_catalog_item'), 1);
  });

  test('refresh invalidates completed entries and old requests', () async {
    final server = CatalogServer();
    addTearDown(server.client.dispose);
    await server.source.fetchAll();
    await server.source.fetchItem('A');
    await server.source.requestRefresh();
    await server.source.fetchAll();
    await server.source.fetchItem('A');
    expect(server.count('get_stock_catalog_register_batch'), 2);
    expect(server.knownVersions, [null, null]);
    server.delayDetail = Completer<void>();
    final old = server.source.fetchItem('B');
    final rejected = expectLater(old, throwsStateError);
    await server.source.requestRefresh();
    server.delayDetail!.complete();
    await rejected;
  });

  test(
    'header permission failure never serves the previous complete register',
    () async {
      final server = CatalogServer();
      addTearDown(server.client.dispose);
      await server.source.fetchAll();
      server.failHeader = true;
      await expectLater(
        server.source.fetchAll(),
        throwsA(isA<PostgrestException>()),
      );
      server.failHeader = false;
      await server.source.fetchAll();
      expect(server.count('get_stock_catalog_register_batch'), 2);
    },
  );

  test(
    'detail errors and removed products never fall back to stale quantities',
    () async {
      final server = CatalogServer();
      addTearDown(server.client.dispose);
      await server.source.fetchItem('A');
      server.failDetail = true;
      await expectLater(
        server.source.fetchItem('A'),
        throwsA(isA<PostgrestException>()),
      );
      server.failDetail = false;
      await server.source.fetchItem('A');
      expect(server.knownVersions, [null, 'd1', null]);
      server.missing = true;
      await expectLater(server.source.fetchItem('A'), throwsStateError);
    },
  );

  test('clients never share another account or server memory', () async {
    final one = CatalogServer();
    final two = CatalogServer()..stock = 77;
    addTearDown(one.client.dispose);
    addTearDown(two.client.dispose);
    expect((await one.source.fetchItem('A')).number('total_stock'), 10);
    expect((await two.source.fetchItem('A')).number('total_stock'), 77);
    expect(two.knownVersions, [null]);
  });

  test(
    'signing out and changing account clears the same client memory',
    () async {
      final server = CatalogServer();
      addTearDown(server.client.dispose);
      await server.client.auth.signInWithPassword(
        email: 'one@example.com',
        password: 'test',
      );
      await server.source.fetchAll();
      await server.source.fetchItem('A');
      await server.client.auth.signOut(scope: SignOutScope.local);
      await server.client.auth.signInWithPassword(
        email: 'two@example.com',
        password: 'test',
      );
      server.stock = 77;
      await server.source.fetchAll();
      expect((await server.source.fetchItem('A')).number('total_stock'), 77);
      expect(server.knownVersions, [null, null]);
      expect(server.count('get_stock_catalog_register_batch'), 2);
    },
  );

  test(
    'an older response cannot overwrite a new account in-flight request',
    () async {
      final cache = StockCatalogMemoryCache();
      final oldResponse = Completer<Map<String, dynamic>?>();
      final newResponse = Completer<Map<String, dynamic>?>();
      final old = cache.item('A', (_) => oldResponse.future);
      final rejected = expectLater(old, throwsStateError);
      cache.clear();
      final fresh = cache.item('A', (_) => newResponse.future);
      oldResponse.complete(detail('A', stock: 10));
      await rejected;
      final repeated = cache.item(
        'A',
        (_) async => throw StateError('Duplicate network request'),
      );
      expect(identical(repeated, fresh), isTrue);
      newResponse.complete(detail('A', stock: 77));
      expect((await fresh).number('total_stock'), 77);
      expect((await repeated).number('total_stock'), 77);
    },
  );

  test('details use a bounded LRU cache', () async {
    final cache = StockCatalogMemoryCache(maxDetails: 2);
    final versions = <String?>[];
    Future<void> open(String code) async {
      await cache.item(code, (known) async {
        versions.add(known);
        return known == null
            ? detail(code)
            : {'_cache_not_modified': true, '_cache_version': known};
      });
    }

    await open('A');
    await open('B');
    await open('A');
    await open('C');
    await open('B');
    expect(versions, [null, null, 'd1', null, null]);
  });

  test(
    'clearing an account during a request prevents late data from being returned',
    () async {
      final cache = StockCatalogMemoryCache();
      final pending = Completer<Map<String, dynamic>?>();
      final result = cache.item('A', (_) => pending.future);
      final rejected = expectLater(result, throwsStateError);
      cache.clear();
      pending.complete(detail('A'));
      await rejected;
      String? received = 'unexpected';
      await cache.item('A', (known) async {
        received = known;
        return detail('A');
      });
      expect(received, isNull);
    },
  );

  test(
    'invalid not-modified messages and wrong product identities are rejected',
    () async {
      final cache = StockCatalogMemoryCache();
      await expectLater(
        cache.item(
          'A',
          (_) async => {'_cache_not_modified': true, '_cache_version': 'd1'},
        ),
        throwsStateError,
      );
      await expectLater(
        cache.item('A', (_) async => detail('B')),
        throwsStateError,
      );
      await cache.item('A', (_) async => detail('A'));
      await expectLater(
        cache.item(
          'A',
          (_) async => {'_cache_not_modified': true, '_cache_version': 'wrong'},
        ),
        throwsStateError,
      );
    },
  );

  test('partial and cancelled registers are never cached', () async {
    final server = CatalogServer();
    addTearDown(server.client.dispose);
    await expectLater(
      server.source.fetchAll(isCancelled: () => true),
      throwsStateError,
    );
    expect(server.count('get_stock_catalog_register_batch'), 0);
    await server.source.fetchAll();
    expect(server.count('get_stock_catalog_register_batch'), 1);
  });

  test('a failed mixed snapshot is fully reloaded on retry', () async {
    final server = CatalogServer()..inconsistentBatch = true;
    addTearDown(server.client.dispose);
    await expectLater(server.source.fetchAll(), throwsStateError);
    server.inconsistentBatch = false;
    final result = await server.source.fetchAll();
    expect(result.rows.length, 2);
    expect(server.count('get_stock_catalog_register_batch'), 2);
  });

  test(
    'rolling back the conditional RPC safely falls back to the legacy response',
    () async {
      final server = CatalogServer();
      addTearDown(server.client.dispose);
      await server.source.fetchItem('A');
      server.conditionalMissing = true;
      server.legacy = true;
      await server.source.fetchItem('A');
      await server.source.fetchItem('A');
      expect(server.count('get_stock_catalog_item'), 3);
      expect(server.count('get_stock_catalog_item_if_changed'), 1);
    },
  );
}
