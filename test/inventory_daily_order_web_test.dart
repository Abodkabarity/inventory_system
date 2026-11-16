@TestOn('browser')
library;

import 'dart:async';

import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/domain/entities/branch_setting.dart';
import 'package:daily_order/domain/entities/daily_order_query.dart';
import 'package:daily_order/domain/entities/daily_order_row.dart';
import 'package:daily_order/domain/repositories/inventory_repository.dart';
import 'package:daily_order/presentation/inventory_dashboard/bloc/inventory_bloc.dart';
import 'package:daily_order/presentation/inventory_dashboard/bloc/inventory_state.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/inventory_daily_order_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

const _runDate = '2026-11-11';
const _next = (itemCode: '0120', branch: 'Alpha', sortValue: '0120');

DailyOrderRow _row(
  int code,
  String name, {
  String branch = 'Alpha',
  num? recordedMax,
}) => DailyOrderRow.fromMap({
  'branch': branch,
  'item_code': code.toString().padLeft(4, '0'),
  'item_name': name,
  'branch_stock': code,
  'store_stock': 160,
  'max_adjustment_30d': recordedMax,
});

class _Request {
  _Request(this.query, this.after);
  final DailyOrderQuery query;
  final DailyOrderCursor? after;
  final result = Completer<DailyOrderBatch>();
}

class _Repository implements InventoryRepository {
  final requests = <_Request>[];
  final valueRequests =
      <({String column, String lookup, List<String> branches})>[];

  @override
  Future<DailyOrderBatch> fetchDailyOrderBatch(
    DailyOrderQuery query, {
    DailyOrderCursor? after,
  }) {
    final request = _Request(query, after);
    requests.add(request);
    return request.result.future;
  }

  @override
  Future<List<BranchSetting>> fetchBranchSettings() async => [];

