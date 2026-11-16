import 'dart:convert';

import 'package:daily_order/data/datasources/remote/inventory_daily_order_query.dart';
import 'package:daily_order/data/datasources/remote/inventory_remote_ds.dart';
import 'package:daily_order/domain/entities/daily_order_query.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'search builds a literal match for all four fields and raw branch aliases',
    () {
      final request = InventoryDailyOrderQuery(
        DailyOrderQuery(
          runDate: '2026-11-11',
          search: '71 Alpha',
          displayedBranchMatches: ['ALPHA'],
        ),
      );
      expect(
        request.predicates.single,
        'item_name.ilike."%71 Alpha%",item_code.ilike."%71 Alpha%",'
        'barcode.ilike."%71 Alpha%",branch.ilike."%71 Alpha%",branch.ilike."ALPHA"',
      );

      final punctuation = InventoryDailyOrderQuery(
        DailyOrderQuery(runDate: '2026-11-11', search: '10%_, "A"'),
      ).predicates.single;
      expect(punctuation, contains(r'item_name.ilike."%10\\%\\_, \"A\"%"'));
      final star = InventoryDailyOrderQuery(
        DailyOrderQuery(runDate: '2026-11-11', search: 'A*B'),
      ).predicates.single;
      expect(star, contains(r'item_name.imatch."A\\*B"'));
    },
  );

  test(
    'REST reads the date, filters, and cursor together before applying the limit',
    () async {
      final calls = <Uri>[];
      final client = SupabaseClient(
        'https://inventory.test',
        'anon-test-key',
        httpClient: MockClient((request) async {
          calls.add(request.url);
          final rows = calls.length == 1
              ? List.generate(
                  121,
                  (index) => {
                    'branch': 'Alpha',
                    'item_code': '${1000 + index}',
                    'item_name': 'Search result',
                    'branch_stock': null,
                  },
                )
              : [
                  {
                    'branch': 'Alpha',
                    'item_code': '1120',
                    'item_name': 'Last item',
                  },
                ];
          return http.Response(
            jsonEncode(rows),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final remote = InventoryRemoteDs(client);
      final query = DailyOrderQuery(
        runDate: '2026-11-11',
        search: 'Search',
        branch: 'Alpha',
        filters: {
          'store_stock': DailyOrderColumnFilter([
            (operator: DailyOrderOperator.greaterThan, value: '0'),
            (operator: DailyOrderOperator.atMost, value: '20'),
          ], matchAny: false),
        },
        sort: 'branch_stock',
        ascending: false,
      );
      final first = await remote.fetchDailyOrderBatch(query);
      expect(first.rows, hasLength(120));
      expect(first.next, (itemCode: '1119', branch: 'Alpha', sortValue: null));
      final last = await remote.fetchDailyOrderBatch(query, after: first.next);
      expect(last.rows.single.itemCode, '1120');
      expect(last.next, isNull);

      final parameters = calls.last.queryParametersAll;
      expect(calls.last.path, '/rest/v1/inventory_daily_order_rows');
      expect(parameters['run_date'], ['eq.2026-11-11']);
      expect(parameters['branch'], ['eq.Alpha']);
      expect(parameters['limit'], ['121']);
      expect(parameters['offset'], isNull);
      expect(parameters['order'], [
        'branch_stock.desc.nullslast,item_code.asc.nullslast,branch.asc.nullslast',
      ]);
      expect(parameters['or'], [
        contains('barcode.ilike."%Search%"'),
        '(and(store_stock.gt."0",store_stock.lte."20"))',
        '(and(branch_stock.is.null,item_code.gt."1119"),'
            'and(branch_stock.is.null,item_code.eq."1119",branch.gt."Alpha"))',
      ]);
    },
  );
}
