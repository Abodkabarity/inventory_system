import 'dart:convert';

import 'package:daily_order/core/utils/purchase_shortage_report.dart';
import 'package:daily_order/data/datasources/remote/inventory_remote_ds.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('requests exactly one dated workbook and forces its download', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({'signedURL': '/object/sign/report.xlsx?token=test'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    final url = Uri.parse(
      await InventoryRemoteDs(
        client,
      ).fetchPurchaseShortageExportUrl(runDate: '2026-10-07'),
    );
    expect(requests, hasLength(1));
    expect(
      Uri.decodeFull(requests.single.url.path),
      '/storage/v1/object/sign/shotrage purchase/10-2026/Items Shortage Include Assortment 07-10-2026.xlsx',
    );
    expect(jsonDecode(requests.single.body)['expiresIn'], 60);
    expect(
      url.queryParameters['download'],
      PurchaseShortageReport.fileName('2026-10-07'),
    );
    expect(url.queryParameters['token'], 'test');
  });

  test(
    'missing today does not fall back to an older report or recalculate',
    () async {
      var calls = 0;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          calls++;
          return http.Response(
            jsonEncode({
              'statusCode': '404',
              'error': 'not_found',
              'message': 'Object not found',
            }),
            400,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        InventoryRemoteDs(
          client,
        ).fetchPurchaseShortageExportUrl(runDate: '2026-10-07'),
        throwsA(predicate((e) => e.toString().contains('not ready yet'))),
      );
      expect(calls, 1);
    },
  );
}
