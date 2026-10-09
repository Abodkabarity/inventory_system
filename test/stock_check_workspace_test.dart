// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'package:daily_order/data/datasources/remote/stock_check_workspace_remote_ds.dart';
import 'package:daily_order/domain/entities/stock_check_campaign.dart';
import 'package:daily_order/domain/entities/stock_check_kpi_comparison.dart';
import 'package:daily_order/domain/entities/stock_check_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

StockCheckTask counted(
  String code,
  num system,
  num actual, {
  String branch = 'Branch A',
  String status = 'submitted',
}) => StockCheckTask.fromMap({
  'id': code,
  'batch_id': 'batch',
  'branch_name': branch,
  'item_code': code,
  'item_name': code,
  'system_qty': system,
  'actual_qty': actual,
  'status': status,
});

http.Response jsonResponse(http.Request request, String body, int status) =>
    http.Response(
      body,
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

void main() {
  test(
    'sending requires a signed-in app user before any profile lookup',
    () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(
          (_) async => throw StateError('Unexpected lookup'),
        ),
      );
      addTearDown(client.dispose);
      await expectLater(
        StockCheckWorkspaceRemoteDs(client).currentSender(),
        throwsA(isA<StateError>()),
      );
    },
  );
  for (final profile in [
    {'user_name': '  Maya  ', 'is_active': true},
    {'user_name': 'Maya', 'is_active': false},
    {'user_name': '   ', 'is_active': true},
    {'role': 'branch', 'user_name': null, 'is_active': true},
    {'role': ' Branch ', 'user_name': '   ', 'is_active': true},
    null,
  ]) {
    test('sender profile validation: $profile', () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          return jsonResponse(
            request,
            jsonEncode(profile == null ? [] : [profile]),
            200,
          );
        }),
      );
      addTearDown(client.dispose);
      await client.auth.setInitialSession(
        jsonEncode({
          'access_token': 'test-token',
          'token_type': 'bearer',
          'user': {'id': 'maya-id'},
        }),
      );
      final future = StockCheckWorkspaceRemoteDs(client).currentSender();
      if ((profile?['role'] ?? '').toString().trim().toLowerCase() ==
          'branch') {
        expect(await future, (id: 'maya-id', name: ''));
      } else if (profile?['is_active'] == true &&
          profile?['user_name'] == '  Maya  ') {
        expect(await future, (id: 'maya-id', name: 'Maya'));
      } else {
        await expectLater(future, throwsA(isA<StateError>()));
      }
      expect(requests.single.url.path, endsWith('/app_users'));
      expect(requests.single.url.queryParameters['user_id'], 'eq.maya-id');
    });
  }
  test(
    'branch summary keeps removed items with the same normalized branch',
    () {
      final report = StockCheckKpiComparison(
        [
          counted('A', 10, 10, branch: ' BRANCH A '),
          counted('B', 10, 10, branch: ' BRANCH A '),
        ],
        [counted('A', 10, 10, branch: 'branch a')],
      );
      expect(report.branches.length, 1);
      expect(report.branches.values.single.items.length, 2);
    },
  );
  test(
    'crossing the accuracy tolerance is an improvement even for a small change',
    () {
      final report = StockCheckKpiComparison(
        [counted('A', 10, 10.015)],
        [counted('A', 10, 10.009)],
      );
      expect(report.items.single.result, 'Improved');
      expect(report.delta, 100);
    },
  );
  test('legacy campaigns keep an unknown sender and regular purpose', () {
    final campaign = StockCheckCampaign({
      'batch_id': 'old',
      'total': 10,
      'submitted': 3,
    });
    expect(campaign.kind, 'regular');
    expect(campaign.senderId, isEmpty);
    expect(campaign.senderLabel, 'Sender not recorded');
    expect(campaign.period, isEmpty);
    expect(campaign.accuracy, isNull);
    expect(campaign.pending, 7);
  });
  test(
    'campaign filters separate purpose, sender identity, status and quarter',
    () {
      final campaign = StockCheckCampaign({
        'check_kind': 'kpi',
        'sender_user_id': 'maya-id',
        'sender_name': 'Maya',
        'kpi_year': 2026,
        'kpi_quarter': 3,
        'total': 10,
        'submitted': 8,
        'expires_at': '2026-10-01',
      });
      expect(campaign.matches(kind: 'regular'), isFalse);
      expect(campaign.matches(kind: 'kpi', sender: 'other-id'), isFalse);
      expect(campaign.matches(kind: 'kpi', sender: 'maya-id'), isTrue);
      expect(
        campaign.matches(
          kind: 'kpi',
          search: 'maya',
          status: 'overdue',
          now: DateTime(2026, 10, 8),
        ),
        isTrue,
      );
      expect(campaign.matches(kind: 'kpi', search: 'Q3'), isTrue);
      expect(campaign.matches(kind: 'kpi', status: 'completed'), isFalse);
      expect(
        campaign.matches(
          kind: 'kpi',
          status: 'pending',
          now: DateTime(2026, 10, 8),
        ),
        isFalse,
      );
    },
  );
  test(
    'KPI accuracy uses submitted common pairs and excludes changed assortment',
    () {
      final report = StockCheckKpiComparison(
        [
          counted('A', 10, 8),
          counted('B', 10, 10),
          counted('removed', 10, 10),
          counted('pending', 10, 10, status: 'pending'),
        ],
        [
          counted('A', 10, 10),
          counted('B', 10, 10),
          counted('added', 10, 0),
          counted('pending', 10, 10),
        ],
      );
      expect(report.comparable.length, 2);
      expect(report.previousAccuracy, 50);
      expect(report.currentAccuracy, 100);
      expect(report.delta, 50);
      expect(
        report.items.map((e) => e.result),
        containsAll([
          'Improved',
          'Unchanged',
          'Added',
          'Removed',
          'Awaiting counts',
        ]),
      );
      expect(report.branches['Branch A']!.delta, 50);
    },
  );
  test('empty and disjoint quarters have unknown accuracy, never zero', () {
    final report = StockCheckKpiComparison(
      [counted('old', 10, 10)],
      [counted('new', 10, 10)],
    );
    expect(report.delta, isNull);
    expect(report.currentAccuracy, isNull);
    expect(report.comparable, isEmpty);
  });
  test('same code in different branches is never compared', () {
    final report = StockCheckKpiComparison(
      [counted('A', 10, 10, branch: 'First')],
      [counted('A', 10, 5, branch: 'Second')],
    );
    expect(report.comparable, isEmpty);
    expect(report.branches.length, 2);
  });
  test(
    'case and whitespace normalize item keys; tolerance and direction remain correct',
    () {
      final report = StockCheckKpiComparison(
        [counted(' a ', 10, 10.01, branch: 'BRANCH A'), counted('B', 10, 8)],
        [counted('A', 10, 10), counted('B', 10, 12)],
      );
      expect(report.comparable.length, 2);
      expect(report.items.first.result, 'Unchanged');
      expect(report.items.last.result, 'Direction changed');
    },
  );
  test(
    'workspace loads summaries only, paginates full details and caches reopen',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('stock_check_campaigns')) {
            return jsonResponse(
              request,
              jsonEncode([
                {'batch_id': 'batch', 'source': 'inventory', 'total': 2505},
              ]),
              200,
            );
          }
          final start = int.parse(request.url.queryParameters['offset'] ?? '0');
          final end = (start + 1000).clamp(0, 2505);
          return jsonResponse(
            request,
            jsonEncode([
              for (var i = start; i < end; i++)
                {'id': '$i', 'batch_id': 'batch', 'item_code': '$i'},
            ]),
            200,
          );
        }),
      );
      final ds = StockCheckWorkspaceRemoteDs(client);
      final summaries = await ds.campaigns(['inventory']);
      expect(summaries.single.total, 2505);
      expect(requests.length, 1);
      expect(requests.single.url.path, endsWith('stock_check_campaigns'));
      final rows = await ds.details('batch', 2505);
      expect(rows.length, 2505);
      expect(rows.map((e) => e.id).toSet().length, 2505);
      expect(requests.length, 4);
      expect(identical(await ds.details('batch', 2505), rows), isTrue);
      expect(requests.length, 4);
      ds.invalidate();
      await ds.details('batch', 2505);
      expect(requests.length, 7);
      await client.dispose();
    },
  );
  test('failed or incomplete campaign loads are retryable', () async {
    var fail = true;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'key',
      httpClient: MockClient(
        (request) async => jsonResponse(
          request,
          jsonEncode(
            fail
                ? []
                : [
                    {'id': 'one', 'batch_id': 'b'},
                  ],
          ),
          200,
        ),
      ),
    );
    final ds = StockCheckWorkspaceRemoteDs(client);
    await expectLater(ds.details('b', 1), throwsStateError);
    fail = false;
    expect((await ds.details('b', 1)).single.id, 'one');
    await client.dispose();
  });
}