  @override
  Future<DailyOrderFilterValues> fetchDailyOrderFilterValues(
    DailyOrderQuery query, {
    required DailyOrderField field,
    required String lookup,
    List<String> lookupBranches = const [],
    String? after,
  }) async {
    valueRequests.add((
      column: field.column,
      lookup: lookup,
      branches: lookupBranches,
    ));
    if (field.column == 'branch') {
      return DailyOrderFilterValues(
        lookup.isEmpty ? ['Alpha', 'Beta'] : ['Alpha'],
        null,
      );
    }
    return const DailyOrderFilterValues(['1', '2', null], null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PageBloc extends Cubit<InventoryState> implements InventoryBloc {
  _PageBloc(this.repo, InventoryState? initial)
    : super(initial ?? InventoryState.initial());

  @override
  final InventoryRepository repo;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_Repository> _openPage(
  WidgetTester tester, {
  Size size = const Size(1450, 820),
  InventoryState? initial,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final repo = _Repository();
  final bloc = _PageBloc(repo, initial);
  addTearDown(bloc.close);
  StoreBranchIdentityRegistry.groups.value = const {};
  addTearDown(() => StoreBranchIdentityRegistry.groups.value = const {});
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider<InventoryBloc>.value(
          value: bloc,
          child: const InventoryDailyOrderPage(runDate: _runDate),
        ),
      ),
    ),
  );
  return repo;
}

void main() {
  testWidgets('Max Adjustment renders only recorded numeric values', (
    tester,
  ) async {
    const columns = ['item_code', 'item_name', 'max_adjustment_30d'];
    final repo = await _openPage(
      tester,
      initial: InventoryState.initial().copyWith(
        visibleColumns: columns,
        columnOrder: columns,
      ),
    );
    repo.requests.single.result.complete(
      DailyOrderBatch([
        _row(1, 'Missing max'),
        _row(2, 'Recorded zero', recordedMax: 0),
        _row(3, 'Recorded quantity', recordedMax: 12),
      ], null),
    );
    await tester.pumpAndSettle();
    final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
    final values = grid.source.rows.map(
      (row) => row
          .getCells()
          .singleWhere((cell) => cell.columnName == 'max_adjustment_30d')
          .value,
    );
    expect(values, [null, 0, 12]);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('the toolbar is compact on desktop and wraps on narrow screens', (
    tester,
  ) async {
    final repo = await _openPage(tester);
    repo.requests.single.result.complete(
      DailyOrderBatch([_row(1, 'Product')], null),
    );
    await tester.pumpAndSettle();

    final search = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText ==
              'Search item name, code, barcode or branch',
    );
    final export = find.byTooltip('Export');
    expect(
      (tester.getCenter(search).dy - tester.getCenter(export).dy).abs(),
      lessThan(4),
    );

    await tester.binding.setSurfaceSize(const Size(390, 740));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(search).dy,
      greaterThan(tester.getBottomLeft(export).dy),
    );
    expect(find.text('Product'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scroll retry uses the same cursor and keeps rendered rows', (
    tester,
  ) async {
    final repo = await _openPage(tester);
    expect(find.text('Loading daily orders…'), findsOneWidget);
    expect(repo.requests.single.query.runDate, _runDate);
    repo.requests.single.result.complete(
      DailyOrderBatch(
        List.generate(120, (index) => _row(index + 1, 'Product ${index + 1}')),
        _next,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('120 rows loaded'), findsOneWidget);
    expect(find.text('Product 1'), findsOneWidget);
    expect(repo.requests, hasLength(1));

    final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
    final scroll = grid.verticalScrollController!;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(repo.requests.last.after, _next);
    expect(find.text('Loading more…'), findsOneWidget);

    repo.requests.last.result.completeError(StateError('Temporary failure'));
    await tester.pumpAndSettle();
    expect(find.text('120 rows loaded'), findsOneWidget);
    expect(find.text('Couldn’t load more orders.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(repo.requests.last.after, _next);

    repo.requests.last.result.complete(
      DailyOrderBatch([
        _row(120, 'Duplicate'),
        _row(121, 'Final result'),
      ], null),
    );
    await tester.pumpAndSettle();
    expect(find.text('121 rows loaded'), findsOneWidget);
    expect(find.text('End of results'), findsOneWidget);
    expect(scroll.offset, greaterThan(0));
  });

  testWidgets('search debounce, Enter, stale requests and branch aliases', (
    tester,
  ) async {
    final repo = await _openPage(tester);
    repo.requests.single.result.complete(
      DailyOrderBatch([
        _row(1, 'First item'),
        _row(2, 'Other group item', branch: 'Beta'),
      ], null),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);

    StoreBranchIdentityRegistry.groups.value = const {
      'ALPHA': '71',
      'BETA': '12',
    };
    await tester.pumpAndSettle();
    expect(find.text('71 Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    final search = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText ==
              'Search item name, code, barcode or branch',
    );
    await tester.enterText(search, 'first');
    await tester.pump(const Duration(milliseconds: 279));
    expect(repo.requests, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    final older = repo.requests.last;
    expect(older.query.search, 'first');

    await tester.enterText(search, '71 Alpha');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    final latest = repo.requests.last;
    expect(latest.query.search, '71 Alpha');
    expect(latest.query.displayedBranchMatches, ['ALPHA']);
    latest.result.complete(DailyOrderBatch([_row(5, 'Matching branch')], null));
    await tester.pumpAndSettle();
    older.result.complete(DailyOrderBatch([_row(1, 'Old result')], null));
    await tester.pumpAndSettle();
    expect(find.text('Matching branch'), findsOneWidget);
    expect(find.text('Old result'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(repo.requests.last.query.search, isEmpty);
    repo.requests.last.result.complete(const DailyOrderBatch([], null));
    await tester.pumpAndSettle();
    expect(find.text('No orders for this date'), findsOneWidget);
  });

  testWidgets('Excel branch filter searches labels and applies raw values', (
    tester,
  ) async {
    final repo = await _openPage(tester);
    StoreBranchIdentityRegistry.groups.value = const {
      'ALPHA': '71',
      'BETA': '12',
    };
    repo.requests.single.result.complete(
      DailyOrderBatch([_row(1, 'First item', branch: 'Beta')], null),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Filter BRANCH'));
    await tester.pumpAndSettle();
    expect(repo.valueRequests.single.column, 'branch');
    expect(find.widgetWithText(CheckboxListTile, '71 Alpha'), findsOneWidget);

    await tester.tap(find.text('Select all'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Search values'),
      '71 Alpha',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(repo.valueRequests.last.branches, ['ALPHA']);
    await tester.tap(find.widgetWithText(CheckboxListTile, '71 Alpha'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pump();
    final filter = repo.requests.last.query.filters['branch']!;
    expect(filter.excludeValues, isFalse);
    expect(filter.values, {'Alpha'});
    repo.requests.last.result.complete(
      DailyOrderBatch([_row(2, 'New branch result')], null),
    );
    await tester.pumpAndSettle();
    expect(find.text('New branch result'), findsOneWidget);
  });

  testWidgets('column filter and sort requery the server on a compact layout', (
    tester,
  ) async {
    final repo = await _openPage(tester, size: const Size(820, 800));
    repo.requests.single.result.complete(
      DailyOrderBatch([_row(1, 'Product')], null),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final grid = tester.widget<SfDataGrid>(find.byType(SfDataGrid));
    final controller = grid.columns.firstWhere(
      (column) => column.columnName == 'branch_stock',
    );
    await tester.tap(find.byWidget(controller.label).hitTestable());
    await tester.pump();
    expect(repo.requests.last.query.sort, 'branch_stock');
    repo.requests.last.result.complete(
      DailyOrderBatch([_row(2, 'Sorted product')], null),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Filter BRANCH STOCK'));
    await tester.pumpAndSettle();
    expect(find.text('(Blanks)'), findsOneWidget);
    await tester.tap(find.text('Number filters'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Value'), '2');
    await tester.tap(find.text('Apply').hitTestable());
    await tester.pump();
    expect(
      repo.requests.last.query.filters['branch_stock']?.rules.single.value,
      '2',
    );
    repo.requests.last.result.complete(const DailyOrderBatch([], null));
    await tester.pumpAndSettle();
    expect(find.text('No matching orders'), findsOneWidget);
  });
}
