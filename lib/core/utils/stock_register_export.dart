import '../../domain/entities/stock_supply_insight.dart';
import '../../domain/entities/stock_management.dart';
import '../../domain/entities/stock_expiry.dart';
import 'stock_item_added_date.dart';
import 'stock_vendor.dart';
import 'store_branch_identity_registry.dart';

typedef StockRegisterExporter =
    Future<void> Function(List<Map<String, dynamic>> rows, String fileName);

Map<String, dynamic> stockRegisterExportRow(StockManagementItem item) => {
  if (item.isCdReceipt)
    'Warehouse': StoreBranchIdentityRegistry.displayName(item.warehouse),
  'Item code': item.code,
  'Product': item.name,
  'Reference': item.text('reference'),
  'Created date': formatStockItemAddedDate(
    item.data['added_date_time'],
    empty: '',
  ),
  'Category': item.text('category'),
  'Supplier': item.text('supplier'),
  'Company': item.text('company'),
  'MRN date': formatStockItemAddedDate(item.data['last_mrn_date'], empty: ''),
  'MRN number': item.text('last_mrn_no'),
  'Expiry date': formatStockItemAddedDate(item.data['expiry_date'], empty: ''),
  'Ordered Qty': item.data['ordered_quantity'],
  'Total Qty': item.receiptTotal,
  'Bonus Qty': item.receiptBonus,
  'Vendor': formatStockVendor(item.data['vendor']),
  'Store stock': item.stockAvailable ? item.number('store_stock') : null,
  'Branches stock': item.stockAvailable ? item.number('branches_stock') : null,
  'Total stock': item.stockAvailable ? item.number('total_stock') : null,
  'Store / Total stock %': item.storeTotalPercent,
  'Stock / Sales %': item.stockSalesPercent,
  'Stock cover (days)': item.stockAvailable ? item.days : null,
  'Purchase Status': item.purchaseStatus,
  'Sales 45D': item.data['recent_sales'],
  'Stock status': item.stockAvailable ? item.status : 'Unavailable',
  ...StockSupplyInsight.of(item).exportFields,
  for (final year in stockSalesYears(item)) ...{
    'Sales $year': item.year(year)['total'],
    'Cash $year': item.year(year)['cash'],
    'Insurance $year': item.year(year)['insurance'],
    'Online $year': item.year(year)['online'],
    'Best month $year': item.year(year)['best_month'],
    'Best month Qty $year': item.year(year)['best_qty'],
  },
};

Map<String, dynamic> stockExpiryExportRow(StockExpiryAlert alert) => {
  ...stockRegisterExportRow(alert.product),
  'Reference': alert.text('reference'),
  'MRN number': alert.text('mrn_numbers'),
  'MRN date': formatStockItemAddedDate(
    alert.data['last_receipt_date'],
    empty: '',
  ),
  'Expiry date': formatStockItemAddedDate(alert.expiry, empty: ''),
  'Ordered Qty': alert.data['ordered_qty'],
  'Total Qty': alert.data['total_qty'] ?? alert.data['received_qty'],
  'Bonus Qty': alert.number('bonus'),
  'Vendor': formatStockVendor(alert.data['vendor']),
  'Days to expiry': alert.days,
  'Review status': alert.reviewed ? 'Reviewed' : 'Active',
  'New receipts': alert.newReceipts ? 'Yes' : 'No',
  'Note': alert.note,
};
