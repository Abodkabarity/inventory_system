import 'dart:async';

import 'package:daily_order/domain/repositories/inventory_repository.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/inventory_daily_order_exports.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repository implements InventoryRepository {
  final dates = Completer<List<String>>();
  final requestedDates = <String>[];
  final pendingDownload = Completer<String?>();

  @override
  Future<List<String>> fetchDailyOrderExportDates() => dates.future;

  @override
  Future<String?> fetchDailyOrderExportFileUrl({required String runDate}) {
    requestedDates.add(runDate);
    return pendingDownload.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _openExports(WidgetTester tester, _Repository repository) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  InventoryDailyOrderExports(repository: repository),
            ),
            child: const Text('Open exports'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open exports'));
  await tester.pump();
}

void main() {
  testWidgets(
    'the download control requests the original date and recovers from failure',
    (tester) async {
      final repository = _Repository();
      await _openExports(tester, repository);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repository.dates.complete(['2026-11-16', '2026-11-15']);
      await tester.pumpAndSettle();

      expect(find.text('2 Excel exports'), findsOneWidget);
      expect(find.text('Monday'), findsOneWidget);
      await tester.tap(find.byTooltip('Download export for 16 Nov 2026'));
      await tester.pump();
      expect(repository.requestedDates, ['2026-11-16']);
      expect(find.text('Preparing…'), findsOneWidget);
      expect(
        tester
            .widgetList<FilledButton>(find.byType(FilledButton))
            .every((button) => button.onPressed == null),
        isTrue,
      );

      repository.pendingDownload.complete(null);
      await tester.pumpAndSettle();
      expect(
        find.text('Couldn’t start the download. Try again.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Download export for 16 Nov 2026'), findsOneWidget);
    },
  );

  testWidgets(
    'a compact dialog scrolls, and closing it during download keeps the page open',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 430));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repository = _Repository();
      repository.dates.complete([
        for (var day = 16; day >= 1; day--)
          '2026-11-${day.toString().padLeft(2, '0')}',
      ]);
      await _openExports(tester, repository);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close exports'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final target = find.byTooltip('Download export for 1 Nov 2026');
      await tester.scrollUntilVisible(
        find.text('1 Nov 2026'),
        140,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pump();
      expect(repository.requestedDates, ['2026-11-01']);

      await tester.tap(find.byTooltip('Close exports'));
      await tester.pumpAndSettle();
      repository.pendingDownload.complete('https://example.test/download');
      await tester.pumpAndSettle();
      expect(find.text('Open exports'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
