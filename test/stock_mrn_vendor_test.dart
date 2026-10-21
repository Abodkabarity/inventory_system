import 'package:daily_order/core/utils/stock_register_export.dart';
import 'package:daily_order/domain/entities/stock_management.dart';
import 'package:daily_order/domain/entities/stock_expiry.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_management_grid.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_expiry_grid.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_management_formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const item = StockManagementItem({
    'item_code': 'A',
    'item_name': 'Product A',
    'vendor': ' abcdefghijklmnop ',
    'total_stock': 100,
    'store_stock': 25,
    'branches_stock': 75,
    'store_branches_ratio': 1 / 3,
  });
  test(
    'vendor labels are trimmed, uppercase and limited by Unicode characters',
    () {
      expect(formatStockVendor(item.data['vendor']), 'ABCDEFGHIJ');
      expect(formatStockVendor('  short  '), 'SHORT');
      expect(formatStockVendor(null), '');
      expect(formatStockVendor('😀abcdefghi-more'), '😀ABCDEFGHI');
    },
  );
  test(
    'MRN grid filters and sorts the displayed vendor and total-stock percentage',
    () {
      final source = StockManagementGridSource([item], onOpen: (_) {});
      addTearDown(source.dispose);
      final keys = StockManagementGridSource.columns.map((c) => c.$1).toList();
      expect(keys[keys.indexOf('received_quantity') + 1], 'vendor');
      expect(keys[keys.indexOf('branches_stock') + 1], 'total_stock');
      final cells = {
        for (final c in source.rows.single.getCells()) c.columnName: c.value,
      };
      expect(cells['vendor'], 'ABCDEFGHIJ');
      expect(cells['store_total_percent'], 25);
      expect(cells.containsKey('store_branches_ratio'), isFalse);
      expect(formatStockPercentage(cells['store_total_percent'] as num), '25%');
    },
  );
  test('expiry grid uses that receipt vendor and same numeric store share', () {
    final alert = StockExpiryAlert({
      'item_code': 'A',
      'expiry_date': '2026-12-01',
      'vendor': '  selected-vendor-long ',
      'product_data': item.data,
    });
    final source = StockExpiryGridSource(
      alerts: [alert],
      busy: {},
      fading: {},
      onOpen: (_) {},
      onReview: (_) {},
      riskColor: (_) => Colors.red,
    );
    addTearDown(source.dispose);
    final keys = StockExpiryGridSource.columns.map((c) => c.$1).toList();
    expect(keys[keys.indexOf('received_qty') + 1], 'vendor');
    expect(keys[keys.indexOf('branches_stock') + 1], 'total_stock');
    final cells = {
      for (final c in source.rows.single.getCells()) c.columnName: c.value,
    };
    expect(cells['vendor'], 'SELECTED-V');
    expect(cells['store_total_percent'], 25);
    expect(cells.containsKey('store_branches_ratio'), isFalse);
  });
  test(
    'Excel follows vendor placement, receipt identity and total-stock formula',
    () {
      final row = stockRegisterExportRow(item);
      final keys = row.keys.toList();
      expect(keys[keys.indexOf('Received Qty') + 1], 'Vendor');
      expect(keys[keys.indexOf('Branches stock') + 1], 'Total stock');
      expect(row['Vendor'], 'ABCDEFGHIJ');
      expect(row['Store / Total stock %'], 25);
      expect(row.containsKey('Store / branches %'), isFalse);
      final exported = stockExpiryExportRow(
        StockExpiryAlert({
          'item_code': 'A',
          'expiry_date': '2026-12-01',
          'vendor': 'selected-vendor-long',
          'product_data': item.data,
        }),
      );
      expect(exported['Vendor'], 'SELECTED-V');
      expect(exported['Store / Total stock %'], 25);
      expect(
        stockRegisterExportRow(
          const StockManagementItem({'total_stock': 0}),
        )['Store / Total stock %'],
        isNull,
      );
    },
  );
}
