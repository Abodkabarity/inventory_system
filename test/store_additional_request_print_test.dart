import 'dart:async';
import 'dart:convert';

import 'package:daily_order/data/repositories/store_additional_request_repository.dart';
import 'package:daily_order/domain/entities/store_additional_request_status.dart';
import 'package:daily_order/presentation/store_dashboard/widgets/additional_request_dialog.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:yet_another_json_isolate/yet_another_json_isolate.dart';

// Widget tests use a fake clock; keep real JSON serialization on that clock
// while exercising the production Supabase request/response/filter pipeline.
class TestJsonIsolate implements YAJsonIsolate {
  @override
  Future<dynamic> decode(String value) async => jsonDecode(value);
  @override
  Future<String> encode(Object? value) async => jsonEncode(value);
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> item(
  String id, {
  String status = 'sent_to_store',
  String? storeStatus,
  String branch = 'MODERN',
  num? inventoryQty = 1,
}) => {
  'id': id,
  'request_group_id': 'group-1',
  'branch_name': branch,
  'item_code': id,
  'item_name': 'Product $id',
  'inventory_qty': inventoryQty,
  'request_qty': 1,
  'status': status,
  'store_status': storeStatus,
  'fulfilled_qty': status == 'done' ? 1 : null,
  'store_note': status == 'done' ? 'Original evidence' : null,
};

class RequestFixture {
  RequestFixture(this.rows) {
    client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      isolate: TestJsonIsolate(),
      httpClient: MockClient(_handle),
    );
  }
  final List<Map<String, dynamic>> rows;
  late final SupabaseClient client;
  int reads = 0, writes = 0, cap = 4000;
  bool failRead = false, failWrite = false, commitThenFail = false;
  void Function()? beforePatch;
  final requests = <http.Request>[];
  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    final q = request.url.queryParameters;
    expect(q['request_group_id'], 'eq.group-1');
    final inventory = request.url.path.endsWith('additional_order_inventory');
    if (!inventory) expect(q['branch_name'], 'eq.MODERN');
    var selected = rows
        .where(
          (r) =>
              r['request_group_id'] == 'group-1' &&
              (inventory || r['branch_name'] == 'MODERN'),
        )
        .toList();
    if (request.method == 'GET') {
      reads++;
      if (failRead) {
        return _response(request, {
          'message': 'load failed',
          'code': 'test',
        }, 500);
      }
      expect(q['order'], startsWith('id.asc'));
      final from = int.parse(q['offset'] ?? '0');
      final limit = int.parse(q['limit'] ?? '0');
      expect(limit, 4000);
      final batch = selected
          .skip(from)
          .take(limit < cap ? limit : cap)
          .toList();
      return _response(request, batch, 200, total: selected.length);
    }
    expect(request.method, 'PATCH');
    writes++;
    expect(q['status'], 'eq.sent_to_store');
    expect(q['or'], '(store_status.is.null,store_status.eq.)');
    expect(jsonDecode(request.body), {'store_status': 'processing'});
    beforePatch?.call();
    if (failWrite) {
      return _response(request, {
        'message': 'save failed',
        'code': 'test',
      }, 500);
    }
    selected = selected
        .where(
          (r) =>
              q['id']!.contains('"${r['id']}"') &&
              r['status'] == 'sent_to_store' &&
              (r['store_status'] == null || r['store_status'] == ''),
        )
        .toList();
    for (final row in selected) {
      row['store_status'] = 'processing';
    }
    if (commitThenFail) {
      return _response(request, {
        'message': 'response lost',
        'code': 'test',
      }, 500);
    }
    return _response(request, [
      for (final r in selected) {'id': r['id']},
    ], 200);
  }

  http.Response _response(
    http.Request request,
    Object body,
    int code, {
    int? total,
  }) => http.Response(
    jsonEncode(body),
    code,
    request: request,
    headers: {
      'content-type': 'application/json',
      if (total != null) 'content-range': '0-0/$total',
    },
  );
  StoreAdditionalRequestRepository repository({
    String source = 'additional_requests',
  }) => StoreAdditionalRequestRepository(
    client,
    groupId: 'group-1',
    branch: 'MODERN',
    sourceTable: source,
  );
}

