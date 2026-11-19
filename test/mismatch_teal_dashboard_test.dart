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

import 'mismatch_review_workspace_test.dart' as fixtures;

MismatchReview _row(
  int id, {
  String? name,
  String status = 'priority_followup',
}) => MismatchReview({
  ...fixtures.sample(id, name: name ?? 'ITEM $id', status: status).raw,
  'system_stock': 42,
  'actual_stock': 37,
  'diff': -5,
  'analysis': {
    ...fixtures.sample(id, status: status).analysis,
    'event_at': DateTime(
      2026,
      11,
      18,
      22,
    ).subtract(Duration(minutes: id)).toIso8601String(),
  },
});

void main() {
  testWidgets(
    'metric hover lifts only its card, returns smoothly and remains clickable',
    (tester) async {
      tester.view.physicalSize = const Size(1721, 914);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = MismatchReviewController(fixtures.FakeReviews());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MismatchReviewWorkspace(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      final title = find.text('Active mismatch entries');
      final original = tester.getTopLeft(title);
      final neighbor = tester.getTopLeft(find.text('Needs follow-up'));
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(
        tester.getCenter(find.byKey(const ValueKey('mismatch-metric-all'))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      expect(tester.getTopLeft(title).dy, lessThan(original.dy));
      expect(tester.getTopLeft(find.text('Needs follow-up')), neighbor);
      await tester.pumpAndSettle();
      final scale = tester.widget<Transform>(
        find.byKey(const ValueKey('mismatch-metric-all-scale')),
      );
      final icon = tester.widget<Transform>(
        find.byKey(const ValueKey('mismatch-metric-all-icon')),
      );
      expect(scale.transform.entry(0, 0), greaterThan(1));
      expect(icon.transform.entry(1, 0).abs(), greaterThan(.05));
      expect(find.text('3 records'), findsOneWidget);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(title).dy, closeTo(original.dy, .001));
      await mouse.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey('mismatch-metric-attention')),
        ),
      );
      await tester.pumpAndSettle();
      await mouse.down(
        tester.getCenter(
          find.byKey(const ValueKey('mismatch-metric-attention')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.text('2 records'), findsOneWidget);
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('metric hover respects reduced motion', (tester) async {
    tester.view.physicalSize = const Size(1721, 914);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = MismatchReviewController(fixtures.FakeReviews());
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(body: MismatchReviewWorkspace(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    final title = find.text('Active mismatch entries');
    final original = tester.getTopLeft(title);
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('mismatch-metric-all'))),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(title), original);
    expect(
      tester
          .widget<Transform>(
            find.byKey(const ValueKey('mismatch-metric-all-scale')),
          )
          .transform
          .entry(0, 0),
      1,
    );
    await mouse.removePointer();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'quantities are separate and pagination retains complete search results',
    (tester) async {
      tester.view.physicalSize = const Size(1721, 914);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = fixtures.FakeReviews()
        ..rows = List.generate(120, (i) => _row(i + 1));
      final controller = MismatchReviewController(repo);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MismatchReviewWorkspace(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('System Qty'), findsOneWidget);
      expect(find.text('Actual Qty'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('mismatch-system-qty-1')))
            .data,
        '42',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('mismatch-actual-qty-1')))
            .data,
        '37',
      );
      expect(find.byType(Image), findsNothing);
      expect(find.text('Showing 1 – 50 of 120 records'), findsOneWidget);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('Showing 51 – 100 of 120 records'), findsOneWidget);
      expect(find.text('ITEM 51'), findsOneWidget);
      expect(find.text('ITEM 1'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mismatch-page-size')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('25').last);
      await tester.pumpAndSettle();
      expect(find.text('Showing 1 – 25 of 120 records'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'ITEM 120');
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mismatch-system-qty-120')),
        findsOneWidget,
      );
      expect(find.text('Showing 1 – 1 of 1 records'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('render reference teal dashboard without product images', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final font in [
        (
          'ReviewPreview',
          [
            'C:/Windows/Fonts/segoeui.ttf',
            'C:/Windows/Fonts/seguisb.ttf',
            'C:/Windows/Fonts/segoeuib.ttf',
          ],
        ),
        (
          'MaterialIcons',
          [
            'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ],
        ),
      ]) {
        final loader = FontLoader(font.$1);
        for (final path in font.$2) {
          final file = File(path);
          if (await file.exists()) {
            loader.addFont(
              Future.value(ByteData.sublistView(await file.readAsBytes())),
            );
          }
        }
        await loader.load();
      }
    });
    final names = [
      'PIC THERMOGEL PACK 10 CM X 26 CM',
      'KIN GINGIVAL COMPLEX MOUTHWASH 250 ML',
      'KIN ORTHODONTIC WAX',
      'TYNOR WRIST & FOREARM SPLINT E-03 LEFT L',
      'MEDIX GAUZE SWABS STERILE 7.5 CM X 7.5 CM 8 PLY 50 S',
      'DOLCIVIT D3 50000 IU CAPS 12 S',
      'AURACOS PRO COLLAGENIUM DRINK 25 ML X 14 S 2 + 1 FREE',
      'LOMAR CREPE BANDAGE 5 CM',
    ];
    final branches = [
      'ZEINA - AD',
      'Rabdan2-AD',
      'Al Noud - Ain',
      'SAMA',
      'Asharej Branch',
      'ZEINA - AD',
      'SAMA',
      'Zakher Branch',
    ];
    StoreBranchIdentityRegistry.groups.value = {
      for (final branch in branches)
        branch.toUpperCase():
            branch == 'Asharej Branch' || branch == 'Zakher Branch'
            ? '71'
            : 'APG',
    };
    final statuses = [
      ...List.filled(131, 'priority_followup'),
      ...List.filled(151, 'recent_receipt_followup'),
      ...List.filled(18, 'adjustment_review'),
      ...List.filled(7024, 'data_review'),
      ...List.filled(3592, 'historical_review'),
      ...List.filled(306, 'surplus_review'),
      ...List.filled(275, 'unchanged_discrepancy'),
      ...List.filled(112, 'resolved'),
    ];
    final repo = fixtures.FakeReviews()
      ..rows = List.generate(statuses.length, (i) {
        final base = _row(
          i + 1,
          name: names[i % names.length],
          status: statuses[i],
        );
        return MismatchReview({
          ...base.raw,
          'branch_name': branches[i % branches.length],
          'system_stock': i == 1 ? 3 : 1,
          'actual_stock': 0,
          'diff': i == 1 ? -3 : -1,
        });
      })
      ..coverageOverride = [
        for (final company in ['APG', '71 Pharmacy L.L.C.'])
          {
            'company': company,
            'from_date': '2026-01-01',
            'to_date': '2026-11-18',
            'complete': true,
            'expected_rows': 1,
            'committed_rows': 1,
          },
      ];
    final controller = MismatchReviewController(repo);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    for (final size in [
      const Size(1721, 914),
      const Size(640, 1100),
      const Size(360, 1100),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              fontFamily: 'ReviewPreview',
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF007F90),
              ),
            ),
            home: Scaffold(
              body: MismatchReviewWorkspace(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsNothing);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          'outputs/mismatch-teal-dashboard-${size.width.toInt()}.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
