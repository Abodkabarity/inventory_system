import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/presentation/widgets/inventory_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> host(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 250, child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => StoreBranchIdentityRegistry.groups.value = const {});
  testWidgets(
    'null All branches selection is delivered and branch identities stay raw',
    (tester) async {
      String? selected = 'City';
      var calls = 0;
      await host(
        tester,
        StatefulBuilder(
          builder: (context, setState) => InventoryDropdown<String?>(
            label: 'Branch',
            branchNames: true,
            value: selected,
            items: const [
              DropdownMenuItem(value: null, child: Text('All branches')),
              DropdownMenuItem(value: 'City', child: Text('City')),
            ],
            onChanged: (value) {
              setState(() => selected = value);
              calls++;
            },
          ),
        ),
      );
      await tester.tap(find.byTooltip('Choose Branch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All branches'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(selected, isNull);
      expect(find.text('All branches'), findsOneWidget);
    },
  );
  testWidgets(
    '71 metadata refreshes the open menu without decorating other groups or stored values',
    (tester) async {
      String? selected;
      await host(
        tester,
        InventoryDropdown<String>(
          label: 'Branch',
          branchNames: true,
          value: 'City',
          items: const [
            DropdownMenuItem(value: 'Al Ain', child: Text('Al Ain')),
            DropdownMenuItem(value: 'City', child: Text('City')),
          ],
          onChanged: (value) => selected = value,
        ),
      );
      await tester.tap(find.byTooltip('Choose Branch'));
      await tester.pumpAndSettle();
      StoreBranchIdentityRegistry.groups.value = const {
        'AL AIN': '71',
        'CITY': 'APG',
      };
      await tester.pumpAndSettle();
      expect(find.text('71 Al Ain'), findsOneWidget);
      expect(find.text('71 City'), findsNothing);
      await tester.tap(find.text('71 Al Ain'));
      await tester.pumpAndSettle();
      expect(selected, 'Al Ain');
    },
  );
  testWidgets('disabled selectors and disabled options never submit changes', (
    tester,
  ) async {
    var calls = 0;
    await host(
      tester,
      InventoryDropdown<int>(
        label: 'Quarter',
        value: 1,
        items: const [
          DropdownMenuItem(value: 1, child: Text('Q1')),
          DropdownMenuItem(value: 2, enabled: false, child: Text('Q2')),
        ],
        onChanged: (value) => calls++,
      ),
    );
    await tester.tap(find.byTooltip('Choose Quarter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Q2'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await host(
      tester,
      InventoryDropdown<int>(
        label: 'Quarter',
        value: 1,
        items: const [DropdownMenuItem(value: 1, child: Text('Q1'))],
      ),
    );
    await tester.tap(find.text('Q1'));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<int>), findsNothing);
  });
  testWidgets(
    'form selectors validate, save and reflect a new controlled value',
    (tester) async {
      final form = GlobalKey<FormState>();
      int? saved;
      int? value;
      late StateSetter update;
      await host(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Form(
              key: form,
              child: InventoryDropdownFormField<int>(
                initialValue: value,
                decoration: const InputDecoration(labelText: 'KPI year'),
                items: const [
                  DropdownMenuItem(value: 2025, child: Text('2025')),
                  DropdownMenuItem(value: 2026, child: Text('2026')),
                ],
                validator: (v) => v == null ? 'Select a year' : null,
                onSaved: (v) => saved = v,
                onChanged: (v) => setState(() => value = v),
              ),
            );
          },
        ),
      );
      expect(form.currentState!.validate(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('Select a year'), findsOneWidget);
      await tester.tap(find.byTooltip('Choose KPI year'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025'));
      await tester.pumpAndSettle();
      expect(form.currentState!.validate(), isTrue);
      form.currentState!.save();
      expect(saved, 2025);
      update(() => value = 2026);
      await tester.pumpAndSettle();
      expect(find.text('2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
