import 'package:daily_order/domain/entities/items_tracker_record.dart';
import 'package:daily_order/presentation/items_tracker/widgets/items_tracker_email_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ItemsTrackerRecord record(
  String id, {
  String team = 'category',
  bool queued = true,
  String email = '',
  String status = 'pending',
}) => ItemsTrackerRecord.fromMap({
  'id': id,
  'item_code': id,
  'item_name': 'Product $id',
  'company': 'Company $id',
  'follow_up_role': team,
  'required_qty': 4,
  'required_value': 50,
  'inventory_note': 'Reason for $id',
  'created_at': DateTime.now().toIso8601String(),
  if (queued) 'email_queued_at': '2026-10-19T08:00:00Z',
  'email_status': email,
  'case_status': status,
});

void main() {
  testWidgets('saved drafts are continued separately from new selections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItemsTrackerEmailSelection(
            newOnly: true,
            records: [
              record('fresh'),
              record('saved', email: 'draft'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('emailSelect:fresh')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('emailSelect:saved')),
          )
          .value,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('emailSelect:saved')));
    await tester.pumpAndSettle();
    expect(find.text('Continue saved draft'), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('emailSelect:fresh')),
          )
          .value,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('emailSelect:fresh')));
    await tester.pumpAndSettle();
    expect(find.text('Continue saved draft'), findsNothing);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('emailSelect:saved')),
          )
          .value,
      isFalse,
    );
  });
  test(
    'new queue requires a server marker and excludes sent or done products',
    () {
      expect(record('legacy', queued: false).isNewEmail, isFalse);
      expect(record('new').isNewEmail, isTrue);
      expect(record('draft', email: 'draft').isNewEmail, isTrue);
      expect(record('sent', email: 'sent').isNewEmail, isFalse);
      expect(record('done', status: 'done').isNewEmail, isFalse);
    },
  );

  testWidgets(
    'new queue selects one team and preserves selection through search',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      List<ItemsTrackerRecord>? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showTrackerEmailSelection(
                    context: context,
                    newOnly: true,
                    records: [
                      record('A'),
                      record('B'),
                      record('purchase', team: 'purchase'),
                      record('legacy', queued: false),
                      record('sent', email: 'sent'),
                      record('done', status: 'done'),
                    ],
                  );
                },
                child: const Text('Choose'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      for (final id in ['legacy', 'sent', 'done', 'purchase']) {
        expect(find.byKey(ValueKey('emailSelect:$id')), findsNothing);
      }
      await tester.enterText(find.byType(TextField), 'Product A');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('emailSelect:B')), findsNothing);
      expect(find.text('2 selected'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Category (2)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Purchase (1)').last);
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byKey(const ValueKey('emailSelect:A')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('prepareSelectedEmail')));
      await tester.pumpAndSettle();
      expect(selected!.map((r) => r.id), ['purchase']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual selection includes existing unsent records and fits compact screens',
    (tester) async {
      tester.view.physicalSize = const Size(430, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ItemsTrackerEmailSelection(
              records: [record('legacy', queued: false)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0 selected'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('emailSelect:legacy')));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('prepareSelectedEmail')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
