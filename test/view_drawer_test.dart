import 'package:daily_order/domain/entities/inventory_page.dart';
import 'package:daily_order/presentation/auth/bloc/auth_bloc.dart';
import 'package:daily_order/presentation/auth/bloc/auth_state.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/inventory_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _AuthBloc extends Cubit<AuthState> implements AuthBloc {
  _AuthBloc() : super(AuthState.initial());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('view drawer exposes only the five requested pages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = _AuthBloc();
    addTearDown(auth.close);
    var page = InventoryPageType.stockManagement;
    final selections = <InventoryPageType>[];
    await tester.pumpWidget(
      BlocProvider<AuthBloc>.value(
        value: auth,
        child: MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => InventoryDrawer.view(
                selectedPage: page,
                onSelected: (next) => setState(() {
                  selections.add(next);
                  page = next;
                }),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final (title, target) in [
      ('Overview', InventoryPageType.stockManagement),
      ('MRN Overview', InventoryPageType.mrnOverview),
      ('Near Expiry', InventoryPageType.nearExpiry),
      ('Availability KPI', InventoryPageType.availabilityKpi),
      ('Fill Rate KPI', InventoryPageType.fillRateKpi),
    ]) {
      expect(find.text(title), findsOneWidget);
      await tester.ensureVisible(find.text(title));
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(page, target);
    }
    expect(selections.length, 5);
    for (final title in [
      'Dashboard',
      'ORDER MANAGEMENT',
      'OPERATIONS',
      'CONFIGURATION',
      'Daily Order',
      'Max Adjustment',
      'Formulary',
      'Assortment',
      'TMA',
      'Additional Orders',
      'Items Tracker',
      'Allocation',
      'Stock Check',
      'Shortage',
      'Submission Tracker',
      'Branches Tracker',
      'Mismatch Report',
      'Additional Analysis',
      'Order Edit Analysis',
      'Branch Setting',
    ]) {
      expect(find.text(title), findsNothing, reason: title);
    }
    expect(find.text('Log out'), findsOneWidget);
    // No InventoryBloc or Supabase initialization is needed for this drawer.
    expect(tester.takeException(), isNull);
  });
}
