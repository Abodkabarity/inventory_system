import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_management_formatters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daily_order/core/utils/stock_item_added_date.dart';

void main() {
  test('Item Report date uses Dubai calendar day without displaying time', () {
    expect(formatStockItemAddedDate('2025-01-01T00:00:00+04:00'), '01/01/2025');
    expect(formatStockItemAddedDate('2024-12-31T20:00:00Z'), '01/01/2025');
    expect(formatStockItemAddedDate('2026-10-15'), '15/10/2026');
    expect(formatStockItemAddedDate('2026-10-15T02:30:00+08:00'), '14/10/2026');
    expect(formatStockItemAddedDate(null), '—');
    expect(formatStockItemAddedDate('invalid'), '—');
    expect(formatStockItemAddedDate(null, empty: ''), '');
    expect(stockItemAddedDate('2025-01-01T22:00:00Z'), DateTime(2025, 1, 2));
  });
  test('formats store-to-branches ratios as percentages', () {
    expect(formatStoreBranchesPercentage(null), '—');
    expect(formatStoreBranchesPercentage(0), '0%');
    expect(formatStoreBranchesPercentage(0.4164), '41.64%');
    expect(formatStoreBranchesPercentage(1.1), '110%');
    expect(formatStoreBranchesPercentage(2.35), '235%');
  });
}
