import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/data/repositories/mismatch_review_repository.dart';
import 'package:daily_order/domain/entities/mismatch_review.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/mismatch_review_workspace.dart';
import 'package:daily_order/presentation/widgets/app_date_range_picker_dialog.dart';

MismatchReview sample(
  int id, {
  String branch = 'Al Noud - Ain',
  String status = 'priority_followup',
  String name = 'KIN ORTHODONTIC WAX',
  bool stale = false,
}) => MismatchReview({
  'id': id,
  'branch_name': branch,
  'item_code': '16-02-05028-$id',
  'item_name': name,
  'system_stock': 1,
  'actual_stock': 0,
  'diff': -1,
  'created_at': '2026-09-26T12:50:00Z',
  'review_stale': stale,
  'analysis': {
    'status': status,
    'issues': status == 'data_review' ? ['incomplete_coverage'] : [],
    'event_at': '2026-09-26T16:50:00',
    'event_action': 'add',
    'baseline_qty': 1,
    'reconstructed_before': 1,
    'last_zero': '2026-08-04',
    'last_receipt': '2026-09-07',
    'receipt_qty': 1,
    'receipt_types': ['StockTransferTo'],
    'out_since_receipt': 0,
    'old_shortage': 0,
    'new_shortage': 1,
    'added_shortage': 1,
    'adjustment_count': 0,
    'coverage_through': '2026-10-21',
  },
});

class FakeReviews extends MismatchReviewRepository {
  List<Map<String, dynamic>> extraMovements = [];
  List<Map<String, dynamic>>? movementOverride;
  List<MismatchReview> rows = [
    sample(1),
    sample(
      2,
      branch: 'Asharej Branch',
      name: 'NOREVA EXFOLIAC GENTLE FOAMING GEL',
      status: 'recent_receipt_followup',
    ),
    sample(3, name: 'BEURER EAR THERMOMETER FT 58', status: 'data_review'),
  ];
  void Function(int?)? changed;
  void Function(bool)? connection;
  bool closed = false, fail = false;
  int loads = 0, detailCalls = 0;
  String sourceVersion = 'source';
  Completer<void>? detailGate;
  List<int> refreshed = [];
  Completer<void>? refreshGate;
  @override
  Future<MismatchReviewSnapshot> load() async {
    loads++;
    if (fail) throw StateError('offline');
    return MismatchReviewSnapshot(List.of(rows), [
      {
        'company': 'APG',
        'from_date': '2026-01-01',
        'to_date': '2026-10-21',
        'complete': true,
        'committed_rows': 1,
        'expected_rows': 1,
      },
    ], sourceVersion);
  }

  @override
  Future<Map<String, dynamic>?> detail(int id) async {
    detailCalls++;
    if (detailGate != null) await detailGate!.future;
    final r = rows.where((r) => r.id == id).firstOrNull;
    if (r == null) return null;
    return {
      'analysis': r.analysis,
      'evidence': {
        'baseline': [
          {'qty': '1'},
        ],
        'movements':
            movementOverride ??
            [
              ...extraMovements,
              {
                'trans_date': '2026-08-04',
                'qty': '-1',
                'mode': 'Out',
                'trans_type': 'POSDVN',
                'trans_no': '00017',
              },
              {
                'trans_date': '2026-09-07',
                'qty': '1',
                'mode': 'IN',
                'trans_type': 'StockTransferTo',
                'trans_no': '1073464',
              },
            ],
        'events': [
          {
            'action': 'add',
            'changed_at': '2026-09-26T16:50:00',
            'new_system_stock': '1',
            'new_actual_stock': '0',
            'new_diff': '-1',
          },
        ],
      },
    };
  }

  @override
  Future<void> refreshReviews(List<int> ids) async {
    refreshed.addAll(ids);
    if (refreshGate != null) await refreshGate!.future;
    rows = rows
        .map((r) => MismatchReview({...r.raw, 'review_stale': false}))
        .toList();
  }

