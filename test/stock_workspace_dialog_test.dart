import 'dart:io';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/domain/entities/stock_management.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_catalog_product_dialog.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_catalog_visuals.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_expiry_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_management_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'stock_catalog_test.dart' as catalog;
import 'stock_management_test.dart' as mrn;
import 'stock_expiry_test.dart' as expiry;

class SharedDetailSource extends mrn.FakeStockSource {
  @override
  Future<StockManagementItem> fetchItem(String code) async =>
      StockManagementItem({
        ...catalog.fixture().data,
        'item_code': code,
        'reference': 'IN26217285',
        'mrn_details': mrn.product().data,
        'branches': [
          {
            'branch': 'Alpha',
            'stock': 50,
            'recent_sales': 10,
            'last_3_sales': 2,
            'baseline_sales': 8,
            'sales_2025': 100,
            'sales_2026': 70,
          },
          {
            'branch': 'Beta',
            'stock': 30,
            'recent_sales': 6,
            'last_3_sales': 1,
            'baseline_sales': 5,
            'sales_2025': 60,
            'sales_2026': 40,
          },
        ],
      });
}

void main() {
  setUpAll(() async {
    final root = Platform.environment['CATALOG_FONT_ROOT'];
    if (root == null) return;
    for (final (family, file) in [
      ('Roboto', 'roboto-regular.ttf'),
      ('MaterialIcons', 'MaterialIcons-Regular.otf'),
    ]) {
      final font = FontLoader(family)
        ..addFont(
          Future.value(
            ByteData.sublistView(File('$root/$file').readAsBytesSync()),
          ),
        );
      await font.load();
    }
  });
  tearDown(() => StoreBranchIdentityRegistry.groups.value = const {});
  for (final size in [const Size(1500, 960), const Size(620, 880)]) {
    testWidgets(
      'shared MRN charts, reference and asynchronous 71 labels at ${size.width}',
      (tester) async {
        final boundary = GlobalKey();
        await catalog.app(
          tester,
          Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showStockManagementProductDetails(
                  context,
                  mrn.product(),
                  dataSource: SharedDetailSource(),
                ),
                child: const Text('Open product'),
              ),
            ),
          ),
          size: size,
          boundary: boundary,
        );
        await tester.tap(find.text('Open product'));
        await tester.pumpAndSettle();
        expect(find.byType(StockCatalogProductDialog), findsOneWidget);
        for (final label in [
          'Monthly sales & momentum',
          'Stock / Sales',
          'LAST 3 DAYS QTY',
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.text('Reference  IN26217285'), findsOneWidget);
        expect(find.text('MRN receipt details'), findsNothing);
        expect(find.text('MRN number'), findsNothing);
        expect(find.text('Expiry received Qty'), findsNothing);
        final receiptCards = find.byKey(const ValueKey('mrn-receipt-cards'));
        final cardWidgets = tester
            .widgetList<CatalogMetric>(
              find.descendant(
                of: receiptCards,
                matching: find.byType(CatalogMetric),
              ),
            )
            .toList();
        expect(cardWidgets.map((c) => c.title), [
          'LAST MRN',
          'VENDOR',
          'EXPIRY DATE',
          'ORDERED QTY',
          'RECEIVED QTY',
        ]);
        expect(cardWidgets.every((c) => c.caption.isEmpty), isTrue);
        final heights = find
            .descendant(of: receiptCards, matching: find.byType(CatalogMetric))
            .evaluate()
            .map((e) => tester.getSize(find.byWidget(e.widget)).height)
            .toSet();
        expect(heights.length, 1);

        expect(find.text('ABCDEFGHIJ'), findsOneWidget);
        expect(find.text('abcdefghijk-latest'), findsNothing);
        await catalog.capture(
          tester,
          boundary,
          'mrn_shared_dialog_${size.width.toInt()}',
        );
        StoreBranchIdentityRegistry.groups.value = {
          'ALPHA': 'APG',
          'BETA': '71',
        };
        await tester.pumpAndSettle();
        final branchSearch = find.widgetWithText(
          TextField,
          'Search branch (including 71)',
        );
        await tester.ensureVisible(branchSearch);
        await tester.pumpAndSettle();
        await tester.enterText(branchSearch, '71 Beta');
        await tester.pumpAndSettle();
        final table = tester.widget<DataTable>(find.byType(DataTable));
        expect(table.rows.length, 1);
        expect((table.rows.single.cells.first.child as Text).data, '71 Beta');
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'expiry preserves review edits and receipt evidence in the shared dialog',
    (tester) async {
      final source = expiry.FakeExpirySource();
      final boundary = GlobalKey();
      await catalog.app(
        tester,
        StockExpiryPage(
          dataSource: source,
          productDataSource: SharedDetailSource(),
        ),
        size: const Size(1500, 960),
        boundary: boundary,
      );
      await tester.tap(find.text(mrn.product().name.toUpperCase()).first);
      await tester.pumpAndSettle();
      expect(find.byType(StockCatalogProductDialog), findsOneWidget);
      expect(find.text('Reference  IN26217285'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('expiry-review-badges')),
          matching: find.text('Vendor OLDER-VEND'),
        ),
        findsOneWidget,
      );
      expect(find.text('Receipt evidence (1)'), findsOneWidget);
      expect(find.text('Monthly sales & momentum'), findsOneWidget);
      final note = find.byKey(const ValueKey('expiry-note-field'));
      final toolbar = find.byKey(const ValueKey('expiry-note-toolbar'));
      expect(toolbar, findsOneWidget);
      final review = find.byKey(const ValueKey('expiry-review-button'));
      final button = tester.widget<FilledButton>(review);
      expect(button.style!.foregroundColor!.resolve({}), Colors.white);
      expect(
        tester.getRect(note).center.dy,
        closeTo(tester.getRect(review).center.dy, 2),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('expiry-note-actions'))).left,
        greaterThan(tester.getRect(note).right),
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('expiry-review-badges')))
            .height,
        lessThan(60),
      );
      await catalog.capture(tester, boundary, 'expiry_compact_review_dialog');

      await tester.ensureVisible(note);
      await tester.enterText(note, 'Inspect remaining batch');
      StoreBranchIdentityRegistry.groups.value = {'ALPHA': 'APG', 'BETA': '71'};
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(note).controller!.text,
        'Inspect remaining batch',
      );
      await tester.pumpAndSettle();
      final save = find.text('Save note');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(source.items.first.note, 'Inspect remaining batch');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'compact expiry review keeps edits and cards intact with larger text',
    (tester) async {
      final source = expiry.FakeExpirySource();
      await expiry.showExpiry(
        tester,
        source,
        productSource: SharedDetailSource(),
        size: const Size(540, 960),
        textScale: 1.5,
      );
      await tester.tap(find.text(mrn.product().name.toUpperCase()).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('expiry-note-toolbar')), findsNothing);
      final note = find.byKey(const ValueKey('expiry-note-field'));
      await tester.ensureVisible(note);
      await tester.pumpAndSettle();
      await tester.enterText(
        note,
        'Keep this note on a smaller screen\nSecond line stays saved',
      );
      await tester.pumpAndSettle();
      final save = find.text('Save note');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        source.items.first.note,
        'Keep this note on a smaller screen\nSecond line stays saved',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
