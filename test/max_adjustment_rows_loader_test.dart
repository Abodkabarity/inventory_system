import 'package:daily_order/core/utils/max_adjustment_rows_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads all 8627 records across API batches without UI pages', () async {
    final calls = <int>[];
    final rows = await loadMaxAdjustmentRows(
      fetchRange: (from, to) async {
        calls.add(from);
        return {
          'total': 8627,
          'rows': [
            for (var i = from; i <= to && i < 8627; i++) {'id': i},
          ],
        };
      },
    );
    expect(rows!.length, 8627);
    expect(rows.first['id'], 0);
    expect(rows.last['id'], 8626);
    expect(rows.map((r) => r['id']).toSet().length, 8627);
    expect(calls.length, 18);
  });

  test('continues when API caps each batch below requested range', () async {
    final rows = await loadMaxAdjustmentRows(
      fetchRange: (from, to) async => {
        'total': 1200,
        'rows': [
          for (var i = from; i < from + 200 && i < 1200; i++) {'id': i},
        ],
      },
    );
    expect(rows!.length, 1200);
    expect(rows.last['id'], 1199);
  });

  test('returns empty complete search results', () async {
    expect(
      await loadMaxAdjustmentRows(
        fetchRange: (_, _) async => {'total': 0, 'rows': []},
      ),
      isEmpty,
    );
  });

  test(
    'abandons obsolete searches without publishing partial results',
    () async {
      var cancelled = false;
      var calls = 0;
      final rows = await loadMaxAdjustmentRows(
        fetchRange: (_, _) async {
          calls++;
          cancelled = true;
          return {
            'total': 8627,
            'rows': [
              {'id': 1},
            ],
          };
        },
        isCancelled: () => cancelled,
      );
      expect(rows, isNull);
      expect(calls, 1);
    },
  );

  test('never treats an incomplete API response as a complete table', () async {
    await expectLater(
      loadMaxAdjustmentRows(
        fetchRange: (_, _) async => {'total': 10, 'rows': []},
      ),
      throwsStateError,
    );
  });
}
