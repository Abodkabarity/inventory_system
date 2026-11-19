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

const _product = 'PIGEON BOTTLE GLASS S 120 ML K4-A282';

class _ModalReviews extends fixtures.FakeReviews {
  _ModalReviews() {
    final base = fixtures.sample(1);
    rows = [
      MismatchReview({
        ...base.raw,
        'branch_name': 'Rabdan2-AD',
        'item_code': '16-02-00525',
        'item_name': _product,
        'analysis': {
          ...base.analysis,
          'event_at': '2026-11-18T20:52:11',
          'baseline_qty': 0,
          'last_zero': '2026-11-08',
          'last_receipt': '2026-11-15',
          'coverage_through': '2026-11-18',
          'receipt_qty': 1,
        },
      }),
      for (var i = 2; i <= 8; i++)
        fixtures.sample(i, name: 'KIN ORTHODONTIC WAX $i'),
    ];
  }
  @override
  Future<Map<String, dynamic>?> detail(int id) async {
    if (id != 1) return super.detail(id);
    detailCalls++;
    return {
      'analysis': rows.first.analysis,
      'evidence': {
        'baseline': [
          {'qty': '0', 'company': 'APG'},
        ],
        'movements': [
          {
            'trans_date': '2026-11-15',
            'qty': '1',
            'mode': 'IN',
            'trans_type': 'StockTransferTo',
            'trans_no': 'T-001',
          },
        ],
        'events': [
          {
            'action': 'add',
            'changed_at': '2026-11-18T20:52:11',
            'new_system_stock': '1',
            'new_actual_stock': '0',
            'new_diff': '-1',
          },
        ],
      },
    };
  }
}

void main() {
  testWidgets('teal modal keeps tabs, live branch identity and close action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1672, 941);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = MismatchReviewController(_ModalReviews());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MismatchReviewWorkspace(controller: controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(_product));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(MismatchReviewDetail)).width, 1028);
    expect(find.text('What happened to this item?'), findsOneWidget);
    expect(find.text('Missing: Qty 1. Check with the branch.'), findsOneWidget);
    expect(find.text('Stock Movement Timeline'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    StoreBranchIdentityRegistry.groups.value = {'RABDAN2-AD': '71'};
    await tester.pumpAndSettle();
    expect(find.text('71 Rabdan2-AD'), findsWidgets);
    await tester.tap(find.text('Movements'));
    await tester.pumpAndSettle();
    expect(find.text('Adj No T-001'), findsOneWidget);
    await tester.tap(find.text('Stock corrections (0)'));
    await tester.pumpAndSettle();
    expect(
      find.text('No INVAdjustment found in available 2026 history.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Mismatch history'));
    await tester.pumpAndSettle();
    expect(find.text('ADD'), findsOneWidget);
    await tester.tap(find.byTooltip('Close review'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('render reference modal on desktop, tablet and phone', (
    tester,
  ) async {
    final previousDisableShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      await tester.runAsync(() async {
        for (final family in [
          (
            'ModalPreview',
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
          final loader = FontLoader(family.$1);
          for (final path in family.$2) {
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
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      StoreBranchIdentityRegistry.groups.value = {'RABDAN2-AD': 'APG'};
      for (final size in [
        const Size(1672, 941),
        const Size(1000, 1000),
        const Size(640, 1000),
        const Size(360, 1000),
      ]) {
        tester.view.physicalSize = size;
        final controller = MismatchReviewController(_ModalReviews());
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                fontFamily: 'ModalPreview',
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
        await tester.tap(find.text(_product));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('What happened to this item?'), findsOneWidget);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            'outputs/mismatch-teal-modal-${size.width.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
        await tester.tap(find.byTooltip('Close review'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    } finally {
      debugDisableShadows = previousDisableShadows;
    }
  });
}
