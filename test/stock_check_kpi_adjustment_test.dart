import 'dart:convert';
import 'package:daily_order/data/datasources/remote/stock_check_kpi_adjustment_remote_ds.dart';
import 'package:daily_order/domain/entities/stock_check_campaign.dart';
import 'package:daily_order/domain/entities/stock_check_kpi_adjustment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, Object> row(
  String code, {
  String branch = 'Raw Branch',
  num qty = 0,
  int count = 0,
  bool complete = true,
}) => {
  'branch': branch,
  'item_code': code,
  'qty': '$qty',
  'movement_count': count,
  'complete': complete,
};
Map<String, Object?> page(
  List<Map<String, Object>> rows, {
  int? total,
  bool more = false,
  String snapshot = 'snapshot',
}) => {
  'rows': rows,
  'total': total ?? rows.length,
  'has_more': more,
  'snapshot': snapshot,
  'from_date': '2026-07-08',
  'through_date': '2026-10-28',
  'next_branch': rows.lastOrNull?['branch'],
  'next_code': rows.lastOrNull?['item_code'],
};

void main() {
  final projects = [
    StockCheckCampaign({'batch_id': 'q1'}),
  ];
  test(
    'adjustment labels show recorded quantities and counts regardless of coverage',
    () {
      expect(
        const StockCheckKpiAdjustment(
          quantity: 0,
          movementCount: 0,
          complete: true,
        ).exportValue,
        '',
      );
      expect(
        const StockCheckKpiAdjustment(
          quantity: 0,
          movementCount: 2,
          complete: true,
        ).exportValue,
        '0 (2 adjustments)',
      );
      expect(
        const StockCheckKpiAdjustment(
          quantity: -.005,
          movementCount: 1,
          complete: true,
        ).exportValue,
        '-0.005 (1 adjustment)',
      );
      expect(
        const StockCheckKpiAdjustment(
          quantity: 0,
          movementCount: 0,
          complete: false,
        ).label,
        '',
      );
      expect(
        const StockCheckKpiAdjustment(
          quantity: 3.5,
          movementCount: 2,
          complete: false,
        ).label,
        '3.5 (2 adjustments)',
      );
    },
  );
  test(
    '5000-row bulk pages preserve signed quantities and one consistent date/snapshot',
    () async {
      final requests = <Map<String, dynamic>>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'key',
        httpClient: MockClient((request) async {
          final params = jsonDecode(request.body) as Map<String, dynamic>;
          requests.add(params);
          expect(
            request.url.path,
            endsWith('/rpc/stock_check_kpi_adjustments'),
          );
          expect(params['p_limit'], 5000);
          final body = requests.length == 1
              ? page(
                  [
                    for (var i = 0; i < 5000; i++)
                      row('P${i.toString().padLeft(5, '0')}'),
                  ],
                  total: 5001,
                  more: true,
                )
              : page([row('P05000', qty: -3.005, count: 2)], total: 5001);
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final data = await StockCheckKpiAdjustmentRemoteDs(client).load(projects);
      expect(data.values.length, 5001);
      expect(data.forItem(' RAW BRANCH ', 'p05000')!.quantity, -3.005);
      expect(data.period, '2026-07-08 → 2026-10-28');
      expect(requests[1]['p_snapshot'], 'snapshot');
      expect(requests[1]['p_through'], '2026-10-28');
      expect(requests[1]['p_after_code'], 'P04999');
      expect(requests[1]['p_after_branch'], 'Raw Branch');
    },
  );
  for (final failure in ['duplicate', 'snapshot', 'incomplete', 'nonfinite']) {
    test('rejects $failure data', () async {
      var attempt = 0;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'key',
        httpClient: MockClient((request) async {
          attempt++;
          final Object body = switch (failure) {
            'duplicate' => page([row('A'), row(' a ')]),
            'incomplete' => page([row('A')], total: 2),
            'nonfinite' => page([row('A', qty: double.infinity)]),
            _ =>
              attempt == 1
                  ? page([row('A')], total: 2, more: true)
                  : page([row('B')], total: 2, snapshot: 'changed'),
          };
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        StockCheckKpiAdjustmentRemoteDs(client).load(projects),
        throwsStateError,
      );
    });
  }
}
