// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';

import 'package:daily_order/data/datasources/remote/zone_stock_check_remote_ds.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> task(int id, {String branch = 'Nadd Al Hamar - DXB'}) => {
  'id': id.toString().padLeft(6, '0'),
  'batch_id': 'same-campaign',
  'title': 'Stock Check',
  'source': id.isEven ? 'inventory' : 'store',
  'branch_name': branch,
  'item_code': '$id',
  'status': id < 20 ? 'pending' : 'submitted',
  'sent_at': '2026-10-15T09:00:00Z',
  'expires_at': '2026-10-25T09:00:00Z',
  'updated_at': '2026-10-15T09:00:00Z',
};

class Fixture {
  List<Map<String, dynamic>> rows;
  final int cap;
  final requests = <http.Request>[];
  void Function(http.Request)? beforeRequest;
  List<Map<String, dynamic>> Function(List<Map<String, dynamic>>)? changePage;
  late final client = SupabaseClient(
    'https://example.supabase.co',
    'key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient(respond),
  );

  Future<http.Response> respond(http.Request request) async {
    requests.add(request);
    beforeRequest?.call(request);
    final params = request.url.queryParameters;
    expect(params.containsKey('source'), isFalse);
    final branches = params['branch_name']!;
    var filtered = rows
        .where((row) => branches.contains('"${row['branch_name']}"'))
        .toList();
    if (params['status'] == 'eq.pending') {
      filtered = filtered.where((row) => row['status'] == 'pending').toList();
    }
    final count = filtered.length;
    final snapshot = params['select'] == 'id,updated_at';
    if (snapshot) {
      expect(params['order'], 'updated_at.desc.nullslast,id.asc.nullslast');
      filtered.sort((a, b) {
        final byUpdate = '${b['updated_at']}'.compareTo('${a['updated_at']}');
        return byUpdate == 0 ? '${a['id']}'.compareTo('${b['id']}') : byUpdate;
      });
      filtered = filtered.take(1).toList();
    } else {
      expect(params['order'], 'id.asc.nullslast');
      expect(params['limit'], '5000');
      expect(params.containsKey('offset'), isFalse);
      final cursor = params['id']?.substring(3);
      filtered.sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
      filtered = filtered
          .where(
            (row) => cursor == null || '${row['id']}'.compareTo(cursor) > 0,
          )
          .take(cap)
          .toList();
      filtered = changePage?.call(filtered) ?? filtered;
    }
    return http.Response(
      jsonEncode(filtered),
      200,
      request: request,
      headers: {
        'content-type': 'application/json',
        'content-range': filtered.isEmpty
            ? '*/$count'
            : '0-${filtered.length - 1}/$count',
      },
    );
  }

  Fixture(this.rows, {this.cap = 1000});

  ZoneStockCheckRemoteDs get source {
    addTearDown(client.dispose);
    return ZoneStockCheckRemoteDs(client);
  }
}

void main() {
  test(
    'tied campaign dates and a smaller server cap retain all 2,501 unique rows',
    () async {
      final fixture = Fixture([for (var i = 0; i < 2501; i++) task(i)]);
      final source = fixture.source;
      final details = await source.load(['Nadd Al Hamar - DXB']);
      final pending = await source.load([
        'Nadd Al Hamar - DXB',
      ], pendingOnly: true);
      expect(details.length, 2501);
      expect(details.map((row) => row.id).toSet().length, 2501);
      expect(pending.length, 20);
      expect(
        details.where((row) => row.isPending).map((row) => row.id),
        pending.map((row) => row.id),
      );
    },
  );

  test(
    'multiple zones cannot query the same branch in different chunks',
    () async {
      final branches = [for (var i = 0; i < 23; i++) 'Branch $i'];
      final fixture = Fixture([
        for (var i = 0; i < branches.length; i++) task(i, branch: branches[i]),
      ]);
      final rows = await fixture.source.load([
        ...branches,
        branches.first,
        branches.last,
        '',
      ]);
      expect(rows.length, 23);
      expect(rows.map((row) => row.id).toSet().length, 23);
      expect(
        fixture.requests
            .where((r) => r.url.queryParameters['select'] == '*')
            .length,
        2,
      );
    },
  );

  test('concurrent submissions retry the pending snapshot', () async {
    final fixture = Fixture([for (var i = 0; i < 20; i++) task(i)], cap: 7);
    var changed = false;
    fixture.beforeRequest = (request) {
      if (!changed && request.url.queryParameters.containsKey('id')) {
        changed = true;
        fixture.rows[0] = {
          ...fixture.rows[0],
          'status': 'submitted',
          'updated_at': '2026-10-20T10:00:00Z',
        };
      }
    };
    final rows = await fixture.source.load([
      'Nadd Al Hamar - DXB',
    ], pendingOnly: true);
    expect(rows.length, 19);
    expect(rows.any((row) => row.id == '000000'), isFalse);
  });

  test('updates with unchanged row count also retry the snapshot', () async {
    final fixture = Fixture([for (var i = 0; i < 24; i++) task(i)], cap: 7);
    var changed = false;
    fixture.beforeRequest = (request) {
      if (!changed && request.url.queryParameters.containsKey('id')) {
        changed = true;
        fixture.rows[0] = {
          ...fixture.rows[0],
          'status': 'submitted',
          'updated_at': '2026-10-20T10:00:00Z',
        };
      }
    };
    final rows = await fixture.source.load(['Nadd Al Hamar - DXB']);
    expect(rows.length, 24);
    expect(rows.first.isSubmitted, isTrue);
  });

  for (final corruption in ['duplicate', 'missing', 'wrong branch']) {
    test(
      'rejects $corruption rows instead of publishing wrong zone totals',
      () async {
        final fixture = Fixture([task(0), task(1)]);
        fixture.changePage = (page) => switch (corruption) {
          'duplicate' => [task(0), task(0)],
          'missing' => [],
          _ => [task(0, branch: 'Unmanaged branch'), task(1)],
        };
        await expectLater(
          fixture.source.load(['Nadd Al Hamar - DXB']),
          throwsStateError,
        );
      },
    );
  }

  test('empty branch scope makes no requests', () async {
    final fixture = Fixture([]);
    expect(await fixture.source.load(['', '  ']), isEmpty);
    expect(fixture.requests, isEmpty);
  });
}
