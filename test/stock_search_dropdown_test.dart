import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/presentation/widgets/inventory_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => StoreBranchIdentityRegistry.groups.value = const {});
  Finder search(String label) => find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == 'Search $label...',
  );
  Finder option(String text) => find
      .ancestor(of: find.text(text).last, matching: find.byType(InkResponse))
      .first;

  testWidgets('searches option labels and preserves nullable All selection', (
    tester,
  ) async {
    String? selected;
    final changes = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              height: 46,
              child: StatefulBuilder(
                builder: (_, setState) => InventoryDropdown<String>(
                  searchable: true,
                  label: 'Supplier',
                  value: selected,
                  items: const [
                    DropdownMenuItem(child: Text('All suppliers')),
                    DropdownMenuItem(
                      value: 'alpha-key',
                      child: Text('Alpha supplier'),
                    ),
                    DropdownMenuItem(
                      value: 'beta-key',
                      child: Text('Beta supplier'),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    selected = value;
                    changes.add(value);
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Choose Supplier'));
    await tester.pumpAndSettle();
    await tester.enterText(search('Supplier'), 'alpha');
    await tester.pumpAndSettle();
    expect(find.text('Beta supplier'), findsNothing);
    await tester.tap(option('Alpha supplier'));
    await tester.pumpAndSettle();
    expect(selected, 'alpha-key');
    expect(find.text('Alpha supplier'), findsOneWidget);
    await tester.tap(find.byTooltip('Choose Supplier'));
    await tester.pumpAndSettle();
    await tester.enterText(search('Supplier'), 'All suppliers');
    await tester.pumpAndSettle();
    await tester.tap(option('All suppliers'));
    await tester.pumpAndSettle();
    expect(changes, ['alpha-key', null]);
    expect(find.text('All suppliers'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('form selection keeps empty All key and handles no results', (
    tester,
  ) async {
    var selected = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 180,
              height: 46,
              child: StatefulBuilder(
                builder: (_, setState) => InventoryDropdownFormField<String>(
                  searchable: true,
                  initialValue: selected,
                  decoration: const InputDecoration(labelText: 'Stock status'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All stock')),
                    DropdownMenuItem(
                      value: 'no_stock',
                      child: Text('No Stock'),
                    ),
                  ],
                  onChanged: (value) => setState(() => selected = value!),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Choose Stock status'));
    await tester.pumpAndSettle();
    await tester.enterText(search('Stock status'), 'nothing matches');
    await tester.pumpAndSettle();
    expect(find.text('No matching options'), findsOneWidget);
    await tester.enterText(search('Stock status'), 'No Stock');
    await tester.pumpAndSettle();
    await tester.tap(option('No Stock'));
    await tester.pumpAndSettle();
    expect(selected, 'no_stock');
    await tester.tap(find.byTooltip('Choose Stock status'));
    await tester.pumpAndSettle();
    await tester.enterText(search('Stock status'), 'All stock');
    await tester.pumpAndSettle();
    await tester.tap(option('All stock'));
    await tester.pumpAndSettle();
    expect(selected, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'searchable branch labels refresh metadata and return raw identity',
    (tester) async {
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: InventoryDropdown<String>(
                  searchable: true,
                  branchNames: true,
                  label: 'Branch',
                  value: selected,
                  items: const [
                    DropdownMenuItem(child: Text('All branches')),
                    DropdownMenuItem(value: 'Al Ain', child: Text('Al Ain')),
                    DropdownMenuItem(value: 'City', child: Text('City')),
                  ],
                  onChanged: (value) => selected = value,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Choose Branch'));
      await tester.pumpAndSettle();
      StoreBranchIdentityRegistry.groups.value = {
        'AL AIN': '71',
        'CITY': 'APG',
      };
      await tester.pumpAndSettle();
      expect(find.text('71 Al Ain'), findsOneWidget);
      expect(find.text('City'), findsOneWidget);
      expect(find.text('71 City'), findsNothing);
      await tester.enterText(search('Branch'), '71 Al');
      await tester.pumpAndSettle();
      await tester.tap(option('71 Al Ain'));
      await tester.pumpAndSettle();
      expect(selected, 'Al Ain');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search popup fits a narrow screen with long option labels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 156,
              height: 46,
              child: InventoryDropdown<String>(
                searchable: true,
                label: 'Category',
                value: '',
                items: const [
                  DropdownMenuItem(value: '', child: Text('All categories')),
                  DropdownMenuItem(
                    value: 'long',
                    child: Text(
                      'A long category label that wraps inside the searchable menu',
                    ),
                  ),
                ],
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Choose Category'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(search('Category'));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(390));
    expect(tester.takeException(), isNull);
  });
}
