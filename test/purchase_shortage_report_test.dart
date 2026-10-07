import 'package:daily_order/core/utils/purchase_shortage_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses Dubai calendar date across midnight and month boundaries', () {
    expect(
      PurchaseShortageReport.today(now: DateTime.utc(2026, 10, 31, 19, 59)),
      '2026-10-31',
    );
    expect(
      PurchaseShortageReport.today(now: DateTime.utc(2026, 10, 31, 20)),
      '2026-11-01',
    );
    expect(
      PurchaseShortageReport.today(now: DateTime.utc(2026, 12, 31, 20)),
      '2027-01-01',
    );
  });

  test('does not apply the dashboard 9 PM business-date cutoff', () {
    expect(
      PurchaseShortageReport.today(now: DateTime.utc(2026, 10, 7, 18)),
      '2026-10-07',
    );
  });

  test('matches the Python archive contract', () {
    expect(
      PurchaseShortageReport.storagePath('2026-10-07'),
      '10-2026/Items Shortage Include Assortment 07-10-2026.xlsx',
    );
  });
}
