import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:daily_order/core/utils/max_adjustment_import.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:flutter_test/flutter_test.dart';

List<dynamic> fixtureRow(
  String code, {
  String branch = 'Al Ain',
  String action = 'ADD',
  String date = '28-09-2026',
}) => [action, branch, code, 'Item $code', '3', '5', 'Reason', date, ''];

void main() {
  setUp(
    () => StoreBranchIdentityRegistry.groups.value = const {
      'AL AIN': '71',
      'CITY': 'APG',
    },
  );
  tearDown(() => StoreBranchIdentityRegistry.groups.value = const {});

  test(
    'incremental CSV preserves BOM, identifiers and quoted UTF-8 across byte boundaries',
    () async {
      final row = fixtureRow('00123');
      row[3] = 'دواء, with "quotes"\nand a new line';
      final csv =
          '\uFEFF${const ListToCsvConverter(eol: '\r\n').convert([maxAdjustmentImportHeaders, row])}';
      final rows = await parseMaxAdjustmentCsv(
        Uint8List.fromList(utf8.encode(csv)),
        chunkSize: 7,
      );
      expect(rows.first, maxAdjustmentImportHeaders);
      expect(rows[1][2], '00123');
      expect(rows[1][3], row[3]);
    },
  );

  test(
    'accepts LF and legacy Latin-1 with monotonic parsing progress',
    () async {
      final row = fixtureRow('00123');
      row[3] = 'Café';
      final csv = const ListToCsvConverter(
        eol: '\n',
      ).convert([maxAdjustmentImportHeaders, row]);
      final progress = <double>[];
      final rows = await parseMaxAdjustmentCsv(
        Uint8List.fromList(latin1.encode(csv)),
        chunkSize: 16,
        onProgress: progress.add,
      );
      expect(rows.length, 2);
      expect(rows[1][3], 'Café');
      expect(progress, orderedEquals([...progress]..sort()));
    },
  );

  test('CSV parsing yields to timers on large files', () async {
    final csv = const ListToCsvConverter(eol: '\n').convert([
      maxAdjustmentImportHeaders,
      for (var i = 0; i < 5000; i++) fixtureRow('$i'),
    ]);
    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => ticks++,
    );
    try {
      final rows = await parseMaxAdjustmentCsv(
        Uint8List.fromList(utf8.encode(csv)),
      );
      expect(rows.length, 5001);
      expect(ticks, greaterThan(1));
    } finally {
      timer.cancel();
    }
  });

  test(
    'plans 20000 writes without scanning or changing the displayed list',
    () async {
      final existing = <Map<String, dynamic>>[
        for (var i = 0; i < 10000; i++)
          {'branch_name': 'Al Ain', 'item_code': '$i', 'max_adjustment_30d': 1},
      ];
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 1),
        (_) => ticks++,
      );
      try {
        final plan = await prepareMaxAdjustmentImport(
          rows: [
            maxAdjustmentImportHeaders,
            for (var i = 0; i < 20000; i++) fixtureRow('$i'),
          ],
          activeBranches: ['Al Ain'],
          existing: existing,
          overwrite: true,
        );
        expect(plan.upserts.length, 20000);
        expect(plan.issues, isEmpty);
        expect(existing.length, 10000);
        expect(existing.first['max_adjustment_30d'], 1);
        expect(ticks, greaterThan(1));
      } finally {
        timer.cancel();
      }
    },
  );

  test(
    'duplicate decision preserves raw identities, decrease rules and custom dates',
    () async {
      final a = fixtureRow('001', branch: '71 Al Ain');
      a[5] = '3';
      a[8] = '31/12/2026';
      final existing = [
        {'branch_name': 'Al Ain', 'item_code': '001', 'max_adjustment_30d': 9},
      ];
      final rows = [
        maxAdjustmentImportHeaders,
        a,
        fixtureRow('002', branch: 'City'),
      ];
      final review = await prepareMaxAdjustmentImport(
        rows: rows,
        activeBranches: ['Al Ain', 'City'],
        existing: existing,
        overwrite: false,
      );
      expect(review.conflicts.length, 1);
      expect(review.upserts.single['branch_name'], 'City');
      expect(review.conflicts.single['branch_name'], 'Al Ain');
      expect(review.conflicts.single['new_adjustment_type'], 'DECREASE');
      expect(review.conflicts.single['new_end_date'], '2026-12-31');
      final overwrite = await prepareMaxAdjustmentImport(
        rows: rows,
        activeBranches: ['Al Ain', 'City'],
        existing: existing,
        overwrite: true,
      );
      expect(overwrite.upserts.length, 2);
      expect(overwrite.upserts.first['branch_name'], 'Al Ain');
      expect(overwrite.upserts.first['update_date'], '2026-09-28');
    },
  );

  test(
    'errors identify bad rows and repeated file identities before any write',
    () async {
      final invalidNumber = fixtureRow('bad-number')..[5] = 'oops';
      final plan = await prepareMaxAdjustmentImport(
        rows: [
          maxAdjustmentImportHeaders,
          fixtureRow('one'),
          fixtureRow('one'),
          fixtureRow('two', branch: 'unknown'),
          invalidNumber,
          fixtureRow('bad-date', date: '30/02/2026'),
        ],
        activeBranches: ['Al Ain'],
        existing: [],
        overwrite: false,
      );
      expect(plan.issues.map((e) => e['row']), [3, 4, 5, 6]);
      var writes = 0;
      await expectLater(
        writeMaxAdjustmentImport(
          plan: plan,
          upsert: (_) async {
            writes++;
          },
          delete: (_) async {
            writes++;
          },
        ),
        throwsStateError,
      );
      expect(writes, 0);
    },
  );

  test('delete and conflict-only files also yield to the UI', () async {
    for (final action in ['DELETE', 'ADD']) {
      var ticks = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 1),
        (_) => ticks++,
      );
      try {
        final plan = await prepareMaxAdjustmentImport(
          rows: [
            maxAdjustmentImportHeaders,
            for (var i = 0; i < 1500; i++) fixtureRow('$i', action: action),
          ],
          activeBranches: ['Al Ain'],
          existing: [
            for (var i = 0; i < 1500; i++)
              {'branch_name': 'Al Ain', 'item_code': '$i'},
          ],
          overwrite: false,
        );
        expect(
          action == 'DELETE' ? plan.deletes.length : plan.conflicts.length,
          1500,
        );
        expect(ticks, greaterThan(1));
      } finally {
        timer.cancel();
      }
    }
  });

  test('sequential bounded writes report confirmed progress', () async {
    final plan = MaxAdjustmentImportPlan();
    plan.deletes.addAll([
      for (var i = 0; i < 600; i++) {'id': i},
    ]);
    plan.upserts.addAll([
      for (var i = 0; i < 700; i++) {'id': i},
    ]);
    final calls = <String>[];
    final progress = <int>[];
    var pending = 0;
    Future<void> write(String name, List<Map<String, dynamic>> batch) async {
      expect(pending++, 0);
      expect(batch.length, lessThanOrEqualTo(250));
      calls.add('$name:${batch.length}');
      await Future<void>.delayed(Duration.zero);
      pending--;
    }

    final count = await writeMaxAdjustmentImport(
      plan: plan,
      upsert: (b) => write('upsert', b),
      delete: (b) => write('delete', b),
      onProgress: (n, total) {
        progress.add(n);
        expect(total, 1300);
      },
    );
    expect(count, 1300);
    expect(calls, [
      'delete:250',
      'delete:250',
      'delete:100',
      'upsert:250',
      'upsert:250',
      'upsert:200',
    ]);
    expect(progress, [250, 500, 600, 850, 1100, 1300]);
  });

  test('failed/timed-out batch stops later writes and never retries', () async {
    for (final timedOut in [false, true]) {
      final plan = MaxAdjustmentImportPlan()
        ..upserts.addAll([
          for (var i = 0; i < 700; i++) {'id': i},
        ]);
      var calls = 0;
      final pending = Completer<void>();
      await expectLater(
        writeMaxAdjustmentImport(
          plan: plan,
          timeout: const Duration(milliseconds: 5),
          delete: (_) async {},
          upsert: (_) async {
            calls++;
            if (calls == 2) {
              if (timedOut) {
                await pending.future;
              } else {
                throw StateError('failure');
              }
            }
          },
        ),
        throwsA(
          isA<MaxAdjustmentImportWriteFailure>().having(
            (e) => e.confirmedRows,
            'confirmed rows',
            250,
          ),
        ),
      );
      expect(calls, 2);
      if (timedOut) pending.complete();
    }
  });

  test(
    'issue/duplicate CSV exports decorate 71 once without changing import keys',
    () async {
      final rows = [
        {
          'row': 2,
          'branch_name': 'Al Ain',
          'item_code': '001',
          'error': 'Invalid, value',
        },
        {
          'row': 3,
          'branch_name': 'City',
          'item_code': '002',
          'error': '"Quoted" error',
        },
      ];
      final csv = await maxAdjustmentImportReportCsv(rows);
      expect(csv, contains('71 Al Ain'));
      expect(csv, isNot(contains('71 City')));
      expect(csv, contains('"Invalid, value"'));
      expect(csv, contains('""Quoted""'));
      expect(rows.first['branch_name'], 'Al Ain');
    },
  );
}
