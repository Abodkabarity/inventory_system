import 'package:daily_order/domain/entities/online_branch_availability.dart';
import 'package:daily_order/domain/entities/online_overview.dart';
import 'package:flutter_test/flutter_test.dart';

const _branches = [
  OnlineBranch('Web Shop', '71'),
  OnlineBranch('Online Two', 'APG'),
];

Map<String, dynamic> _data() => {
  'generation': 'test-generation',
  'stock_day': '2026-11-17',
  'rows': [
    for (final branch in _branches)
      for (final rank in ['a', 'b', 'c'])
        {
          'branch_name': branch.name,
          'rank': rank,
          'total': rank == 'a'
              ? 1000
              : rank == 'b'
              ? 100
              : 0,
          'available': rank == 'a'
              ? 800
              : rank == 'b'
              ? 50
              : 0,
          'unknown': rank == 'a' ? 100 : 0,
        },
  ],
};

OnlineAvailabilitySnapshot _parse(Map<String, dynamic> data) =>
    OnlineAvailabilitySnapshot.fromMap(
      data,
      generation: 'test-generation',
      approvedBranches: _branches,
    );

void main() {
  test(
    'availability counts products, keeps missing reports in the denominator and uses only ABC',
    () {
      final result = _parse(_data());
      final a = result.branches.first.ranks[OnlineRank.a]!;
      expect(a.percent, 80);
      expect(a.unknown, 100);
      expect(a.withoutStock, 100);
      expect(result.stockDay, DateTime(2026, 11, 17));
      expect(result.branches.first.ranks.length, 3);
    },
  );
  test('an empty rank has no percentage', () {
    final c = _parse(_data()).branches.first.ranks[OnlineRank.c]!;
    expect(c.percent, isNull);
    expect(c.total, 0);
  });
  test('new stock and rank totals change the percentages', () {
    final data = _data();
    for (final row in data['rows'] as List) {
      if (row['rank'] == 'a') {
        row['total'] = 2000;
        row['available'] = 1200;
      }
    }
    expect(_parse(data).branches.first.ranks[OnlineRank.a]!.percent, 60);
  });
  test('stale generations are rejected', () {
    expect(
      () => _parse(_data()..['generation'] = 'older-generation'),
      throwsStateError,
    );
  });
  test('non-online branches and other ranks are rejected', () {
    for (final edit in [
      {'branch_name': 'Retail outlet'},
      {'rank': 'n'},
    ]) {
      final data = _data();
      (data['rows'] as List).first.addAll(edit);
      expect(() => _parse(data), throwsStateError);
    }
  });
  test('missing and duplicate rows are rejected', () {
    final missing = _data();
    (missing['rows'] as List).removeLast();
    expect(() => _parse(missing), throwsStateError);
    final duplicate = _data();
    (duplicate['rows'] as List).add((duplicate['rows'] as List).first);
    expect(() => _parse(duplicate), throwsStateError);
  });
  test('partial or contradictory totals cannot inflate availability', () {
    for (final edits in [
      {'total': 1001},
      {'available': 950},
      {'available': -1},
      {'unknown': 1.5},
      {'total': double.nan},
    ]) {
      final data = _data();
      (data['rows'] as List).first.addAll(edits);
      expect(() => _parse(data), throwsStateError);
    }
  });
}