Future<void> open(
  WidgetTester tester,
  RequestFixture fixture, {
  AdditionalRequestPrinter? printer,
  Size size = const Size(1280, 900),
  String source = 'additional_requests',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => AdditionalRequestDialog(
                groupId: 'group-1',
                branch: 'MODERN',
                sourceTable: source,
                client: fixture.client,
                printer: printer,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => StoreBranchIdentityRegistry.groups.value = const {});
  test('mixed request stays pending regardless of first row or sort order', () {
    final rows = [
      for (var i = 0; i < 14; i++)
        item('done-$i', status: 'done', storeStatus: 'done'),
      item('remaining'),
    ];
    for (final source in [rows, rows.reversed]) {
      final status = StoreAdditionalRequestStatus(source);
      expect(status.label, 'Pending');
      expect(status.complete, false);
      expect(status.doneCount, 14);
      expect(status.printable.single['id'], 'remaining');
    }
    expect(
      StoreAdditionalRequestStatus([
        item('a', status: 'done', storeStatus: 'processing'),
        item('b', status: 'rejected'),
      ]).label,
      'Done',
    );
    expect(
      StoreAdditionalRequestStatus([item('a', status: 'rejected')]).label,
      'Rejected',
    );
    expect(
      StoreAdditionalRequestStatus([
        item('a', status: 'inventory_review'),
      ]).complete,
      false,
    );
    expect(StoreAdditionalRequestStatus([]).label, 'No approved items');
    expect(
      StoreAdditionalRequestStatus([item('a', inventoryQty: 0)]).items,
      isEmpty,
    );
    expect(
      StoreAdditionalRequestStatus([item('a', inventoryQty: null)]).items,
      hasLength(1),
    );
  });

  test(
    'complete scoped load tolerates API caps and excludes other groups/branches',
    () async {
      final f = RequestFixture([
        for (var i = 0; i < 4501; i++) item('$i'),
        item('other-branch', branch: 'OTHER'),
        {...item('other-group'), 'request_group_id': 'other'},
      ])..cap = 1000;
      addTearDown(f.client.dispose);
      final rows = await f.repository().load();
      expect(rows.length, 4501);
      expect(f.reads, 5);
      expect(rows.any((r) => r['id'] == 'other-branch'), false);
    },
  );

  test(
    'guarded transition cannot reopen lines confirmed concurrently',
    () async {
      final pending = item('pending');
      final done = item('done', status: 'done', storeStatus: 'done');
      final f = RequestFixture([pending, done]);
      addTearDown(f.client.dispose);
      f.beforePatch = () {
        pending['status'] = 'done';
        pending['store_status'] = 'done';
      };
      expect(
        await f.repository().markPrinted([
          {...pending},
          done,
        ]),
        0,
      );
      expect(done['store_status'], 'done');
      expect(pending['store_status'], 'done');
      expect(
        f.requests.last.url.queryParameters['id'],
        isNot(contains('"done"')),
      );
    },
  );

  test(
    'Inventory request groups retain all of their branches, with exact group scope',
    () async {
      final f = RequestFixture([item('a'), item('b', branch: 'OTHER')]);
      addTearDown(f.client.dispose);
      final rows = await f
          .repository(source: 'additional_order_inventory')
          .load();
      expect(rows.length, 2);
      expect(
        await f
            .repository(source: 'additional_order_inventory')
            .markPrinted(rows),
        2,
      );
      expect(
        f.requests.last.url.queryParameters.containsKey('branch_name'),
        false,
      );
    },
  );

  testWidgets(
    'MODERN regression: only the remaining line prints and completed evidence stays unchanged',
    (tester) async {
      final f = RequestFixture([
        for (var i = 0; i < 14; i++)
          item('done-$i', status: 'done', storeStatus: 'done'),
        item('remaining'),
      ]);
      addTearDown(() => tester.runAsync(f.client.dispose));
      final before = jsonEncode(f.rows.take(14).toList());
      final batches = <Map<String, List<Map<String, dynamic>>>>[];
      await open(
        tester,
        f,
        printer: (batch) async {
          batches.add(batch);
          return true;
        },
      );
      expect(find.text('Print pending (1)'), findsOneWidget);
      expect(
        tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
        Colors.grey.shade100,
      );
      expect(find.text('Sent Qty'), findsWidgets);
      expect(find.text('Store Note'), findsWidgets);
      expect(find.byType(Divider), findsOneWidget);
      expect(find.text('Done'), findsWidgets);
      expect(
        tester.widget<Text>(find.text('Done').first).style!.color,
        Colors.green.shade700,
      );
      await tester.tap(find.text('Print pending (1)'));
      await tester.pumpAndSettle();
      expect(batches.single['MODERN']!.single['id'], 'remaining');
      expect(f.writes, 1);
      expect(f.rows.last['store_status'], 'processing');
      expect(jsonEncode(f.rows.take(14).toList()), before);
      expect(find.text('Reprint processing (1)'), findsOneWidget);
      expect(find.text('Already printed'), findsOneWidget);
      await tester.tap(find.text('Reprint processing (1)'));
      await tester.pumpAndSettle();
      expect(batches.length, 2);
      expect(f.writes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final cancel in [true, false]) {
    testWidgets(
      '${cancel ? 'cancelled' : 'failed'} printing never marks processing',
      (tester) async {
        final f = RequestFixture([item('remaining')]);
        addTearDown(() => tester.runAsync(f.client.dispose));
        await open(
          tester,
          f,
          printer: (_) async {
            if (cancel) return false;
            throw StateError('printer unavailable');
          },
        );
        await tester.tap(find.text('Print pending (1)'));
        await tester.pumpAndSettle();
        expect(f.writes, 0);
        expect(f.rows.single['store_status'], isNull);
        expect(
          find.textContaining(
            cancel ? 'Printing cancelled' : 'Could not print',
          ),
          findsOneWidget,
        );
        if (!cancel) {
          await tester.tap(find.text('Refresh'));
          await tester.pumpAndSettle();
        }
        expect(
          tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
          isNotNull,
        );
      },
    );
  }

  testWidgets(
    'double clicks share one print and no writes happen before the print response',
    (tester) async {
      final f = RequestFixture([item('a')]);
      addTearDown(() => tester.runAsync(f.client.dispose));
      final result = Completer<bool>();
      var prints = 0;
      await open(
        tester,
        f,
        printer: (_) {
          prints++;
          return result.future;
        },
      );
      await tester.tap(find.text('Print pending (1)'));
      await tester.pump();
      expect(prints, 1);
      expect(f.writes, 0);
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(find.byType(IconButton).first).onPressed,
        isNull,
      );
      result.complete(true);
      await tester.pumpAndSettle();
      expect(f.writes, 1);
    },
  );

  testWidgets(
    'fresh read removes a line completed after opening; no PDF or write',
    (tester) async {
      final f = RequestFixture([item('a')]);
      addTearDown(() => tester.runAsync(f.client.dispose));
      var prints = 0;
      await open(
        tester,
        f,
        printer: (_) async {
          prints++;
          return true;
        },
      );
      f.rows.single['status'] = 'done';
      f.rows.single['store_status'] = 'done';
      await tester.tap(find.text('Print pending (1)'));
      await tester.pumpAndSettle();
      expect(prints, 0);
      expect(f.writes, 0);
      expect(find.textContaining('No pending items'), findsOneWidget);
      expect(find.text('Print pending (1)'), findsNothing);
    },
  );

  testWidgets(
    'a response lost after saving is reconciled without automatic write replay',
    (tester) async {
      final f = RequestFixture([item('a')])..commitThenFail = true;
      addTearDown(() => tester.runAsync(f.client.dispose));
      await open(tester, f, printer: (_) async => true);
      await tester.tap(find.text('Print pending (1)'));
      await tester.pumpAndSettle();
      expect(f.writes, 1);
      expect(f.rows.single['store_status'], 'processing');
      expect(
        find.textContaining('status could not be verified'),
        findsOneWidget,
      );
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Reprint processing (1)'), findsOneWidget);
      expect(f.writes, 1);
    },
  );

  testWidgets(
    'read failures show refresh; no false Done and no enabled Print',
    (tester) async {
      final f = RequestFixture([item('a')])..failRead = true;
      addTearDown(() => tester.runAsync(f.client.dispose));
      await open(tester, f, printer: (_) async => true);
      expect(find.textContaining('Could not load'), findsOneWidget);
      expect(find.text('Print pending (1)'), findsNothing);
      f.failRead = false;
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Print pending (1)'), findsOneWidget);
    },
  );

  testWidgets('mixed processing and pending prints the unprinted lines only', (
    tester,
  ) async {
    final f = RequestFixture([
      item('already', storeStatus: 'processing'),
      item('new'),
    ]);
    addTearDown(() => tester.runAsync(f.client.dispose));
    await open(
      tester,
      f,
      printer: (batch) async {
        expect(batch['MODERN']!.map((r) => r['id']), ['new']);
        return true;
      },
    );
    await tester.tap(find.text('Print pending (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Reprint processing (2)'), findsOneWidget);
    expect(f.writes, 1);
  });

  testWidgets('phone layout wraps group 71 labels and preserves numeric Qty', (
    tester,
  ) async {
    StoreBranchIdentityRegistry.groups.value = {'MODERN': '71'};
    final f = RequestFixture([
      {
        ...item('a'),
        'item_name': 'Long product name that must wrap on a small screen',
        'inventory_qty': 2.5,
      },
    ]);
    addTearDown(() => tester.runAsync(f.client.dispose));
    await open(
      tester,
      f,
      size: const Size(390, 750),
      printer: (_) async => true,
    );
    expect(find.text('71 MODERN Additional Order'), findsOneWidget);
    expect(find.text('2.5'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
