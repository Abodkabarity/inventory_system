import 'dart:io';
import 'dart:async';
import 'package:daily_order/core/utils/stock_register_export.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/domain/entities/stock_management.dart';
import 'package:daily_order/domain/entities/stock_mrn_receipt_history.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_mrn_receipts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'stock_catalog_test.dart' as catalog;

final completeReceipt = StockManagementItem({
  'item_code': '16-01-07742',
  'last_mrn_date': '2026-10-21',
  'last_mrn_no': '106431',
  'last_mrn_qty': 230,
  'received_quantity': 230,
  'ordered_quantity': 630,
  'receipt_count': 4,
  'expiry_date': '2028-09-01',
  'expiry_count': 1,
  'receipt_lines': [
    for (final (number, qty) in [
      ('106431', 100),
      ('106430', 15),
      ('106403', 100),
      ('106402', 15),
    ])
      {
        'mrn_no': number,
        'reference': 'REF-$number',
        'warehouse': number == '106431' ? 'Beta' : 'Alpha',
        'expiry_date': '2028-09-01',
        'vendor': 'unicare medical trading l.l.c',
        'ordered_qty': qty == 100 ? 300 : 15,
        'received_qty': qty,
      },
  ],
});

void main() {
  setUpAll(() async {
    final root = Platform.environment['CATALOG_FONT_ROOT'];
    if (root == null) return;
    for (final (family, file) in [
      ('Roboto', 'roboto-regular.ttf'),
      ('MaterialIcons', 'MaterialIcons-Regular.otf'),
    ]) {
      final loader = FontLoader(family)
        ..addFont(
          Future.value(
            ByteData.sublistView(File('$root/$file').readAsBytesSync()),
          ),
        );
      await loader.load();
    }
  });
  tearDown(() => StoreBranchIdentityRegistry.groups.value = const {});
  test('Excel contains all four receipts as the daily total', () {
    final row = stockRegisterExportRow(completeReceipt);
    expect(row['Total Qty'], 230);
    expect(row['Ordered Qty'], 630);
  });
  for (final width in [1500.0, 540.0]) {
    testWidgets(
      'collapsed history shows summary immediately without loading rows at $width',
      (tester) async {
        var calls = 0;
        final boundary = GlobalKey();
        await catalog.app(
          tester,
          StockMrnReceipts(
            item: StockManagementItem({
              ...completeReceipt.data,
              'receipt_history_summary': {
                'mrn_count': 46,
                'day_count': 37,
                'received_qty': 292,
                'from': '2026-01-24',
                'through': '2026-10-28',
              },
            }),
            loadHistory: () async {
              calls++;
              throw StateError('No row request expected');
            },
          ),
          size: Size(width, 880),
          boundary: boundary,
        );
        expect(find.text('MRN receipt history (46)'), findsOneWidget);
        expect(find.text('Total Qty 292'), findsOneWidget);
        expect(
          find.text('24 Jan 2026 – 28 Oct 2026 · 37 receipt dates'),
          findsOneWidget,
        );
        expect(find.byType(DataTable), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(calls, 0);
        expect(completeReceipt.number('received_quantity'), 230);
        await catalog.capture(
          tester,
          boundary,
          'mrn_collapsed_summary_${width.toInt()}',
        );
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets(
      'complete history is lazy and keeps earlier receipts at $width',
      (tester) async {
        final pending = Completer<StockMrnReceiptHistory>();
        var calls = 0;
        final boundary = GlobalKey();
        await catalog.app(
          tester,
          StockMrnReceipts(
            item: completeReceipt,
            loadHistory: () {
              calls++;
              return pending.future;
            },
          ),
          size: Size(width, 880),
          boundary: boundary,
        );
        expect(calls, 0);
        await tester.tap(find.text('MRN receipt history'));
        await tester.pump();
        expect(calls, 1);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        pending.complete(
          StockMrnReceiptHistory(
            lines: [
              for (final line in completeReceipt.list('receipt_lines'))
                {...line, 'mrn_date': '2026-10-21'},
              {
                'mrn_date': '2026-01-13',
                'mrn_no': 'OLD',
                'reference': 'OLD-REF',
                'warehouse': 'main virtual',
                'received_qty': 50,
                'ordered_qty': 50,
              },
            ],
            mrnCount: 5,
            dayCount: 2,
            receivedQty: 280,
            from: '2026-01-13',
            through: '2026-10-21',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('MRN receipt history (5)'), findsOneWidget);
        expect(find.textContaining('2 receipt dates'), findsOneWidget);
        expect(find.text('Total Qty 280'), findsOneWidget);
        expect(find.text('13 Jan 2026'), findsOneWidget);
        expect(find.text('OLD-REF'), findsOneWidget);
        expect(tester.widget<DataTable>(find.byType(DataTable)).rows.length, 5);
        StoreBranchIdentityRegistry.groups.value = {
          'BETA': '71',
          'ALPHA': 'APG',
        };
        await tester.pumpAndSettle();
        expect(find.text('71 Beta'), findsOneWidget);
        expect(find.text('Alpha'), findsNWidgets(3));
        await catalog.capture(
          tester,
          boundary,
          'mrn_full_history_${width.toInt()}',
        );
        await tester.tap(find.text('MRN receipt history (5)'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('MRN receipt history (5)'));
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(tester.takeException(), isNull);
      },
    );
    testWidgets('all receipt references and quantities at width $width', (
      tester,
    ) async {
      final boundary = GlobalKey();
      await catalog.app(
        tester,
        StockMrnReceipts(item: completeReceipt),
        size: Size(width, 880),
        boundary: boundary,
      );
      expect(find.text('MRN receipts (4)'), findsOneWidget);
      expect(find.textContaining('Total Qty 230'), findsOneWidget);
      expect(find.byType(DataTable), findsNothing);
      await tester.tap(find.text('MRN receipts (4)'));
      await tester.pumpAndSettle();
      expect(tester.widget<DataTable>(find.byType(DataTable)).rows.length, 4);
      for (final number in ['106431', '106430', '106403', '106402']) {
        expect(find.text('REF-$number'), findsOneWidget);
      }
      expect(find.text('100'), findsNWidgets(2));
      expect(find.text('15'), findsNWidgets(4));
      StoreBranchIdentityRegistry.groups.value = {'BETA': '71', 'ALPHA': 'APG'};
      await tester.pumpAndSettle();
      expect(find.text('71 Beta'), findsOneWidget);
      expect(find.text('Alpha'), findsNWidgets(3));
      expect(find.text('71 Alpha'), findsNothing);
      await catalog.capture(
        tester,
        boundary,
        'mrn_complete_receipts_${width.toInt()}',
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'history errors are retryable and do not claim latest-day rows are complete',
    (tester) async {
      var calls = 0;
      await catalog.app(
        tester,
        StockMrnReceipts(
          item: completeReceipt,
          loadHistory: () async {
            if (++calls == 1) throw StateError('failed');
            return const StockMrnReceiptHistory(
              lines: [],
              mrnCount: 0,
              dayCount: 0,
              receivedQty: 0,
              from: '',
              through: '',
            );
          },
        ),
      );
      await tester.tap(find.text('MRN receipt history'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Could not load receipt history'),
        findsOneWidget,
      );
      expect(find.byType(DataTable), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('No approved MRN receipts found.'), findsOneWidget);
      expect(calls, 2);
    },
  );
}
