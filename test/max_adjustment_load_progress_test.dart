import 'package:daily_order/presentation/inventory_dashboard/widgets/max_adjustment_load_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows actual counts and a determinate loading percentage', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MaxAdjustmentLoadProgress(loaded: 4000, total: 19716),
        ),
      ),
    );
    expect(find.text('Loaded 4,000 of 19,716 records (20%)'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo(4000 / 19716, .0001),
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MaxAdjustmentLoadProgress(loaded: 0, total: 0)),
      ),
    );
    expect(find.text('Counting max adjustments...'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MaxAdjustmentLoadProgress(loaded: 19716, total: 19716),
        ),
      ),
    );
    expect(find.text('Preparing the table...'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
