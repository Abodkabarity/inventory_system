import 'dart:convert';
import 'dart:io';
import 'package:daily_order/core/utils/online_overview_export.dart';
import 'package:daily_order/core/utils/stock_excel_report.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/domain/entities/online_overview.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/online_overview_grid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'online_overview_fixtures.dart';

void main() {
  tearDown(() => StoreBranchIdentityRegistry.groups.value = {});
  test(
    'grid reuses exact prepared cells while filtering and replaces changed product facts',
    () {
      final records = List.generate(
        8915,
        (index) => onlinePreparedRow(onlineItem('P$index')),
      );
      final grid = OnlineOverviewGridSource(onOpen: (_) {}, onAudit: (_) {});
      addTearDown(grid.dispose);
      final first = Stopwatch()..start();
      grid.replace(records);
      first.stop();
      final original = grid.rows.first;
      final values = original.getCells().map((c) => c.value).toList();
      final repeat = Stopwatch()..start();
      grid.replace(records);
      repeat.stop();
      expect(identical(grid.rows.first, original), isTrue);
      expect(grid.rows.first.getCells().map((c) => c.value), values);
      grid.replace([records.last]);
      expect(grid.itemFor(grid.rows.single), same(records.last));
      grid.replace(records);
      expect(identical(grid.rows.first, original), isTrue);
      final changed = onlinePreparedRow(onlineItem('P0', retail: 123));
      grid.replace([changed]);
      expect(identical(grid.rows.single, original), isFalse);
      expect(
        grid.rows.single
            .getCells()
            .firstWhere((c) => c.columnName == 'retail')
            .value,
        123,
      );
      final timing = File(
        'outputs/online_overview/actual_sales_trial/grid_performance.json',
      );
      timing.parent.createSync(recursive: true);
      timing.writeAsStringSync(
        jsonEncode({
          'rows': records.length,
          'first_build_ms': first.elapsedMilliseconds,
          'repeat_filter_ms': repeat.elapsedMilliseconds,
        }),
      );
    },
  );
  test(
    'recorded sales keep their own numbers and are not exported as a forecast',
    () {
      const facts = {
        'actual_qty': 24,
        'actual_value': 240,
        'qty_score': 24,
        'value_score': 240,
        'selling_branches': 10,
        'selling_months': 6,
        'routes': ['wide_branch_sales'],
        'sales_from': '2026-05-01',
        'sales_through': '2026-10-31',
      };
      final item = onlineItem(
        'FAST',
        extra: {
          'test_actual_sales': facts,
          'test_actual_reason': 'Sold in 10 of 14 online branches.',
        },
      );
      final row = onlinePreparedRow(item, networkBranches: 14);
      expect(row.usesActualSales, isTrue);
      expect(row.hasSalesForecast, isFalse);
      expect(onlinePlainReason(row), 'Sold in 10 of 14 online branches.');
      expect(onlinePriorityLabel(row), 'A · Sales in many branches');
      final exported = onlineOverviewExportRows(
        [row],
        snapshot: onlineSnapshot(),
        scope: OnlineSalesScope.onlineOnly,
      ).single;
      expect(exported['online_qty_last_6_full_months'], 24);
      expect(
        exported['online_value_last_6_full_months_at_current_retail'],
        240,
      );
      expect(exported['forecast_qty'], isNull);
      expect(exported['a_rules_met'], 'wide_branch_sales');
    },
  );
  test('prepared ranking preserves ABCNMTS and a stock review state', () {
    expect(OnlineRank.values.map((r) => r.label), [
      'A',
      'B',
      'C',
      'N',
      'M',
      'T',
      'S',
      'Review',
    ]);
    for (final rank in OnlineRank.values) {
      final row = onlinePreparedRow(
        onlineItem('P'),
        extra: {'rank': rank.name},
      );
      expect(row.rank, rank);
    }
  });
  test(
    'prepared network class is not recalculated from selected branch or price',
    () {
      final item = onlineItem('EXPENSIVE', retail: 99999);
      final row = onlinePreparedRow(
        item,
        branches: ['Web Shop'],
        networkBranches: 15,
        extra: {'rank': 'c'},
      );
      expect(row.rank, OnlineRank.c);
      expect(row.networkBranchCount, 15);
      expect(row.branchNames.length, 1);
      expect(row.hasAbcmt, isTrue);
      final byValue = onlinePreparedRow(
        onlineItem('EXPENSIVE', retail: 950),
        extra: {
          'rank': 'a',
          'classification': {
            ...row.classification,
            'priority_route': 'sales_value',
            'sales_2026': 12,
            'recent_3_qty': 12,
            'estimated_network_sales_value': 11400,
            'thresholds': {...row.classThresholds, 'value_high': 11268},
          },
        },
      );
      expect(onlinePriorityLabel(byValue), 'A · High sales value');
      expect(
        onlinePlainReason(byValue),
        'Estimated online sales: AED 11,400. Top 10% by sales value. '
        'It sold in 3 months and sold recently.',
      );
      final byRepeat = onlinePreparedRow(
        onlineItem('EXPENSIVE', retail: 1000),
        extra: {
          'rank': 'a',
          'classification': {
            ...row.classification,
            'priority_route': 'premium_repeat',
            'selling_periods_last_12': 3,
          },
        },
      );
      expect(onlinePriorityLabel(byRepeat), 'A · Regular sales, high price');
      expect(
        onlinePlainReason(byRepeat),
        'Retail AED 1,000. Sold in 3 of the last 4 three-month periods, '
        'including the most recent.',
      );
      expect(byRepeat.aQualification, 'Regular sales, high price');
    },
  );
  test(
    'other branch stock defaults to zero and stays outside online calculations',
    () {
      for (final value in [null, 'missing', double.nan, double.infinity]) {
        final row = onlinePreparedRow(
          onlineItem('FAST', extra: {'other_branch_stock': value}),
        );
        expect(row.otherBranchStock, 0);
        expect(
          onlineOverviewExportRows(
            [row],
            snapshot: onlineSnapshot(),
            scope: OnlineSalesScope.onlineOnly,
          ).single['other_branch_stock'],
          0,
        );
      }
      final row = onlinePreparedRow(
        onlineItem('FAST', extra: {'other_branch_stock': 120.5}),
      );
      final original = onlinePreparedRow(onlineItem('FAST'));
      expect(row.otherBranchStock, 120.5);
      expect(row.combinedStock, 45);
      expect(row.onlineStock, original.onlineStock);
      expect(row.stockCoverDays, original.stockCoverDays);
      expect(row.rank, original.rank);
      expect(
        onlineOverviewExportRows(
          [row],
          snapshot: onlineSnapshot(),
          scope: OnlineSalesScope.onlineOnly,
        ).single['other_branch_stock'],
        120.5,
      );
    },
  );
  test(
    'six-month export keeps numeric forecasts and formatted plan branches',
    () {
      StoreBranchIdentityRegistry.groups.value = {'WEB SHOP': '71'};
      final row = onlinePreparedRow(
        onlineItem(
          'FAST',
          extra: {
            'test_forecast': {
              'status': 'ready',
              'qty': 42.5,
              'estimated_value': 425,
              'forecast_from': '2026-11-01',
              'forecast_to': '2027-04-30',
              'suggested_branches': ['Web Shop'],
              'model': 'Repeat-sales estimate',
              'product_age': {
                'status': 'new',
                'first_mrn': '2026-09-08',
                'new_until': '2027-03-08',
                'as_of': '2026-10-31',
                'months_since_mrn': 1,
                'months_to_first_sale': 0,
                'age_adjusted': true,
              },
              'reason': 'Expected online sales over 6 months: 42.5 Qty.',
            },
          },
        ),
      );
      final exported = onlineOverviewExportRows(
        [row],
        snapshot: onlineSnapshot(),
        scope: OnlineSalesScope.onlineOnly,
      ).single;
      expect(exported['forecast_horizon_months'], 6);
      expect(exported['forecast_qty'], 42.5);
      expect(exported['forecast_estimated_sales_aed'], 425);
      expect(exported['suggested_online_branches'], '71 Web Shop');
      expect(exported['mrn_product_age'], 'new');
      expect(exported['first_mrn_date'], '2026-09-08');
      expect(exported['new_product_until'], '2027-03-08');
      expect(exported['new_product_age_adjusted'], true);
      expect(
        onlinePlainReason(row),
        'Expected online sales over 6 months: 42.5 Qty.',
      );
    },
  );

  test('partial stock is a reported sum, not a complete network total', () {
    final row = onlinePreparedRow(
      onlineItem('P'),
      branches: ['Web Shop', 'Online Two'],
      extra: {
        'online_stock': null,
        'known_online_stock': 9,
        'reported_branches': 1,
        'stocked_branches': 1,
        'missing_branches': ['Online Two'],
      },
    );
    expect(row.displayedStock, 9);
    expect(row.partialStock, isTrue);
    expect(row.stockCoverage, '1 / 2 branches reported');
    expect(row.availability, 'Stock in 1 of 2 branches · partial reports');
    expect(row.onlineStock, isNull);
    expect(row.stockCoverDays, isNull);
  });

  test('stock cover uses complete online stock and the exact sales period', () {
    final row = onlinePreparedRow(
      onlineItem('P'),
      extra: {'online_stock': 46, 'recent_qty': 184},
    );
    expect(row.stockCoverSalesWindowDays, 92);
    expect(row.stockCoverDays, 23);
    expect(row.stockCoverFor(stock: 2, sales: 46), 4);
    expect(row.stockCoverFor(stock: 0, sales: 46), 0);
    expect(row.stockCoverFor(stock: 2, sales: 0), isNull);
    expect(row.stockCoverFor(stock: -1, sales: 46), isNull);
  });
  test(
    'no positive stock in partial reports cannot establish a full stockout',
    () {
      final row = onlinePreparedRow(
        onlineItem('P'),
        branches: ['Web Shop', 'Online Two'],
        extra: {
          'online_stock': null,
          'known_online_stock': 0,
          'reported_branches': 1,
          'stocked_branches': 0,
        },
      );
      expect(row.availability, 'Stock in 0 of 2 branches · partial reports');
    },
  );
  test(
    'negative balances do not hide a branch with positive physical stock',
    () {
      final row = onlinePreparedRow(
        onlineItem('P'),
        branches: ['Web Shop', 'Online Two'],
        extra: {'known_online_stock': -5, 'stocked_branches': 1},
      );
      expect(row.availability, 'Stock in 1 of 2 branches');
    },
  );
  test('invalid server class or mismatched item identity is rejected', () {
    expect(
      () => onlinePreparedRow(onlineItem('P'), extra: {'rank': 'guess'}),
      throwsStateError,
    );
    expect(
      () => onlinePreparedRow(onlineItem('P'), extra: {'code': 'OTHER'}),
      throwsStateError,
    );
  });
  test('ML suggestions are withheld for N, M, T, S and Review', () {
    for (final code in ['NEW-N', 'SLOW', 'NEW', 'UNTESTED']) {
      final row = onlinePreparedRow(onlineItem(code));
      expect(row.modelPrediction['use'], 'withheld');
      expect(row.modelPrediction['class'], isNull);
    }
    final inHouse = onlinePreparedRow(
      onlineItem('FAST', extra: {'sales_orientation': 'INHOUSE'}),
    );
    expect(inHouse.rank, OnlineRank.s);
    expect(inHouse.modelPrediction['use'], 'withheld');
    expect(
      onlinePlainReason(inHouse),
      'Sales Orientation is INHOUSE. This product is assigned S.',
    );
    final exported = onlineOverviewExportRows(
      [inHouse],
      snapshot: onlineSnapshot(),
      scope: OnlineSalesScope.onlineOnly,
    );
    expect(exported.single['rank'], 'S');
    expect(exported.single['sales_orientation'], 'INHOUSE');
  });
  test(
    'worker export preserves ABCMT, model advisory, numeric values and group 71 labels',
    () {
      StoreBranchIdentityRegistry.groups.value = {
        'WEB SHOP': '71',
        'ONLINE TWO': 'APG',
      };
      final data = onlineSnapshot(
        branches: const [
          OnlineBranch('Web Shop', '71'),
          OnlineBranch('Online Two', 'APG'),
        ],
      );
      final item = onlineItem('EXPENSIVE', retail: 2000);
      final sample = onlinePreparedRow(item, networkBranches: 2);
      final rows = [
        onlinePreparedRow(item, branches: ['Web Shop'], networkBranches: 2),
        onlinePreparedRow(
          item,
          branches: ['Online Two'],
          networkBranches: 2,
          extra: {
            'rank': 'a',
            'classification': {
              ...sample.classification,
              'priority_route': 'concentrated_quantity',
              'priority_branches': ['Web Shop', 'Online Two'],
            },
          },
        ),
      ];
      final exported = onlineOverviewExportRows(
        rows,
        snapshot: data,
        scope: OnlineSalesScope.onlineOnly,
      );
      expect(exported.first['branch_name'], '71 Web Shop');
      expect(exported.last['branch_name'], 'Online Two');
      expect(exported.first['rank'], 'C');
      expect(exported.last['rank'], 'A');
      expect(exported.last['a_qualification'], 'Concentrated demand');
      expect(exported.last['priority_branches'], '71 Web Shop / Online Two');
      expect(exported.first['estimated_retail_value_2026'], 4000);
      expect(exported.first['online_stock_cover_days'], 230);
      expect(exported.first['price_affects_abc'], isFalse);
      expect(exported.first['ml_use'], 'advisory_only');
      expect(exported.first['item_status'], '1#NORMAL PURCHASE');
      expect(exported.first['purchase_status'], 'AVAILABLE');
      final report = StockExcelReport(exported, 'online_overview.xlsx');
      expect(report.sheetName, 'Online Overview');
      final file = File('outputs/online_overview/export_payload.json');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'headers': report.headers,
          'widths': report.widths,
          'types': report.types,
          'keys': report.keys,
          'rows': report.values.toList(),
          'sheetName': report.sheetName,
        }),
      );
    },
  );
}
