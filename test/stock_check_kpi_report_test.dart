import 'package:daily_order/domain/entities/stock_check_campaign.dart';
import 'package:daily_order/domain/entities/stock_check_kpi_report.dart';
import 'package:daily_order/domain/entities/stock_check_task.dart';
import 'package:flutter_test/flutter_test.dart';

StockCheckCampaign project(int quarter) => StockCheckCampaign({
  'batch_id': 'q$quarter', 'title': 'Quarter $quarter',
  'check_kind': 'kpi', 'kpi_year': 2026, 'kpi_quarter': quarter,
  // Creation order deliberately differs from quarter order.
  'sent_at': '2026-01-0${5 - quarter}T00:00:00Z',
});

StockCheckTask item(
  int quarter,
  String code,
  num? actual, {
  String branch = 'Branch A',
  String status = 'submitted',
  num? system = 10,
}) => StockCheckTask.fromMap({
  'id': '$quarter-$branch-$code',
  'batch_id': 'q$quarter',
  'branch_name': branch,
  'item_code': code,
  'item_name': 'Product $code',
  'system_qty': system,
  'actual_qty': actual,
  'status': status,
});

StockCheckKpiReport report(List<StockCheckTask> rows, {int quarters = 4}) =>
    StockCheckKpiReport(
      projects: [for (var q = quarters; q > 0; q--) project(q)],
      rows: rows,
    );

void main() {
  test(
    'three quarters compare the full range including negative differences',
    () {
      final result = report([
        item(1, 'A', 8),
        item(2, 'A', 13),
        item(3, 'A', 9),
      ], quarters: 3);
      expect(result.items.single.comparisonDifference, 5);
      expect(result.items.single.score, 0);
    },
  );
  test('an unloaded project cannot be mistaken for a missing product', () {
    final result = StockCheckKpiReport(
      projects: [
        project(1),
        StockCheckCampaign({'batch_id': 'q2', 'title': 'Q2', 'total': 1}),
      ],
      rows: [item(1, 'A', 10)],
    );
    expect(result.incompleteProjectIds, ['q2']);
    expect(result.accuracy, isNull);
    expect(result.items, isEmpty);
  });
  test('a nonzero middle quarter fails even when first and last are zero', () {
    final result = report([
      item(1, 'A', 10),
      item(2, 'A', 12),
      item(3, 'A', 10),
      item(4, 'A', 10),
    ]);
    expect(result.total, 1);
    expect(result.scored, 1);
    expect(result.correct, 0);
    expect(result.accuracy, 0);
    expect(result.projects.map((p) => p.id), ['q1', 'q2', 'q3', 'q4']);
    expect(result.items.single.differenceChange('q2', result.projects), 2);
    expect(result.items.single.differenceChange('q3', result.projects), -2);
    expect(result.items.single.comparisonDifference, 2);
  });
  test('equal nonzero differences never earn full marks', () {
    final result = report([item(1, 'A', 12), item(2, 'A', 12)], quarters: 2);
    expect(result.items.single.score, 0);
    expect(result.items.single.comparisonDifference, 0);
  });
  test('union includes shared and single-project products exactly once', () {
    final result = report([
      for (var q = 1; q <= 4; q++) item(q, 'A', 10),
      item(1, 'B', 10), item(2, 'C', 9), item(3, 'D', 10), item(4, 'E', 10),
      // Partial overlap is scored across just the projects containing it.
      item(1, 'F', 10), item(3, 'F', 10),
    ]);
    expect(result.total, 6);
    expect(result.shared, 2);
    expect(result.standalone, 4);
    expect(result.correct, 5);
    expect(result.accuracy, closeTo(500 / 6, 1e-9));
    expect(result.items.singleWhere((i) => i.code == 'F').score, 100);
    expect(
      result.items.singleWhere((i) => i.code == 'C').comparisonDifference,
      -1,
    );
    expect(result.items.singleWhere((i) => i.code == 'F').rowFor('q2'), isNull);
  });
  test(
    'pending, null quantities and duplicates require review and are not zero',
    () {
      final result = report([
        item(1, 'P', 10),
        item(2, 'P', 10, status: 'pending'),
        item(1, 'N', null),
        item(1, 'S', 10, system: null),
        item(1, 'D', 10),
        item(1, 'D', 10),
        item(2, 'D', 10),
        item(1, 'OK', 0, system: 0),
      ]);
      expect(result.total, 5);
      expect(result.awaiting, 4);
      expect(result.scored, 1);
      expect(result.accuracy, 100);
      expect(
        result.items.singleWhere((i) => i.code == 'D').hasDuplicates,
        isTrue,
      );
      expect(
        result.items.singleWhere((i) => i.code == 'D').comparisonDifference,
        isNull,
      );
      expect(
        result.items.singleWhere((i) => i.code == 'P').comparisonDifference,
        isNull,
      );
    },
  );
  test('branch and item identity is normalized without mixing branches', () {
    final result = report([
      item(1, ' A ', 10, branch: ' Branch A '),
      item(2, 'a', 10, branch: 'branch a'),
      item(1, 'B', 10, branch: 'BRANCH A'),
      item(1, 'A', 12, branch: 'Branch B'),
    ]);
    expect(result.total, 3);
    expect(result.branches.length, 2);
    expect(result.branches.values.first.total, 2);
    expect(result.branches.values.first.accuracy, 100);
    expect(result.branches.values.last.accuracy, 0);
    expect(result.accuracy, closeTo(200 / 3, 1e-9));
  });
  test('only selected projects count and nonzero decimals fail', () {
    final result = report([
      item(1, 'A', 10.005),
      item(4, 'A', 10),
      item(4, 'B', 10),
    ], quarters: 1);
    expect(result.total, 1);
    expect(result.items.single.projectCount, 1);
    expect(result.items.single.score, 0);
  });
  test('no completed products means no accuracy yet', () {
    final result = report([item(1, 'A', null)]);
    expect(result.accuracy, isNull);
    expect(result.items.single.score, isNull);
  });
}