  @override
  void watch(void Function(int?) f, void Function(bool) c) {
    changed = f;
    connection = c;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

class DeltaReviews extends FakeReviews {
  int version = 0;
  final requested = <List<int>>[];
  @override
  Future<MismatchReviewSnapshot> load() async {
    final result = await super.load();
    return MismatchReviewSnapshot(
      result.rows,
      result.coverage,
      result.sourceVersion,
      '$version',
    );
  }

  @override
  Future<MismatchReviewChanges?> changes(List<int> ids) async {
    requested.add(List.of(ids));
    if (this.fail) throw StateError('offline');
    return MismatchReviewChanges(
      rows.where((r) => ids.contains(r.id)).toList(),
      'source',
      '$version',
    );
  }
}

class CountingReview extends MismatchReview {
  CountingReview(super.raw);
  static int searches = 0;
  @override
  bool matches(String search) {
    searches++;
    return super.matches(search);
  }
}

void main() {
  tearDown(() => StoreBranchIdentityRegistry.groups.value = {});
  testWidgets(
    'toolbar searches decorated branches and filters inclusive UAE report dates',
    (tester) async {
      tester.view.physicalSize = const Size(1700, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      StoreBranchIdentityRegistry.groups.value = {'ASHAREJ BRANCH': '71'};
      final repo = FakeReviews();
      final timestamps = [
        '2026-09-25T20:00:00Z',
        '2026-09-26T19:59:59Z',
        '2026-09-25T19:59:59Z',
        '2026-09-26T20:00:00Z',
      ];
      repo.rows = [
        for (var i = 0; i < timestamps.length; i++)
          MismatchReview({
            ...sample(
              i + 1,
              branch: i == 0 ? 'Asharej Branch' : 'Al Noud - Ain',
            ).raw,
            'analysis': {...sample(i + 1).analysis, 'event_at': timestamps[i]},
          }),
      ];
      final controller = MismatchReviewController(repo);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MismatchReviewWorkspace(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('All reviews'), findsNothing);
      expect(find.byTooltip('Refresh report'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tracker-branch-dropdown')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search branches...'),
        '71 Asharej',
      );
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.text('71 Asharej Branch').last));
      await tester.pumpAndSettle();
      expect(find.text('1 records'), findsOneWidget);
      expect(find.text('16-02-05028-1'), findsOneWidget);
      await tester.tap(find.byTooltip('All branches'));
      await tester.pumpAndSettle();
      expect(find.text('4 records'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('mismatch-report-date-range')),
      );
      await tester.pumpAndSettle();
      final picker = find.byType(AppDateRangePickerDialog);
      expect(picker, findsOneWidget);
      Navigator.of(tester.element(picker)).pop(
        DateTimeRange(start: DateTime(2026, 9, 26), end: DateTime(2026, 9, 26)),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 records'), findsOneWidget);
      expect(find.text('16-02-05028-1'), findsOneWidget);
      expect(find.text('16-02-05028-2'), findsOneWidget);
      expect(find.text('16-02-05028-3'), findsNothing);
      expect(find.text('16-02-05028-4'), findsNothing);
      await tester.tap(find.byTooltip('Clear report dates'));
      await tester.pumpAndSettle();
      expect(find.text('4 records'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  test(
    'pending evidence is never presented as clear and exports decorate only branch fields',
    () {
      StoreBranchIdentityRegistry.groups.value = {'ASHAREJ BRANCH': '71'};
      final r = sample(2, branch: 'Asharej Branch', stale: true);
      expect(r.status, 'pending');
      expect(r.needsFollowup, false);
      expect(r.exportRow()['branch_name'], '71 Asharej Branch');
      expect(r.branch, 'Asharej Branch');
      expect(r.matches('71 Asharej'), true);
    },
  );

  testWidgets(
    'workspace handles detail, late 71 metadata, search and live insert',
    (tester) async {
      tester.view.physicalSize = const Size(1700, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeReviews();
      final controller = MismatchReviewController(repo);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MismatchReviewWorkspace(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mismatch Report'), findsOneWidget);
      expect(find.textContaining('Asharej Branch'), findsWidgets);
      StoreBranchIdentityRegistry.groups.value = {
        'ASHAREJ BRANCH': '71',
        'AL NOUD - AIN': 'APG',
      };
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '71 Asharej');
      await tester.pumpAndSettle();
      expect(find.textContaining('16-02-05028-2'), findsOneWidget);
      expect(find.text('KIN ORTHODONTIC WAX'), findsNothing);
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();
      await tester.tap(find.text('KIN ORTHODONTIC WAX'));
      await tester.pumpAndSettle();
      expect(find.text('MISMATCH REVIEW'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(
        tester.getSize(find.byType(MismatchReviewDetail)).width,
        greaterThan(1200),
      );
      expect(find.text('What happened to this item?'), findsOneWidget);
      await tester.tap(find.text('Movements'));
      await tester.pumpAndSettle();
      expect(find.text('Adj No 00017'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      repo.rows = [
        ...repo.rows,
        sample(4, name: 'A NEW LIVE COUNT', status: 'data_review'),
      ];
      repo.connection!(true);
      repo.changed!(4);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('A NEW LIVE COUNT'), findsOneWidget);
      expect(find.text('Live mismatch updates'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('disconnect retains data and exposes a non-live state', (
    tester,
  ) async {
    final repo = FakeReviews();
    final c = MismatchReviewController(repo);
    addTearDown(c.dispose);
    c.start();
    await tester.pump();
    repo.connection!(true);
    await tester.pump();
    expect(c.live, true);
    repo.connection!(false);
    repo.fail = true;
    await c.refresh();
    expect(c.rows.length, 3);
    expect(c.live, false);
    expect(c.error, isNotNull);
    c.dispose();
  });

  testWidgets(
    '11,000 rows are not scanned on dialog open/close and reopening reuses detail',
    (tester) async {
      tester.view.physicalSize = const Size(1700, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeReviews()
        ..rows = List.generate(
          11000,
          (i) => CountingReview(
            sample(
              i + 1,
              name: i == 0 ? 'PERFORMANCE PRODUCT' : 'Product $i',
              status: i == 0 ? 'priority_followup' : 'historical_review',
            ).raw,
          ),
        );
      final controller = MismatchReviewController(repo);
      addTearDown(controller.dispose);
      CountingReview.searches = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MismatchReviewWorkspace(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      final searches = CountingReview.searches;
      expect(searches, greaterThanOrEqualTo(11000));
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('PERFORMANCE PRODUCT'));
        await tester.pumpAndSettle();
        expect(find.text('What happened to this item?'), findsOneWidget);
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
      }
      expect(CountingReview.searches, searches);
      expect(repo.detailCalls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'detail cache deduplicates requests and rejects changed/source-stale in-flight results',
    (tester) async {
      final repo = FakeReviews()..detailGate = Completer<void>();
      final controller = MismatchReviewController(repo);
      addTearDown(controller.dispose);
      controller.start();
      await tester.pump();
      final row = controller.rows.first;
      final first = controller.detail(row), second = controller.detail(row);
      expect(repo.detailCalls, 1);
      repo.changed!(row.id);
      repo.detailGate!.complete();
      await Future.wait([first, second]);
      expect(controller.cachedDetail(row), isNull);
      await controller.detail(row);
      expect(repo.detailCalls, 2);
      await controller.detail(row);
      expect(repo.detailCalls, 2);
      repo.sourceVersion = 'new-source';
      await controller.refresh();
      expect(controller.cachedDetail(row), isNull);
      repo.rows = List.generate(14, (i) => sample(i + 1));
      for (final r in repo.rows) {
        await controller.detail(r);
      }
      expect(controller.cachedDetail(repo.rows.first), isNull);
      expect(controller.cachedDetail(repo.rows.last), isNotNull);
      controller.dispose();
    },
  );

  testWidgets(
    'two-month story explains three received, one sold, one transferred and one missing',
    (tester) async {
      tester.view.physicalSize = const Size(1700, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final original = sample(1, status: 'historical_review');
      final repo = FakeReviews()
        ..rows = [
          MismatchReview({
            ...original.raw,
            'analysis': {
              ...original.analysis,
              'last_receipt': '2026-08-07',
              'receipt_qty': 3,
              'event_at': '2026-10-07T12:00:00',
            },
          }),
        ]
        ..movementOverride = [
          {'trans_date': '2026-08-04', 'qty': '-1', 'trans_type': 'POSDVN'},
          {
            'trans_date': '2026-08-07',
            'qty': '3',
            'trans_type': 'StockTransferTo',
          },
          {'trans_date': '2026-08-20', 'qty': '-1', 'trans_type': 'POS'},
          {
            'trans_date': '2026-09-01',
            'qty': '-1',
            'trans_type': 'StockTransferFrom',
          },
        ];
      final controller = MismatchReviewController(repo);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MismatchReviewWorkspace(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('KIN ORTHODONTIC WAX'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Received Qty 3'), findsOneWidget);
      expect(find.textContaining('2 months (61 days)'), findsWidgets);
      expect(
        find.textContaining('Sold Qty 1; Transferred Qty 1'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Expected system stock: Qty 1'),
        findsOneWidget,
      );
      expect(
        find.text('Missing: Qty 1. Check with the branch.'),
        findsOneWidget,
      );
      // Same cached row values, but a new source version must refresh the open dialog.
      repo.movementOverride!.add({
        'trans_date': '2026-10-07',
        'qty': '-1',
        'trans_type': 'POS',
      });
      repo.sourceVersion = 'updated-movements';
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(repo.detailCalls, 2);
      expect(
        find.text(
          'Check the stock history before following up with the branch.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('recorded on the report day'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('old adjustments are prominent and open their complete history', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1700, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeReviews()
      ..extraMovements = [
        {
          'trans_date': '2026-02-04',
          'qty': '-2',
          'mode': 'OUT',
          'trans_type': 'INVAdjustment',
          'trans_no': '000091',
        },
        {
          'trans_date': '2026-09-12',
          'qty': '1',
          'mode': 'IN',
          'trans_type': 'INVAdjustment',
          'trans_no': '000092',
        },
      ];
    final controller = MismatchReviewController(repo);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MismatchReviewWorkspace(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('KIN ORTHODONTIC WAX'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stock corrections (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Adj No 000091'), findsOneWidget);
    expect(find.text('Adj No 000092'), findsOneWidget);
    expect(find.textContaining('Before latest incoming'), findsWidgets);
    expect(find.textContaining('After latest incoming'), findsWidgets);
    StoreBranchIdentityRegistry.groups.value = {'AL NOUD - AIN': '71'};
    await tester.pumpAndSettle();
    expect(find.text('71 Al Noud - Ain'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'live notification opens details within a dashboard sidebar layout',
    (tester) async {
      tester.view.physicalSize = const Size(1700, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeReviews();
      final controller = MismatchReviewController(repo);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 1000,
                child: MismatchReviewWorkspace(controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      repo.changed!(1);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Mismatch updated ·'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('MISMATCH REVIEW'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('stale source is refreshed before returning a risk verdict', (
    tester,
  ) async {
    final repo = FakeReviews()
      ..rows = [sample(1, stale: true)]
      ..refreshGate = Completer<void>();
    final c = MismatchReviewController(repo);
    addTearDown(c.dispose);
    c.start();
    await tester.pump();
    expect(c.rows.single.status, 'pending');
    expect(c.refreshingEvidence, true);
    repo.refreshGate!.complete();
    await tester.pump();
    expect(repo.refreshed, [1]);
    expect(c.rows.single.status, 'priority_followup');
    c.dispose();
  });

  testWidgets(
    'live deltas patch only affected IDs and a later poll reconciles missed events',
    (tester) async {
      final repo = DeltaReviews();
      final controller = MismatchReviewController(repo);
      addTearDown(controller.dispose);
      controller.start();
      await tester.pump();
      expect(repo.loads, 1);
      repo.rows = [...repo.rows, sample(4)];
      repo.version++;
      repo.changed!(4);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(controller.rows.length, 4);
      expect(repo.loads, 1);
      expect(repo.requested.last, [4]);
      repo.rows = repo.rows.where((r) => r.id != 4).toList();
      repo.version++;
      repo.changed!(4);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(controller.rows.length, 3);
      expect(repo.loads, 1);
      // A fifth item arrives while the realtime connection is unavailable.
      repo.rows = [...repo.rows, sample(5)];
      repo.version++;
      await tester.pump(const Duration(seconds: 45));
      await tester.pump();
      expect(controller.rows.map((r) => r.id), contains(5));
      expect(repo.loads, 2);
      controller.dispose();
    },
  );

  for (final size in [
    const Size(1600, 800),
    const Size(1000, 1000),
    const Size(640, 1000),
  ]) {
    testWidgets('responsive workspace and detail at ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = MismatchReviewController(FakeReviews());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MismatchReviewWorkspace(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('KIN ORTHODONTIC WAX'));
      await tester.pumpAndSettle();
      expect(find.text('MISMATCH REVIEW'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets('render desktop review workspace for visual inspection', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final font = File('C:/Windows/Fonts/segoeui.ttf');
      if (await font.exists()) {
        await (FontLoader('ReviewPreview')..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes())),
            ))
            .load();
      }
      final icons = File(
        'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      );
      if (await icons.exists()) {
        await (FontLoader('MaterialIcons')..addFont(
              Future.value(ByteData.sublistView(await icons.readAsBytes())),
            ))
            .load();
      }
    });
    tester.view.physicalSize = const Size(1700, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StoreBranchIdentityRegistry.groups.value = {
      'ASHAREJ BRANCH': '71',
      'AL NOUD - AIN': 'APG',
    };
    final controller = MismatchReviewController(FakeReviews());
    addTearDown(controller.dispose);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: ThemeData(
            fontFamily: 'ReviewPreview',
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF087F8C),
            ),
          ),
          home: Scaffold(body: MismatchReviewWorkspace(controller: controller)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('KIN ORTHODONTIC WAX'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('outputs/mismatch-live-workspace-preview.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
