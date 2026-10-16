import 'dart:convert';

import 'package:daily_order/core/utils/mismatch_report_date.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/data/datasources/remote/inventory_remote_ds.dart';
import 'package:daily_order/data/repositories/inventory_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  Map<String, dynamic> record({
    String branch = 'Al Ain',
    String code = '001',
    String? created = '2026-09-26T16:29:12.592+04:00',
  }) => {
    'id': 1,
    'branch_name': branch,
    'item_code': code,
    'item_name': 'Sample item',
    'system_stock': 4,
    'actual_stock': 6,
    'diff': 2,
    'created_at': created,
    'update_date': '2026-09-26',
  };
  Map<String, dynamic> edit(String date, {String action = 'update'}) => {
    'branch_name': 'Al Ain',
    'item_code': '001',
    'action': action,
    'changed_at': date,
  };
  String dateOf(Map<String, dynamic> row) =>
      mismatchDateLabel(mismatchTimestamp(row['report_date']));

  test('shows creation until edited, then the most recent logged edit', () {
    final row = record();
    expect(dateOf(mismatchReportRows([row], []).single), '26/09/2026');
    final changed = mismatchReportRows(
      [row],
      [edit('2026-10-15T20:56:21.603573'), edit('2026-10-02T08:00:00')],
    );
    expect(dateOf(changed.single), '15/10/2026');
    expect(changed.single['has_history'], isTrue);
    expect(row.containsKey('report_date'), isFalse);
  });

  test('re-added items ignore edits and deletes from the previous record', () {
    final rows = mismatchReportRows(
      [record(created: '2026-10-16T00:15:00+04:00')],
      [
        edit('2026-10-15T23:30:00'),
        edit('2026-10-15T23:45:00', action: 'delete'),
      ],
    );
    expect(dateOf(rows.single), '16/10/2026');
    expect(rows.single['has_history'], isTrue);
  });

  test(
    'Dubai dates agree for offset timestamps and offset-free log values',
    () {
      for (final date in [
        '2026-10-15T20:10:00Z',
        '2026-10-16T00:10:00+04:00',
        '2026-10-16T00:10:00',
      ]) {
        expect(mismatchDateLabel(mismatchTimestamp(date)), '16/10/2026');
        expect(mismatchTimestamp(date), DateTime.utc(2026, 10, 15, 20, 10));
      }
    },
  );

  test(
    'legacy missing creation dates use stored date without inventing today',
    () {
      final row = record(created: null);
      expect(dateOf(mismatchReportRows([row], []).single), '26/09/2026');
      final missing = {...row, 'update_date': null};
      expect(dateOf(mismatchReportRows([missing], []).single), '—');
      expect(
        dateOf(mismatchReportRows([missing], [edit('2026-10-15')]).single),
        '15/10/2026',
      );
    },
  );

  test(
    'branch and item identities cannot collide or receive display prefixes',
    () {
      StoreBranchIdentityRegistry.groups.value = {
        'AL AIN': '71',
        'CITY': 'APG',
      };
      addTearDown(() => StoreBranchIdentityRegistry.groups.value = const {});
      final rows = mismatchReportRows(
        [
          record(),
          record(branch: 'City'),
          record(branch: 'A_B', code: 'C'),
          record(branch: 'A', code: 'B_C'),
        ],
        [
          edit('2026-10-15'),
          {...edit('2026-10-16'), 'branch_name': 'A_B', 'item_code': 'C'},
        ],
      );
      expect(rows.map(dateOf), [
        '15/10/2026',
        '26/09/2026',
        '16/10/2026',
        '26/09/2026',
      ]);
      expect(rows.first['branch_name'], 'Al Ain');
      expect(
        StoreBranchIdentityRegistry.exportValue(
          'branch_name',
          rows[0]['branch_name'],
        ),
        '71 Al Ain',
      );
      expect(
        StoreBranchIdentityRegistry.exportValue(
          'branch_name',
          rows[1]['branch_name'],
        ),
        'City',
      );
    },
  );

  test(
    'UI and export read dates beyond the first API batch without writing',
    () async {
      final current = [
        for (var i = 0; i < 501; i++) {...record(code: '$i'), 'id': i},
      ];
      final activity = [
        for (var i = 0; i < 501; i++)
          {...edit('2026-10-15T20:56:21'), 'id': '$i', 'item_code': '$i'},
      ];
      final requests = <Uri>[];
      final client = SupabaseClient(
        'https://mismatch-test.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          requests.add(request.url);
          final records = request.url.path.endsWith('/stk_mismatch')
              ? current
              : activity;
          final from = int.parse(request.url.queryParameters['offset']!);
          final count = int.parse(request.url.queryParameters['limit']!);
          final end = (from + count).clamp(0, records.length);
          return http.Response(
            jsonEncode(records.sublist(from, end)),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final repo = InventoryRepositoryImpl(InventoryRemoteDs(client));
      final items = await repo.fetchMismatch();
      expect(items.length, 501);
      expect(mismatchDateLabel(items.last.reportDate), '15/10/2026');
      expect(items.last.hasHistory, isTrue);
      final exported = await repo.fetchMismatchExport();
      expect(exported.length, 501);
      expect(dateOf(exported.last), mismatchDateLabel(items.last.reportDate));
      expect(requests.length, 8);
    },
  );
}
