import 'package:daily_order/core/utils/max_adj_export_rows.dart';
import 'package:daily_order/core/utils/max_adj_search.dart';
import 'package:daily_order/core/utils/max_adjustment_expiry.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/max_adj_data_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

void main() {
  final now = DateTime.utc(2026, 10, 15, 8);
  Map<String, dynamic> row({
    String type = 'INCREASE',
    String? update = '2026-10-01',
    String? end,
    String? source = 'inventory',
    String branch = 'Al Ain',
  }) => {
    'branch_name': branch,
    'item_code': '123',
    'item_name': 'Sample item',
    'adjustment_type': type,
    'current_demand_30d': 1,
    'max_adjustment_30d': 3,
    'qty': 3,
    'update_date': update,
    'end_date': end,
    'added_by': source,
  };

  setUp(
    () => StoreBranchIdentityRegistry.groups.value = const {
      'AL AIN': '71',
      'CITY': 'APG',
    },
  );
  tearDown(() => StoreBranchIdentityRegistry.groups.value = const {});

  test('defaults to 30/45 calendar days from update_date for every source', () {
    for (final source in ['branch', 'inventory', 'system', null]) {
      final increase = MaxAdjustmentExpiry(row(source: source), now: now);
      expect(increase.daysRemaining, 16);
      expect(increase.dateLabel, '2026-10-31');
      final decrease = MaxAdjustmentExpiry(
        row(source: source, type: 'DECREASE'),
        now: now,
      );
      expect(decrease.daysRemaining, 31);
      expect(decrease.dateLabel, '2026-11-15');
    }
  });

  test('matches live server samples, including ignored branch end_date', () {
    final samples = [
      (
        row(
          type: 'DECREASE',
          source: 'branch',
          update: '2026-10-15',
          end: '2026-10-31',
        ),
        45,
      ),
      (row(type: 'DECREASE', source: 'branch', update: '2026-10-15'), 45),
      (row(type: 'DECREASE', update: '2026-10-08'), 38),
      (row(source: 'branch', update: '2026-10-14'), 29),
      (row(update: '2026-10-15', end: '2026-11-17'), 33),
      (row(update: '2026-11-03'), 49),
    ];
    for (final (data, expected) in samples) {
      expect(MaxAdjustmentExpiry(data, now: now).daysRemaining, expected);
    }
    final branch = MaxAdjustmentExpiry(samples.first.$1, now: now);
    expect(branch.hasIgnoredEndDate, isTrue);
    expect(branch.usesEndDate, isFalse);
    expect(branch.tooltip, contains('server ignores end_date'));
  });

  test(
    'explicit admin deadline overrides default, even without update_date',
    () {
      for (final type in ['INCREASE', 'DECREASE']) {
        final result = MaxAdjustmentExpiry(
          row(type: type, update: null, end: '2027-01-01'),
          now: now,
        );
        expect(result.usesEndDate, isTrue);
        expect(result.dateLabel, '2027-01-01');
        expect(result.daysRemaining, 78);
      }
    },
  );

  test(
    'Dubai midnight changes one calendar day without truncating partial days',
    () {
      final data = row(end: '2026-10-16');
      final before = MaxAdjustmentExpiry(
        data,
        now: DateTime.utc(2026, 10, 15, 19, 59),
      );
      final at = MaxAdjustmentExpiry(data, now: DateTime.utc(2026, 10, 15, 20));
      final after = MaxAdjustmentExpiry(
        data,
        now: DateTime.utc(2026, 10, 16, 20),
      );
      expect(before.daysRemaining, 1);
      expect(before.label, '1 day left');
      expect(at.daysRemaining, 0);
      expect(at.label, 'Ends today');
      expect(after.daysRemaining, -1);
      expect(after.label, 'Expired 1 day ago');
    },
  );

  test('bad dates and unknown types never invent a deadline', () {
    for (final date in [null, '', 'not a date', '2026-02-30']) {
      expect(
        MaxAdjustmentExpiry(row(update: date), now: now).daysRemaining,
        isNull,
      );
    }
    expect(
      MaxAdjustmentExpiry(row(end: 'bad'), now: now).label,
      'Unknown expiry',
    );
    expect(MaxAdjustmentExpiry(row(type: 'OTHER'), now: now).deadline, isNull);
    expect(
      MaxAdjustmentExpiry(row(update: '01/10/2026'), now: now).daysRemaining,
      16,
    );
    expect(
      MaxAdjustmentExpiry(
        row(update: '2026-10-01T00:00:00Z'),
        now: now,
      ).daysRemaining,
      16,
    );
  });

  test(
    'export decorates only group 71; days are numeric and raw rows survive',
    () {
      final original = row();
      final rows = maxAdjExportRows([
        original,
        row(branch: 'City', type: 'DECREASE'),
        {...row(), 'moved_at': '2026-10-10', 'action_type': 'system_move'},
      ], now: now);
      expect(rows[0]['branch_name'], '71 Al Ain');
      expect(rows[1]['branch_name'], 'City');
      expect(rows[0]['remaining_days'], 16);
      expect(rows[1]['remaining_days'], 31);
      expect(rows[0]['expiry_date'], '2026-10-31');
      expect(rows[2]['remaining_days'], 'Historical record');
      expect(original['branch_name'], 'Al Ain');
      expect(original.containsKey('remaining_days'), isFalse);
    },
  );

  test('search accepts displayed 71 labels without including other groups', () {
    final filter = maxAdjSearchFilter('71 Al');
    expect(filter, contains('branch_name.ilike."AL AIN"'));
    expect(filter, isNot(contains('branch_name.ilike."CITY"')));
    expect(maxAdjSearchFilter('71'), contains('branch_name.ilike."AL AIN"'));
    expect(
      maxAdjSearchFilter('Al Ain'),
      contains('branch_name.ilike."%Al Ain%"'),
    );
    expect(maxAdjSearchFilter('a,b(c)'), contains('reason.ilike."%a,b(c)%"'));
  });

  testWidgets(
    'grid sorts and filters numeric days; history retains raw branch',
    (tester) async {
      tester.view.physicalSize = const Size(1800, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? selected;
      final source = MaxAdjDataSource(
        data: [
          row(end: '2026-11-14'),
          row(branch: 'City', end: '2026-10-17'),
        ],
        now: now,
        onHistory: (data) => selected = data,
      );
      addTearDown(source.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SfDataGrid(
              source: source,
              allowSorting: true,
              allowFiltering: true,
              columns: [
                for (final cell in source.rows.first.getCells())
                  GridColumn(
                    columnName: cell.columnName,
                    width: cell.columnName == 'remaining_days' ? 160 : 110,
                    label: Text(cell.columnName),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('30 days left'), findsOneWidget);
      expect(find.text('2 days left'), findsOneWidget);
      expect(find.text('71 Al Ain'), findsOneWidget);
      expect(find.text('City'), findsOneWidget);
      source.sortedColumns.add(
        const SortColumnDetails(
          name: 'remaining_days',
          sortDirection: DataGridSortDirection.ascending,
        ),
      );
      await source.sort();
      await tester.pumpAndSettle();
      expect(
        source.effectiveRows.first
            .getCells()
            .singleWhere((c) => c.columnName == 'remaining_days')
            .value,
        2,
      );
      source.addFilter(
        'remaining_days',
        FilterCondition(type: FilterType.greaterThan, value: 7),
      );
      await tester.pumpAndSettle();
      expect(source.effectiveRows.length, 1);
      expect(find.text('2 days left'), findsNothing);
      await tester.tap(find.byTooltip('View adjustment history'));
      expect(selected?['branch_name'], 'Al Ain');
      expect(tester.takeException(), isNull);
    },
  );
}
