import 'package:daily_order/core/utils/stock_catalog_export.dart';
import 'package:daily_order/core/utils/stock_register_export.dart';
import 'package:daily_order/core/utils/stock_excel_report.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/domain/entities/stock_catalog.dart';
import 'package:daily_order/domain/entities/stock_expiry.dart';
import 'package:daily_order/domain/entities/stock_management.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => StoreBranchIdentityRegistry.groups.value = const {});
  test(
    'effective balances drive branch coverage and all three register exports',
    () {
      // Published stock already includes the allocation. UI/export must neither
      // discard it because base stock is zero nor add Final Reorder a second time.
      final data = <String, dynamic>{
        'item_code': 'effective-stock',
        'branches_base_stock': 0,
        'branches_final_reorder': 4,
        'branches_stock': 4,
        'store_stock': 6,
        'total_stock': 10,
        'daily_sales': 2,
        'recent_sales': 90,
        'days_on_hand': 5,
        'store_branches_ratio': 1.5,
        'stocked_branches': 1,
        'stock_status': 'low_cover',
        'meta': {'baseline_days': 42, 'recent_days': 3},
        'branches': [
          {
            'branch': 'Zakher Branch',
            'stock': 4,
            'base_stock': 0,
            'final_reorder': 4,
            'recent_sales': 9,
          },
          {
            'branch': 'CITY',
            'stock': 0,
            'base_stock': 0,
            'final_reorder': 0,
            'recent_sales': 9,
          },
        ],
      };
      final catalog = StockCatalogItem(data);
      final mrn = StockManagementItem(data);
      final expiry = StockExpiryAlert({
        'item_code': 'effective-stock',
        'product_data': data,
        'received_qty': 80,
        'expiry_date': '2027-01-01',
      });
      expect(catalogBranchRows(catalog).first['cover'], 20);
      expect(catalogBranchRows(catalog).last['cover'], 0);
      expect(mrn.storeTotalPercent, 60);
      expect(mrn.stockSalesPercent, closeTo(100 / 9, .000001));
      expect(mrn.ratio, 1.5);
      for (final row in [
        catalogExportRow(catalog),
        stockRegisterExportRow(mrn),
        stockExpiryExportRow(expiry),
      ]) {
        expect(row['Branches stock'], 4);
        expect(row['Total stock'], 10);
        expect(row['Cover days'] ?? row['Stock cover (days)'], 5);
      }
      expect(expiry.product.number('total_stock'), 10);
      expect(expiry.number('received_qty'), 80);
      StoreBranchIdentityRegistry.groups.value = {
        'ZAKHER BRANCH': '71',
        'CITY': 'APG',
      };
      final report = StockExcelReport(
        catalogBranchRows(catalog),
        'branches.xlsx',
      );
      final values = report.values.toList();
      expect(values.first[report.keys.indexOf('branch')], '71 Zakher Branch');
      expect(values.last[report.keys.indexOf('branch')], 'CITY');
      expect(values.first[report.keys.indexOf('stock')], 4);
      expect(data['branches_final_reorder'], 4);
    },
  );
}
