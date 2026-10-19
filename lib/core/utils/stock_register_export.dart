import '../../domain/entities/stock_management.dart';
import '../../domain/entities/stock_expiry.dart';
import 'stock_item_added_date.dart';

typedef StockRegisterExporter =
    Future<void> Function(List<Map<String, dynamic>> rows, String fileName);

Map<String, dynamic> stockRegisterExportRow(StockManagementItem item) => {
  'Item code': item.code,
  'Product': item.name,
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
  'Received Qty': item.data['received_quantity'],
  'Total stock': item.stockAvailable ? item.number('total_stock') : null,
  'Store stock': item.stockAvailable ? item.number('store_stock') : null,
  'Branches stock': item.stockAvailable ? item.number('branches_stock') : null,
  'Store / branches %': item.stockAvailable && item.ratio != null
      ? item.ratio! * 100
      : null,
  'Stock / Sales %': item.stockSalesPercent,
  'Stock cover (days)': item.stockAvailable ? item.days : null,
  'Sales 45D': item.data['recent_sales'],
  'Stock status': item.stockAvailable ? item.status : 'Unavailable',
  for (final year in [2025, 2026]) ...{
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
  'MRN date': formatStockItemAddedDate(
    alert.data['last_receipt_date'],
    empty: '',
  ),
  'Expiry date': formatStockItemAddedDate(alert.expiry, empty: ''),
  'Ordered Qty': alert.data['ordered_qty'],
  'Received Qty': alert.data['received_qty'],
  'Days to expiry': alert.days,
  'Review status': alert.reviewed ? 'Reviewed' : 'Active',
  'New receipts': alert.newReceipts ? 'Yes' : 'No',
  'Note': alert.note,
};
