import 'package:daily_order/core/theme/app_colors.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/branches_tracker_timeline_tab.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/tracker_branch_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => StoreBranchIdentityRegistry.groups.value = const {});

  Finder popupSearch() => find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == 'Search branches...',
  );

  testWidgets(
    'searches displayed 71 names and filters by raw branch identity',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      StoreBranchIdentityRegistry.groups.value = const {
        'AL AIN': '71',
        'CITY': 'APG',
      };
      final rows = [
        for (final branch in ['Al Ain', 'City'])
          {
            'branch_name': branch,
            'source_table': 'mismatch_log',
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
      await tester.tap(find.byKey(const ValueKey('tracker-branch-dropdown')));
      await tester.pumpAndSettle();
      expect(find.text('Choose a branch'), findsOneWidget);
      await tester.enterText(popupSearch(), '71 Al');
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .ancestor(
              of: find.text('71 Al Ain').last,
              matching: find.byType(InkResponse),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('1 results'), findsOneWidget);
      expect(find.text('City'), findsNothing);
      expect(
        tester
            .widget<TrackerBranchDropdown>(find.byType(TrackerBranchDropdown))
            .value,
        'Al Ain',
      );
      expect(rows.first['branch_name'], 'Al Ain');
      await tester.tap(find.byTooltip('All branches'));
      await tester.pumpAndSettle();
      expect(find.text('2 results'), findsOneWidget);
      expect(find.text('City'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact selector keeps long branch names and popup in bounds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const name = 'A long branch name that should remain readable in the menu';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: 280,
              child: TrackerBranchDropdown(
                value: name,
                items: const ['ALL', name, 'City'],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('tracker-branch-dropdown')));
    await tester.pumpAndSettle();
    final search = tester.getRect(popupSearch());
    expect(search.left, greaterThanOrEqualTo(0));
    expect(search.right, lessThanOrEqualTo(390));
    expect(tester.takeException(), isNull);
  });

  testWidgets('open popup refreshes metadata, searches and shows empty state', (
    tester,
  ) async {
    StoreBranchIdentityRegistry.groups.value = const {};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              child: TrackerBranchDropdown(
                value: 'ALL',
                items: const ['ALL', 'Al Ain', 'City'],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('tracker-branch-dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('Al Ain'), findsOneWidget);
    StoreBranchIdentityRegistry.groups.value = const {
      'AL AIN': '71',
      'CITY': 'APG',
    };
    await tester.pumpAndSettle();
    expect(find.text('71 Al Ain'), findsOneWidget);
    expect(find.text('71 City'), findsNothing);
    await tester.enterText(popupSearch(), '71 Al');
    await tester.pumpAndSettle();
    expect(find.text('71 Al Ain'), findsOneWidget);
    expect(find.text('City'), findsNothing);
    final search = tester.widget<TextField>(popupSearch());
    expect(search.cursorColor, AppColors.primaryColor);
    await tester.enterText(popupSearch(), 'No such branch');
    await tester.pumpAndSettle();
    expect(find.text('No matching branches'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
