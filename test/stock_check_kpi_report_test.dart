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
  test(
    'latest correction earns full marks while retaining the full history',
    () {
      final result = report([
        item(1, 'A', 10),
        item(2, 'A', 12),
        item(3, 'A', 10),
        item(4, 'A', 10),
      ]);
      expect(result.total, 1);
      expect(result.scored, 1);
      expect(result.correct, 1);
      expect(result.accuracy, 100);
      expect(
        result.items.single.result,
        equals('Incorrect in Q2, corrected in Q3'),
      );
      expect(result.projects.map((p) => p.id), ['q1', 'q2', 'q3', 'q4']);
      expect(result.items.single.differenceChange('q2', result.projects), 2);
      expect(result.items.single.differenceChange('q3', result.projects), -2);
      expect(result.items.single.comparisonDifference, 2);
    },
  );
  test('equal nonzero differences earn full marks', () {
    for (var quarters = 2; quarters <= 4; quarters++) {
      for (final diff in [-2, 2]) {
        final result = report([
          for (var q = 1; q <= quarters; q++) item(q, 'A', 10 + diff),
        ], quarters: quarters);
        expect(result.items.single.score, 100);
        expect(result.items.single.comparisonDifference, 0);
      }
    }
    expect(report([item(1, 'A', 12)], quarters: 1).items.single.score, 0);
  });
  test('union includes shared and single-project products exactly once', () {
    final result = report([
      for (var q = 1; q <= 4; q++) item(q, 'A', 10),
      item(1, 'B', 10), item(2, 'C', 9), item(3, 'D', 10), item(4, 'E', 10),
      // Partial overlap is excluded because the product is absent from Q4.
      item(1, 'F', 10), item(3, 'F', 10),
    ]);
    expect(result.total, 6);
    expect(result.shared, 2);
    expect(result.standalone, 4);
    expect(result.correct, 2);
    expect(result.scored, 2);
    expect(result.excluded, 4);
    expect(result.accuracy, 100);
    expect(result.items.singleWhere((i) => i.code == 'F').score, isNull);
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
      ], quarters: 2);
      expect(result.total, 5);
      expect(result.awaiting, 2);
      expect(result.excluded, 3);
      expect(result.scored, 0);
      expect(result.accuracy, isNull);
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
      item(2, 'B', 10, branch: 'BRANCH A'),
      item(2, 'A', 12, branch: 'Branch B'),
    ], quarters: 2);
    expect(result.total, 3);
    expect(result.branches.length, 2);
    expect(result.branches.values.first.total, 2);
    expect(result.branches.values.first.accuracy, 100);
    expect(result.branches.values.last.accuracy, 0);
    expect(result.accuracy, closeTo(200 / 3, 1e-9));
  });
  test(
    'only selected projects count and tiny decimal differences become zero',
    () {
      final result = report([
        item(1, 'A', 10.005),
        item(4, 'A', 10),
        item(4, 'B', 10),
      ], quarters: 1);
      expect(result.total, 1);
      expect(result.items.single.projectCount, 1);
      expect(result.items.single.score, 100);
    },
  );
  test('no completed products means no accuracy yet', () {
    final result = report([item(1, 'A', null)], quarters: 1);
    expect(result.accuracy, isNull);
    expect(result.items.single.score, isNull);
  });

  test(
    'inclusive 0.01 threshold handles both signs without truncating material fractions',
    () {
      for (final diff in [-0.01, -0.001, 0, 0.001, 0.01]) {
        final product = report([
          item(1, 'A', 1 + diff, system: 1),
        ], quarters: 1).items.single;
        expect(product.differenceFor('q1'), 0);
        expect(product.comparisonDifference, 0);
        expect(product.score, 100);
      }
      for (final diff in [-0.0101, 0.0101, 0.5]) {
        final product = report([
          item(1, 'A', 1 + diff, system: 1),
        ], quarters: 1).items.single;
        expect(product.score, 0);
        expect(product.differenceFor('q1'), closeTo(diff, 1e-9));
      }
    },
  );

  test(
    'quarter changes use the same tolerance and preserve original quantities',
    () {
      final result = report([
        item(1, 'A', 11),
        item(2, 'A', 11.01),
        item(1, 'B', 9),
        item(2, 'B', 8.99),
        item(1, 'C', 11),
        item(2, 'C', 11.0101),
      ], quarters: 2);
      for (final code in ['A', 'B']) {
        final product = result.items.singleWhere((i) => i.code == code);
        expect(product.score, 100);
        expect(product.comparisonDifference, 0);
        expect(product.differenceChange('q2', result.projects), 0);
      }
      expect(result.items.singleWhere((i) => i.code == 'C').score, 0);
      expect(result.items.first.rowFor('q2')!.actualQty, 11.01);
    },
  );

  test(
    'latest zero stock has blank accuracy and never enters numerator or denominator',
    () {
      final result = report([
        item(1, 'ZERO', 12),
        item(2, 'ZERO', 0.009, system: 0.01),
        item(1, 'OLD', 0, system: 0),
        item(2, 'OLD', 9),
        item(2, 'FAIL', 8),
        item(2, 'OK', 10),
      ], quarters: 2);
      final zero = result.items.singleWhere((i) => i.code == 'ZERO');
      expect(zero.score, isNull);
      expect(zero.accurate, isFalse);
      expect(zero.zeroStockLatest, isTrue);
      expect(zero.scorable, isFalse);
      expect(zero.result, equals('Zero stock in Q2'));
      expect(result.total, 4);
      expect(result.scored, 3);
      expect(result.correct, 1);
      expect(result.excluded, 1);
      expect(result.awaiting, 0);
      expect(result.accuracy, closeTo(100 / 3, 1e-9));
      expect(result.items.singleWhere((i) => i.code == 'OLD').score, 0);
    },
  );

  test(
    'latest zero stock overrides correct, incorrect or absent earlier quarters',
    () {
      for (var quarters = 1; quarters <= 4; quarters++) {
        for (final quantity in [-0.01, 0, 0.001, 0.01]) {
          final result = report([
            for (var q = 1; q < quarters; q++) ...[
              item(q, 'CORRECT', 2, system: 2),
              item(q, 'INCORRECT', q.isEven ? 9 : 12),
            ],
            for (final code in ['CORRECT', 'INCORRECT', 'LATEST_ONLY'])
              item(quarters, code, quantity, system: -quantity),
            item(quarters, 'OK', 10),
            item(quarters, 'FAIL', 12),
          ], quarters: quarters);
          for (final code in ['CORRECT', 'INCORRECT', 'LATEST_ONLY']) {
            final product = result.items.singleWhere((i) => i.code == code);
            expect(product.score, isNull);
            expect(product.accurate, isFalse);
            expect(product.excluded, isTrue);
            expect(product.scorable, isFalse);
            expect(product.result, 'Zero stock in Q$quarters');
          }
          expect(result.scored, 2);
          expect(result.correct, 1);
          expect(result.failed, 1);
          expect(result.excluded, 3);
          expect(result.awaiting, 0);
          expect(result.accuracy, 50);
          expect(
            result.items.where((i) => i.score == 100).length,
            result.correct,
          );
          expect(result.items.where((i) => i.score == 0).length, result.failed);
        }
      }
    },
  );

  test('1, 1, 0 and a tiny latest difference earn 100 and remain scored', () {
    for (final latest in [10, 10.005]) {
      final result = report([
        item(1, 'A', 11),
        item(2, 'A', 11),
        item(3, 'A', latest),
      ], quarters: 3);
      expect(result.items.single.score, 100);
      expect(result.excluded, 0);
      expect(result.scored, 1);
    }
  });

  test(
    'absent latest products are excluded and gaps use included projects only',
    () {
      final result = report([
        item(1, 'MISSING', 8),
        item(1, 'SHARED', 11),
        item(3, 'SHARED', 11),
        item(3, 'NEW', 9),
      ], quarters: 3);
      final missing = result.items.singleWhere((i) => i.code == 'MISSING');
      expect(missing.score, isNull);
      expect(missing.result, equals('Not present in Q3'));
      expect(result.scored, 2);
      expect(result.correct, 1);
      expect(result.excluded, 1);
      expect(result.awaiting, 0);
      expect(result.accuracy, 50);
      final shared = result.items.singleWhere((i) => i.code == 'SHARED');
      expect(shared.score, 100);
      expect(shared.result, equals('Unchanged variance across quarters'));
    },
  );

  test(
    'result contains only the latest meaningful transition without quantities',
    () {
      final result = report([
        item(4, 'A', 9),
        item(2, 'A', 12),
        item(1, 'A', 10),
        item(3, 'A', 11),
      ]);
      final product = result.items.single;
      expect(product.score, 0);
      expect(product.result, 'Variance changed direction in Q4');
      expect(product.differenceChange('q2', result.projects), 2);
      expect(product.differenceChange('q4', result.projects), -2);
    },
  );

  test('equal endpoints cannot hide a changed middle if latest is nonzero', () {
    final result = report([
      item(1, 'A', 11),
      item(2, 'A', 12),
      item(3, 'A', 11),
    ], quarters: 3);
    expect(result.items.single.score, 0);
    expect(result.items.single.result, 'Variance decreased in Q3');
  });

  test('all zero-stock exclusions have no denominator or awaiting counts', () {
    final result = report([item(1, 'A', 0, system: 0)], quarters: 1);
    expect(result.accuracy, isNull);
    expect(result.items.single.score, isNull);
    expect(result.awaiting, 0);
    expect(result.scored, 0);
  });

  test(
    'all-zero stock including tiny fractions has blank accuracy and one short result',
    () {
      for (var quarters = 1; quarters <= 4; quarters++) {
        final result = report([
          for (var q = 1; q <= quarters; q++)
            item(q, 'ZERO', q.isEven ? -.01 : .001, system: q.isEven ? .01 : 0),
          item(quarters, 'OK', 10),
        ], quarters: quarters);
        final zero = result.items.singleWhere((i) => i.code == 'ZERO');
        expect(zero.allZeroStock, isTrue);
        expect(zero.score, isNull);
        expect(zero.accurate, isFalse);
        expect(
          zero.result,
          quarters == 1
              ? 'Zero stock in Q1'
              : quarters == 2
              ? 'Zero stock in both quarters'
              : 'Zero stock in all quarters',
        );
        expect(result.scored, 1);
        expect(result.correct, 1);
        expect(result.excluded, 1);
        expect(result.awaiting, 0);
      }
    },
  );

  test(
    'short categories cover changes and remain stable across product quantities',
    () {
      StockCheckKpiItem pair(num first, num second) => report([
        item(1, 'A', 10 + first),
        item(2, 'A', 10 + second),
      ], quarters: 2).items.single;
      expect(pair(0, 3).result, 'Correct in Q1, incorrect in Q2');
      expect(pair(4, 0).result, 'Incorrect in Q1, corrected in Q2');
      expect(pair(1, 2).result, 'Variance increased in Q2');
      expect(pair(-1, -3).result, 'Variance increased in Q2');
      expect(pair(3, 1).result, 'Variance decreased in Q2');
      expect(pair(-3, -1).result, 'Variance decreased in Q2');
      expect(pair(1, -1).result, 'Variance changed direction in Q2');
      expect(pair(2, 2.005).result, 'Unchanged variance across quarters');
      expect(pair(0, .005).result, 'Correct in all quarters');
    },
  );

  test('invalid or duplicate latest zero quantities still require review', () {
    final result = report([
      item(2, 'D', 0, system: 0),
      item(2, 'D', 0, system: 0),
      item(2, 'F', double.infinity, system: 0),
      item(2, 'N', double.nan, system: 0),
      item(2, 'P', 0, system: 0, status: 'pending'),
    ], quarters: 2);
    expect(result.scored, 0);
    expect(result.excluded, 0);
    expect(result.awaiting, 4);
    expect(result.items.every((i) => i.score == null), isTrue);
  });
}
