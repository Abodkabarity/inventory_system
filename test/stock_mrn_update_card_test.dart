import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_mrn_update_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('card remains readable in a narrow window with enlarged text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 500));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: StockMrnUpdateCard(
              loader: () async => {
                'status': 'complete',
                'last_success_at': '2026-10-26T22:15:00Z',
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('27 Oct 2026'), findsOneWidget);
    expect(find.textContaining('2:15 AM'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
  testWidgets('shows the converted server last success while an import is running', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StockMrnUpdateCard(
            loader: () async => {
              'status': 'downloading',
              'last_success_at': '2026-10-27T05:15:00Z',
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Last MRN update'), findsOneWidget);
    expect(find.textContaining('9:15 AM'), findsOneWidget);
    expect(find.textContaining('Dubai'), findsNothing);
    expect(find.textContaining('Updating MRN'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'new completed import refreshes the page once, failures keep the old time',
    (tester) async {
      var value = <String, dynamic>{
        'status': 'complete',
        'last_success_at': '2026-10-27T05:00:00Z',
      };
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StockMrnUpdateCard(
              loader: () async => value,
              onUpdated: () => changes++,
            ),
          ),
        ),
      );
      await tester.pump();
      value = {
        'status': 'failed',
        'has_error': true,
        'last_success_at': '2026-10-27T05:00:00Z',
      };
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(changes, 0);
      expect(find.textContaining('Latest attempt failed'), findsOneWidget);
      expect(find.textContaining('9:00 AM'), findsOneWidget);
      value = {'status': 'complete', 'last_success_at': '2026-10-27T06:00:00Z'};
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(changes, 1);
      expect(find.textContaining('10:00 AM'), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(changes, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('no successful import is never shown as a successful timestamp', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StockMrnUpdateCard(
            loader: () async => {'status': 'failed', 'has_error': true},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('No successful hourly update yet'), findsOneWidget);
    expect(find.textContaining('Latest attempt failed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
