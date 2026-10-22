import 'package:flutter_test/flutter_test.dart';
import 'package:daily_order/domain/entities/mismatch_stock_journey.dart';

void main() {
  Map<String, dynamic> movement(String date, String qty, String type) => {
    'trans_date': date,
    'qty': qty,
    'trans_type': type,
  };
  final analysis = <String, dynamic>{
    'event_at': '2026-09-26T16:50:00',
    'last_receipt': '2026-09-07',
    'coverage_through': '2026-10-21',
    'issues': [],
  };
  MismatchStockJourney journey(
    List<Map<String, dynamic>> rows, [
    Map<String, dynamic>? override,
  ]) => MismatchStockJourney({...analysis, ...?override}, {'movements': rows});

  test(
    'old adjustments remain visible and corrections are separate from IN/OUT',
    () {
      final j = journey([
        movement('2026-03-01', '-2', ' INVAdjustment '),
        movement('2026-09-07', '2', 'ReturnPOS'),
        movement('2026-09-10', '-1.5', 'POSDVN'),
        movement('2026-09-12', '1', 'INVAdjustment'),
        movement('2026-09-30', '-9', 'INVAdjustment'),
      ]);
      expect(j.adjustments.length, 2);
      expect(j.adjustmentTiming(j.adjustments.first), 'Before latest incoming');
      expect(j.adjustmentTiming(j.adjustments.last), 'After latest incoming');
      expect(j.laterIn, 0);
      expect(j.laterOut, 1.5);
      expect(j.laterAdjustments, 1);
      expect(j.noLaterMovementEstablished, false);
    },
  );
  test('no movement assertion needs complete coverage and known receipt', () {
    final receipt = movement('2026-09-07', '2', 'StockTransferTo');
    expect(journey([receipt]).noLaterMovementEstablished, true);
    expect(
      journey(
        [receipt],
        {'coverage_through': '2026-09-10'},
      ).noLaterMovementEstablished,
      false,
    );
    expect(
      journey(
        [receipt],
        {
          'issues': ['incomplete_coverage'],
        },
      ).noLaterMovementEstablished,
      false,
    );
    expect(
      journey([], {'last_receipt': null}).noLaterMovementEstablished,
      false,
    );
  });
  test('same-day movements have unknown order and are not later movements', () {
    final j = journey([
      movement('2026-09-07', '2', 'StockTransferTo'),
      movement('2026-09-07', '-1', 'POSDVN'),
      movement('2026-09-07', '-1', 'INVAdjustment'),
    ]);
    expect(j.receiptDayOtherMovements.length, 2);
    expect(j.laterMovements, isEmpty);
    expect(j.noLaterMovementEstablished, false);
    expect(j.adjustmentTiming(j.adjustments.single), contains('order unknown'));
  });

  test(
    'three received, two sold or transferred, one expected after two months',
    () {
      final j = journey(
        [
          movement('2026-08-04', '-1', 'POSDVN'),
          movement('2026-09-07', '3', 'StockTransferTo'),
          movement('2026-09-20', '-1', 'POS'),
          movement('2026-10-01', '-1', 'StockTransferFrom'),
        ],
        {
          'event_at': '2026-11-07T12:00:00',
          'coverage_through': '2026-11-07',
          'baseline_qty': 1,
          'reconstructed_before': 1,
        },
      );
      expect(j.stockBeforeReceipt, 0);
      expect(j.sold, 1);
      expect(j.transferredOut, 1);
      expect(j.expectedBeforeCount, 1);
      expect(j.daysToCount, 61);
      expect(j.elapsedEnglish, '2 months (61 days)');
      expect(j.canCompareCount, true);
    },
  );

  test(
    'carryover stock, corrections, unknown exits and count-day uncertainty stay separate',
    () {
      final j = journey(
        [
          movement('2026-09-07', '3', 'StockTransferTo'),
          movement('2026-09-07', '-1', 'POS'),
          movement('2026-09-20', '-1', 'INVAdjustment'),
          movement('2026-09-21', '-1', 'INVBatchReplacement'),
          movement('2026-09-26', '-2', 'POS'),
        ],
        {'baseline_qty': 1, 'reconstructed_before': 1},
      );
      expect(j.stockBeforeReceipt, 1);
      expect(j.sold, 0);
      expect(j.receiptDayOtherNet, -1);
      expect(j.adjustmentNet, -1);
      expect(j.otherOut, 1);
      expect(j.countDayMovements.length, 1);
      expect(j.canCompareCount, false);
    },
  );

  test('elapsed months handle month-end without negative days', () {
    expect(
      journey([], {
        'last_receipt': '2026-01-31',
        'event_at': '2026-02-28',
      }).elapsedEnglish,
      '1 month (28 days)',
    );
    expect(
      journey([], {
        'last_receipt': '2026-01-31',
        'event_at': '2026-03-01',
      }).elapsedEnglish,
      '1 month and 1 day (29 days)',
    );
  });
}
