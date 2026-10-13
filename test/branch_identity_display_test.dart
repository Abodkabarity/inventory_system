import 'package:daily_order/core/utils/branch_csv_display.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/branches_tracker_timeline_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    StoreBranchIdentityRegistry.groups.value = const {
      'AL AIN': '71',
      'CITY': 'APG',
      'A,"B': '71',
    };
  });

  tearDown(() => StoreBranchIdentityRegistry.groups.value = const {});

  test('prefixes only group 71 and does not prefix twice', () {
    expect(StoreBranchIdentityRegistry.displayName('Al Ain'), '71 Al Ain');
    expect(StoreBranchIdentityRegistry.displayName('71 Al Ain'), '71 Al Ain');
    expect(StoreBranchIdentityRegistry.displayName('City'), 'City');
    expect(
      StoreBranchIdentityRegistry.exportValue('branch_name', 'Al Ain'),
      '71 Al Ain',
    );
    expect(
      StoreBranchIdentityRegistry.exportValue('item_name', 'Al Ain'),
      'Al Ain',
    );
  });

  test('decorates a selected CSV field and preserves quoted neighbours', () {
    expect(
      decorateBranchCsvField('123,"Al Ain","item, one"', 1),
      '123,"71 Al Ain","item, one"',
    );
    expect(
      decorateBranchCsvField('123,"A,""B","item, one"', 1),
      '123,"71 A,""B","item, one"',
    );
    expect(decorateBranchCsvField('123,City,item', 1), '123,City,item');
  });

  testWidgets('tracker refreshes late branch metadata and searches 71 labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    StoreBranchIdentityRegistry.groups.value = const {};
    final rows = [
      for (final branch in ['Zakher Branch', 'City'])
        {
          'branch_name': branch,
          'source_table': 'mismatch_log',
          'change_type': 'update',
          'item_name': 'Sample item',
          'item_code': '1234',
        },
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BranchesTrackerTimelineTab(rows: rows, loading: false),
        ),
      ),
    );
    expect(find.text('Zakher Branch'), findsOneWidget);
    StoreBranchIdentityRegistry.groups.value = const {
      'ZAKHER BRANCH': '71',
      'CITY': 'APG',
    };
    await tester.pumpAndSettle();
    expect(find.text('71 Zakher Branch'), findsOneWidget);
    expect(find.text('Zakher Branch'), findsNothing);
    expect(find.text('City'), findsOneWidget);
    expect(find.text('71 City'), findsNothing);

    await tester.enterText(find.byType(TextField), '71 Zakher');
    await tester.pumpAndSettle();
    expect(find.text('71 Zakher Branch'), findsOneWidget);
    expect(find.text('City'), findsNothing);
    expect(find.text('1 results'), findsOneWidget);
    expect(rows.first['branch_name'], 'Zakher Branch');
    expect(tester.takeException(), isNull);
  });
}
