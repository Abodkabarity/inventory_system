import 'dart:convert';

import 'package:daily_order/data/repositories/mismatch_review_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

http.Response jsonResponse(
  Object body,
  http.Request request, [
  int status = 200,
]) => http.Response(
  jsonEncode(body),
  status,
  request: request,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> page(String token, List<int> ids, {bool more = false}) => {
  'rows': [
    for (final id in ids) {'id': id},
  ],
  'snapshot': token,
  'source_version': 'source',
  'total': more ? 2 : ids.length,
  'has_more': more,
  'next_after': ids.last,
  'coverage': <Object>[],
};

void main() {
  test(
    'snapshot conflict discards earlier pages and restarts loading',
    () async {
      final requests = <Map<String, dynamic>>[];
      final client = SupabaseClient(
        'https://inventory.test',
        'test-key',
        httpClient: MockClient((request) async {
          if (request.url.path == '/rest/v1/branches') {
            return jsonResponse(<Object>[], request);
          }
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          switch (requests.length) {
            case 1:
              return jsonResponse(page('old', [1], more: true), request);
            case 2:
              return jsonResponse(
                {'code': 'PT409', 'message': 'review_snapshot_changed'},
                request,
                409,
              );
            default:
              return jsonResponse(page('new', [2, 3]), request);
          }
        }),
      );
      addTearDown(client.dispose);

      final result = await SupabaseMismatchReviewRepository(client).load();
      expect(result.rows.map((row) => row.id), [2, 3]);
      expect(result.token, 'new');
      expect(requests.map((request) => request['p_after']), [0, 1, 0]);
      expect(requests.map((request) => request['p_snapshot']), [
        null,
        'old',
        null,
      ]);
      expect(requests.every((request) => request['p_limit'] == 5000), isTrue);
    },
  );

  test(
    'persistent snapshot conflict stops after three attempts with pauses',
    () async {
      final attempts = <DateTime>[];
      final client = SupabaseClient(
        'https://inventory.test',
        'test-key',
        httpClient: MockClient((request) async {
          if (request.url.path == '/rest/v1/branches') {
            return jsonResponse(<Object>[], request);
          }
          attempts.add(DateTime.now());
          return jsonResponse(
            {'code': 'PT409', 'message': 'review_snapshot_changed'},
            request,
            409,
          );
        }),
      );
      addTearDown(client.dispose);

      await expectLater(
        SupabaseMismatchReviewRepository(client).load(),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', 'PT409'),
        ),
      );
      expect(attempts, hasLength(3));
      expect(
        attempts[1].difference(attempts[0]).inMilliseconds,
        greaterThanOrEqualTo(240),
      );
      expect(
        attempts[2].difference(attempts[1]).inMilliseconds,
        greaterThanOrEqualTo(490),
      );
    },
  );

  test('unrelated errors are returned without retrying', () async {
    var calls = 0;
    final client = SupabaseClient(
      'https://inventory.test',
      'test-key',
      httpClient: MockClient((request) async {
        if (request.url.path == '/rest/v1/branches') {
          return jsonResponse(<Object>[], request);
        }
        calls++;
        return jsonResponse(
          {'code': '42501', 'message': 'Inventory access required'},
          request,
          403,
        );
      }),
    );
    addTearDown(client.dispose);

    await expectLater(
      SupabaseMismatchReviewRepository(client).load(),
      throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '42501')),
    );
    expect(calls, 1);
  });
}
