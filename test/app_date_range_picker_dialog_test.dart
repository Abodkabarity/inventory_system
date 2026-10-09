import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daily_order/presentation/widgets/app_date_range_picker_dialog.dart';

void main() {
  testWidgets('Last Month selects the previous calendar month', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    DateTimeRange? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<DateTimeRange>(
                  context: context,
                  builder: (_) => AppDateRangePickerDialog(
                    initialRange: DateTimeRange(
                      start: DateTime(2026, 1, 1),
                      end: DateTime(2026, 1, 31),
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    await tester.tap(find.text('Last Month'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final now = DateTime.now();
    expect(result?.start, DateTime(now.year, now.month - 1, 1));
    expect(result?.end, DateTime(now.year, now.month, 0));
  });

  testWidgets('completion window uses shared From and To design', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppDateRangePickerDialog(
            initialRange: DateTimeRange(
              start: DateTime(now.year, now.month, now.day),
              end: DateTime(now.year, now.month, now.day + 1),
            ),
            mode: AppDateRangePickerMode.deadline,
          ),
        ),
      ),
    );

    expect(find.text('QUICK SELECT'), findsOneWidget);
    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('2 Days'), findsOneWidget);
    expect(find.text('1 Week'), findsOneWidget);
    expect(find.text('2 Weeks'), findsOneWidget);
    expect(find.text('1 Month'), findsOneWidget);
    expect(find.text('Last Month'), findsNothing);
    expect(find.text('Last 6 Months'), findsNothing);
    expect(find.text('DURATION'), findsNothing);
    expect(find.text('Start'), findsNothing);
    expect(find.text('Deadline'), findsNothing);
  });
}
