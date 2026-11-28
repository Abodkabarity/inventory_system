import 'dart:convert';

import 'package:daily_order/core/utils/max_adjustment_export_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final history in [false, true]) {
    test(
      'complete ${history ? 'UUID history' : 'current'} export survives API row caps',
      () async {
        Object id(int index) => history
            ? '00000000-0000-0000-0000-${index.toString().padLeft(12, '0')}'
            : index;
        final requests = <http.Request>[];
        final progress = <int>[];
        final client = SupabaseClient(
          'https://example.supabase.co',
          'test-key',
          httpClient: MockClient((request) async {
            requests.add(request);
            final query = request.url.queryParameters;
            expect(
              request.url.path,
              '/rest/v1/${history ? 'max_adj_log' : 'max_adj'}',
            );
            expect(query.containsKey('offset'), isFalse);
            if (query['select'] == 'id') {
              expect(query['order'], startsWith('id.desc'));
              return http.Response(
                jsonEncode([
                  {'id': id(9000)},
                ]),
                200,
                request: request,
                headers: {
                  'content-type': 'application/json',
                  'content-range': '0-0/9000',
                },
              );
            }
            expect(query['limit'], '4000');
            expect(query['order'], startsWith('id.asc'));
            final filters = request.url.queryParametersAll['id']!;
            expect(filters, contains('lte.${id(9000)}'));
            final cursor = filters
                .where((value) => value.startsWith('gt.'))
                .firstOrNull;
            final after = cursor == null
                ? 0
                : int.parse(cursor.split(history ? '-' : '.').last);
            // Simulate a 1,000-row API cap, despite requesting 4,000. Short
            // responses must not be treated as the last page of the report.
            return http.Response(
              jsonEncode([
                for (
                  var index = after + 1;
                  index <= after + 1000 && index <= 9000;
                  index++
                )
                  {'id': id(index), 'item_code': '00$index'},
              ]),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);
        final rows = await loadMaxAdjustmentExport(
          client: client,
          history: history,
          onProgress: (loaded, total) {
            expect(total, 9000);
            progress.add(loaded);
          },
        );
        expect(rows.length, 9000);
        expect(rows.first['id'], id(1));
        expect(rows.last['id'], id(9000));
        expect(rows.map((row) => row['id']).toSet().length, 9000);
        expect(requests.length, 10);
        expect(progress, [
          0,
          1000,
          2000,
          3000,
          4000,
          5000,
          6000,
          7000,
          8000,
          9000,
        ]);
      },
    );
  }

  test('empty tables finish without a data request', () async {
    var calls = 0;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      httpClient: MockClient((request) async {
        calls++;
        return http.Response(
          '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json', 'content-range': '*/0'},
        );
      }),
    );
    addTearDown(client.dispose);
    expect(
      await loadMaxAdjustmentExport(client: client, history: true),
      isEmpty,
    );
    expect(calls, 1);
  });

  test(
    'database timeout reduces the read batch without moving the cursor',
    () async {
      final limits = <String>[];
      final cursors = <List<String>>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          final q = request.url.queryParameters;
          if (q['select'] == 'id') {
            return http.Response(
              '[{"id":3000}]',
              200,
              request: request,
              headers: {
                'content-type': 'application/json',
                'content-range': '0-0/3000',
              },
            );
          }
          limits.add(q['limit']!);
          final filters = request.url.queryParametersAll['id']!;
          cursors.add(filters);
          if (limits.length == 1) {
            return http.Response(
              '{"code":"57014","message":"statement timeout"}',
              500,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          final cursor = filters.where((v) => v.startsWith('gt.')).firstOrNull;
          final after = cursor == null ? 0 : int.parse(cursor.substring(3));
          return http.Response(
            jsonEncode([
              for (var i = after + 1; i <= after + 2000 && i <= 3000; i++)
                {'id': i},
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final rows = await loadMaxAdjustmentExport(client: client, history: true);
      expect(rows.length, 3000);
      expect(limits, ['4000', '2000', '2000']);
      expect(cursors[0], cursors[1]);
      expect(cursors[2], contains('gt.2000'));
    },
  );

  test(
    'other server errors fail immediately and remain retryable by the user',
    () async {
      var calls = 0;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          calls++;
          return http.Response(
            '{"code":"42501","message":"permission denied"}',
            403,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        loadMaxAdjustmentExport(client: client, history: true),
        throwsA(isA<PostgrestException>()),
      );
      expect(calls, 1);
    },
  );

  for (final invalidRows in [
    <Map<String, dynamic>>[],
    [
      {'id': 1},
      {'id': 1},
    ],
    [
      {'id': 1},
      {'id': 2},
    ], // correct count but missing the pinned final ID
  ]) {
    test(
      'changed or duplicate batches never produce a partial export: $invalidRows',
      () async {
        var calls = 0;
        final client = SupabaseClient(
          'https://example.supabase.co',
          'test-key',
          httpClient: MockClient((request) async {
            calls++;
            return http.Response(
              jsonEncode(
                calls == 1
                    ? [
                        {'id': 3},
                      ]
                    : invalidRows,
              ),
              200,
              request: request,
              headers: {
                'content-type': 'application/json',
                'content-range': '0-0/2',
              },
            );
          }),
        );
        addTearDown(client.dispose);
        await expectLater(
          loadMaxAdjustmentExport(client: client, history: false),
          throwsStateError,
        );
      },
    );
  }
}
