import 'package:daily_order/data/datasources/remote/sales_report_remote_ds.dart';
import 'package:daily_order/domain/entities/inventory_page.dart';
import 'package:daily_order/domain/entities/items_tracker_record.dart';
import 'package:daily_order/domain/repositories/items_tracker_repository.dart';
import 'package:daily_order/presentation/auth/bloc/auth_bloc.dart';
import 'package:daily_order/presentation/auth/bloc/auth_state.dart';
import 'package:daily_order/presentation/category_dashboard/page/category_dashboard_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/inventory_drawer.dart';
import 'package:daily_order/presentation/items_tracker/page/items_tracker_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

class _AuthBloc extends Cubit<AuthState> implements AuthBloc {
  _AuthBloc() : super(AuthState.initial());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TrackerRepository implements ItemsTrackerRepository {
  int loads = 0;
  @override
  Future<List<ItemsTrackerRecord>> fetchRecords() async {
    loads++;
    return [];
  }

  @override
  Future<List<String>> fetchItemStatuses() async => [];
  @override
  Future<List<ItemsTrackerNotification>> fetchNotifications() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SalesSource extends SalesReportRemoteDs {
  _SalesSource()
    : super(
        SupabaseClient(
          'https://example.supabase.co',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  int monthlyLoads = 0;
  int dailyLoads = 0;
  @override
  Future<Map<String, dynamic>> fetch({
    List<String> months = const [],
    bool request = false,
  }) async {
    monthlyLoads++;
    return {
      'scope_kind': 'inventory',
      'metadata_current': true,
      'months': [
        {'month': '06/2025'},
        {'month': '06/2026'},
      ],
      'job': null,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchDaily({bool request = false}) async {
    dailyLoads++;
    return {
      'scope_kind': 'inventory',
      'metadata_current': true,
      'period_from': '2026-09-19',
      'period_through': '2026-11-02',
      'expected_through': '2026-11-02',
      'days': ['2026-11-02'],
      'job': null,
    };
  }
}

void main() {
  testWidgets(
    'category drawer preserves tracker and report state across navigation',
    (tester) async {
      final reportError = FlutterError.onError!;
      FlutterError.onError = (details) {
        debugPrint(details.toString());
        reportError(details);
      };
      addTearDown(() => FlutterError.onError = reportError);
      tester.view.physicalSize = const Size(1600, 1050);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = _AuthBloc();
      final repository = _TrackerRepository();
      final sales = _SalesSource();
      addTearDown(auth.close);
      addTearDown(sales.client.dispose);
      await tester.pumpWidget(
        BlocProvider<AuthBloc>.value(
          value: auth,
          child: MaterialApp(
            home: CategoryDashboardPage(
              itemsRepository: repository,
              salesReportDataSource: sales,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Initial Category layout');
      expect(CategoryDashboardPage.pages, [
        InventoryPageType.itemsTracker,
        InventoryPageType.salesReport,
      ]);
      expect(find.text('Category Dashboard'), findsOneWidget);
      expect(
        tester.widget<ItemsTrackerPage>(find.byType(ItemsTrackerPage)).role,
        'category',
      );
      expect(repository.loads, 1);
      expect(sales.monthlyLoads, 0, reason: 'Reports load only on first visit');
      for (final title in [
        'Overview',
        'Daily Order',
        'Branch Setting',
        'Stock Check',
        'Availability KPI',
        'Fill Rate KPI',
        'Online Overview',
      ]) {
        expect(find.text(title), findsNothing);
      }
      await tester.enterText(
        find.byType(TextField).first,
        'Keep category filter',
      );
      await tester.pump(const Duration(milliseconds: 600));
      final drawer = find.byType(InventoryDrawer);
      Finder menu(String title) =>
          find.descendant(of: drawer, matching: find.text(title));
      await tester.tap(menu('Sales Report'));
      await tester.pumpAndSettle();
      expect(sales.monthlyLoads, 1);
      expect(sales.dailyLoads, 1);
      expect(tester.takeException(), isNull, reason: 'Opening Sales Report');
      expect(find.text('Download Sales 45 Days'), findsOneWidget);
      await tester.tap(find.text('June'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'Selecting a report month',
      );
      final loadedReports = sales.monthlyLoads;
      await tester.tap(menu('Items Tracker'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Keep category filter',
      );
      expect(repository.loads, 1);
      await tester.tap(menu('Sales Report'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(sales.monthlyLoads, loadedReports);
      await tester.tap(find.byKey(const ValueKey('categoryMenuToggle')));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Collapsing the desktop drawer',
      );
      await tester.tap(find.byKey(const ValueKey('categoryMenuToggle')));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      // A narrower window opens a modal drawer without losing either page.
      tester.view.physicalSize = const Size(800, 1050);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Narrow Category layout');
      await tester.tap(find.byKey(const ValueKey('categoryMenuToggle')));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen,
        isTrue,
      );
      await tester.tap(menu('Items Tracker'));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen,
        isFalse,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Keep category filter',
      );
      expect(repository.loads, 1);
      await tester.tap(find.byKey(const ValueKey('categoryMenuToggle')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Log out'));
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('unsaved changes in Category Dashboard'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
