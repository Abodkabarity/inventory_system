import 'dart:convert';

import 'package:daily_order/core/config/online_overview_local_config.dart';
import 'package:daily_order/data/datasources/remote/online_overview_remote_ds.dart';
import 'package:daily_order/domain/entities/online_overview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'online_overview_fixtures.dart';

Map<String, dynamic> auditRow({Map<String, dynamic> extra = const {}}) => {
  'branch_name': 'Web Shop',
  'current_rows': 1,
  'current_qty': 10,
  'opening_qty': 10,
  'reconciled': true,
  'movements': <dynamic>[],
  ...extra,
};

void main() {
  test(
    'branch availability reads only the summary RPC for the visible generation',
    () async {
      final calls = <String>[];
      final client = SupabaseClient(
        'https://online-test.invalid',
        'test-anon',
        httpClient: MockClient((request) async {
          calls.add(request.url.pathSegments.last);
          expect(calls.last, 'get_local_online_overview_availability');
          expect(jsonDecode(request.body), {
            'p_generation': 'visible-generation',
          });
          return http.Response(
            jsonEncode({'generation': 'visible-generation', 'rows': []}),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final result = await OnlineOverviewRemoteDs(
        client,
      ).branchAvailability(generation: 'visible-generation');
      expect(result['generation'], 'visible-generation');
      expect(calls, hasLength(1));
    },
  );
  test(
    'product stock uses the visible generation instead of mixing snapshots',
    () async {
      final calls = <String>[];
      final client = SupabaseClient(
        'https://online-test.invalid',
        'test-anon',
        httpClient: MockClient((request) async {
          calls.add(request.url.pathSegments.last);
          expect(calls.last, 'get_local_online_overview_stock');
          final params = jsonDecode(request.body);
          expect(params['p_generation'], 'visible-generation');
          expect(params['p_item_code'], 'P');
          return http.Response(
            jsonEncode([
              {'branch_name': 'Web Shop', 'stock': 3, 'reported': true},
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final rows = await OnlineOverviewRemoteDs(
        client,
      ).stockBreakdown('P', generation: 'visible-generation');
      expect(rows.single['stock'], 3);
      expect(calls.length, 1);
    },
  );
  test('exposure never extends past the loaded monthly sales cutoff', () {
    final result = OnlineProductAudit.fromMap({
      'status': 'ready',
      'through': '2026-10-28',
      'stock_day': '2026-10-28',
      'branches': [auditRow()],
    }, exposureThrough: DateTime.utc(2026, 4, 30));
    final row = result.branches['WEB SHOP']!;
    expect(row.verified, isTrue);
    expect(
      row.stockedDays,
      DateTime.utc(2026, 4, 30).difference(DateTime.utc(2026)).inDays,
    );
    expect(row.stockedDays, lessThan(180));
    expect(row.currentStock, 10);
  });
  final through = DateTime.utc(2026, 10, 28);
  OnlineBranchAudit audit(Map<String, dynamic> row) =>
      OnlineBranchAudit.fromEvidence(row, through, through);
  test(
    'stock exposure starts after opening and requires endpoint matching',
    () {
      final result = audit(auditRow());
      expect(result.verified, isTrue);
      expect(result.stockedDays, through.difference(DateTime.utc(2026)).inDays);
      expect(result.emptyDays, 0);
      expect(audit(auditRow(extra: {'current_qty': 9})).verified, isFalse);
    },
  );
  test('unreconciled history never creates stock exposure', () {
    final result = audit(auditRow(extra: {'reconciled': false}));
    expect(result.verified, isFalse);
    expect(result.stockedDays, 0);
    expect(result.currentStock, 10);
  });
  test('missing current reports remain unknown', () {
    expect(
      audit(
        auditRow(extra: {'current_rows': 0, 'current_qty': null}),
      ).currentStock,
      isNull,
    );
  });
  test('empty and adjustment days are distinct', () {
    final result = audit(
      auditRow(
        extra: {
          'opening_qty': 0,
          'current_qty': 0,
          'movements': [
            {
              'day': '2026-02-01',
              'net': 0,
              'incoming': 0,
              'outgoing': 0,
              'adjustment': true,
            },
          ],
        },
      ),
    );
    expect(result.verified, isTrue);
    expect(result.stockedDays, 0);
    expect(result.emptyDays, through.difference(DateTime.utc(2026)).inDays - 1);
  });
  test('same-day incoming cannot hide possible intraday stockout', () {
    final result = audit(
      auditRow(
        extra: {
          'movements': [
            {'day': '2026-02-01', 'net': 0, 'incoming': 12, 'outgoing': 12},
          ],
        },
      ),
    );
    expect(result.verified, isTrue);
    expect(
      result.stockedDays,
      through.difference(DateTime.utc(2026)).inDays - 1,
    );
  });
  test(
    'negative reconstructed balance blocks even when the endpoint matches',
    () {
      final result = audit(
        auditRow(
          extra: {
            'movements': [
              {'day': '2026-02-01', 'net': -20, 'incoming': 0, 'outgoing': 20},
              {'day': '2026-02-02', 'net': 20, 'incoming': 20, 'outgoing': 0},
            ],
          },
        ),
      );
      expect(result.verified, isFalse);
    },
  );
  test('duplicate movement days and wrong signed totals are rejected', () {
    final day = {'day': '2026-02-01', 'net': 0, 'incoming': 0, 'outgoing': 0};
    expect(
      audit(
        auditRow(
          extra: {
            'movements': [day, day],
          },
        ),
      ).verified,
      isFalse,
    );
    expect(
      audit(
        auditRow(
          extra: {
            'movements': [
              {...day, 'net': 1},
            ],
          },
        ),
      ).verified,
      isFalse,
    );
  });
  test('nonfinite and malformed movement values are rejected', () {
    expect(audit(auditRow(extra: {'opening_qty': 'NaN'})).verified, isFalse);
    expect(
      audit(
        auditRow(
          extra: {
            'movements': [
              {'day': 'not-a-date'},
            ],
          },
        ),
      ).verified,
      isFalse,
    );
  });
  test('assumed zero evidence retains its estimated provenance', () {
    final result = audit(auditRow(extra: {'assumed_opening': true}));
    expect(result.verified, isTrue);
    expect(result.estimated, isTrue);
    expect(result.note, contains('estimate'));
  });
  test('invalid RPC status and duplicate branches are rejected', () {
    expect(
      () => OnlineProductAudit.fromMap({'status': 'awaiting_data'}),
      throwsStateError,
    );
    expect(
      () => OnlineProductAudit.fromMap({
        'status': 'ready',
        'through': '2026-10-28',
        'stock_day': '2026-10-28',
        'branches': [auditRow(), auditRow()],
      }),
      throwsStateError,
    );
  });
  test(
    'all bulk requests ask for 5000 and advance by actual server cap',
    () async {
      final offsets = <int>[];
      final rows = await loadOnlineSource(
        fetch: (offset, limit) async {
          expect(limit, OnlineOverviewLocalConfig.batchSize);
          expect(limit, 5000);
          offsets.add(offset);
          return OnlineSourcePage([
            for (var i = offset; i < offset + 2 && i < 5; i++) {'id': '$i'},
          ], 5);
        },
        identity: (row) => '${row['id']}',
      );
      expect(offsets, [0, 2, 4]);
      expect(rows.length, 5);
    },
  );
  test('empty complete source is allowed, partial source is not', () async {
    expect(
      await loadOnlineSource(
        fetch: (_, _) async => const OnlineSourcePage([], 0),
        identity: (_) => '',
      ),
      isEmpty,
    );
    await expectLater(
      loadOnlineSource(
        fetch: (_, _) async => const OnlineSourcePage([], 2),
        identity: (_) => '',
      ),
      throwsStateError,
    );
  });
  test('duplicate, changed-count and overflow pages are rejected', () async {
    await expectLater(
      loadOnlineSource(
        fetch: (_, _) async => const OnlineSourcePage([
          {'id': 'a'},
          {'id': 'a'},
        ], 2),
        identity: (row) => '${row['id']}',
      ),
      throwsStateError,
    );
    await expectLater(
      loadOnlineSource(
        fetch: (offset, _) async => OnlineSourcePage([
          {'id': '$offset'},
        ], offset == 0 ? 2 : 3),
        identity: (row) => '${row['id']}',
      ),
      throwsStateError,
    );
    await expectLater(
      loadOnlineSource(
        fetch: (_, _) async => const OnlineSourcePage([
          {'id': 'a'},
          {'id': 'b'},
        ], 1),
        identity: (row) => '${row['id']}',
      ),
      throwsStateError,
    );
  });
  test(
    'cancellation before and after a page prevents publishing rows',
    () async {
      var cancelled = true;
      await expectLater(
        loadOnlineSource(
          fetch: (_, _) async => const OnlineSourcePage([], 0),
          identity: (_) => '',
          isCancelled: () => cancelled,
        ),
        throwsStateError,
      );
      cancelled = false;
      await expectLater(
        loadOnlineSource(
          fetch: (_, _) async {
            cancelled = true;
            return const OnlineSourcePage([], 0);
          },
          identity: (_) => '',
          isCancelled: () => cancelled,
        ),
        throwsStateError,
      );
    },
  );
  test('malformed sales months and quantities cannot enter ranking', () {
    expect(
      () => OnlineSalesMonth.fromMap({'month': '13/2026'}, 2026),
      throwsStateError,
    );
    expect(
      () => OnlineSalesMonth.fromMap({'month': '09/2025'}, 2026),
      throwsStateError,
    );
    expect(
      () =>
          OnlineSalesMonth.fromMap({'month': '09/2026', 'online': 'NaN'}, 2026),
      throwsStateError,
    );
  });

  for (final scenario in ['ready', 'changed', 'duplicate', 'short', 'empty']) {
    test(
      'prepared register rejects inconsistent snapshots; $scenario',
      () async {
        final paths = <String>[];
        var states = 0;
        var batches = 0;
        final client = SupabaseClient(
          'https://online-test.invalid',
          'test-anon',
          httpClient: MockClient((request) async {
            final path = request.url.pathSegments.last;
            paths.add(path);
            Object response;
            final generation = scenario == 'changed' && states > 0
                ? 'new'
                : 'G';
            if (path == 'get_local_online_overview_state') {
              states++;
              response = {
                'status': 'complete',
                'generation': scenario == 'empty' ? null : generation,
                'meta': {
                  'items': 2,
                  'refreshed_at': '2026-10-30T06:00:00Z',
                  'branches': [
                    {'name': 'Web Shop', 'group': '71'},
                  ],
                },
              };
            } else if (path == 'get_local_online_overview_batch') {
              final params = jsonDecode(request.body);
              expect(params['p_limit'], 5000);
              expect(params['p_generation'], 'G');
              expect(params['p_branch'], '');
              expect(params['p_scope'], 'onlineOnly');
              batches++;
              final code = scenario == 'duplicate' || batches == 1
                  ? 'FAST'
                  : 'OTHER';
              response = {
                'generation': 'G',
                'total': 2,
                'rows': scenario == 'short' && batches > 1
                    ? []
                    : [
                        {
                          'code': code,
                          'item': onlineItem(code).data,
                          'rank': 'a',
                          'sales26': 900,
                          'price_known': true,
                          'retail': 10,
                          'purchase_status': 'BACK TO STOCK',
                          'reason': 'Prepared on server',
                        },
                      ],
              };
            } else {
              throw StateError('Unexpected raw source request: $path');
            }
            return http.Response(
              jsonEncode(response),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);
        final source = OnlineOverviewRemoteDs(client);
        if (scenario == 'ready') {
          final result = await source.load();
          expect(result.preparedRows!.length, 2);
          expect(result.preparedRows!.first.sales26, 900);
          expect(result.preparedRows!.first.rank, OnlineRank.a);
          expect(result.sales, isEmpty);
          expect(result.generation, 'G');
          await source.load();
          expect(
            batches,
            2,
            reason: 'Unchanged completed snapshots reuse prepared rows',
          );
        } else if (scenario == 'empty') {
          await expectLater(
            source.load(),
            throwsA(isA<OnlineSnapshotNotReady>()),
          );
        } else {
          await expectLater(source.load(), throwsStateError);
        }
        expect(
          paths.every((p) => p.startsWith('get_local_online_overview_')),
          isTrue,
          reason: 'No raw sales, catalog or purchase-status downloads',
        );
      },
    );
  }
}
