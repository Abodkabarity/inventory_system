import 'package:csv/csv.dart';
import '../../domain/entities/stock_catalog.dart';
import '../../domain/entities/stock_management.dart';
import 'store_branch_identity_registry.dart';
import 'stock_item_added_date.dart';
import 'stock_catalog_export_stub.dart'
    if (dart.library.html) 'stock_catalog_export_web.dart'
    as platform;

Map<String, dynamic> catalogExportRow(StockCatalogItem item) => {
  'Item code': item.code,
  'Product': item.name,
  'Item status': item.itemStatus,
  'Created date': formatStockItemAddedDate(
    item.data['added_date_time'],
    empty: '',
  ),
  'Category': item.text('category'),
  'Supplier': item.text('supplier'),
  'Company': item.text('company'),
  'Branches stock': item.number('branches_stock'),
  'STORE stock': item.number('store_stock'),
  'APG stock': item.number('apg_stock'),
  'APG branches only': item.number('apg_branches_stock'),
  '71 branches stock': item.number('stock_71'),
  'Total stock': item.number('total_stock'),
  'Cover days': item.days,
  'Branches / STORE %': item.branchesStorePercent,
  for (final year in [2025, 2026]) ...{
    'Sales $year': item.year(year)['total'] ?? 0,
    'Cash $year': item.year(year)['cash'] ?? 0,
    'Insurance $year': item.year(year)['insurance'] ?? 0,
    'Online $year': item.year(year)['online'] ?? 0,
  },
  'Last 3 days Qty': item.number('last_3_sales'),
  'Previous 42 days Qty': item.number('baseline_sales'),
  '3-day daily average': item.data['recent_daily'],
  '42-day daily average': item.data['baseline_daily'],
  '45-day net Qty': item.number('recent_sales'),
  'Growth %': item.growth,
  'Status': item.signal,
  'Distribution status': item.distributionStatus.label,
  'First STORE MRN date': formatStockItemAddedDate(
    item.distributionStatus.firstReceivedDate,
    empty: '',
  ),
  'Latest STORE MRN date': formatStockItemAddedDate(
    item.distributionStatus.lastReceivedDate,
    empty: '',
  ),
  'Days in STORE': item.distributionStatus.daysInStore,
  'STORE received after creation':
      item.distributionStatus.receivedAfterCreation,
  'STORE received qty since creation': stockMap(
    item.data['store_receipt'],
  )['received_qty'],
  'STORE after final orders': item.distributionStatus.known
      ? item.distributionStatus.availableStore
      : null,
  'Product age (days)': item.distributionStatus.ageDays,
  'Branches for distribution': item.distributionStatus.known
      ? item.distributionStatus.eligible
      : null,
  'Stocked branches': item.distributionStatus.known
      ? item.distributionStatus.stocked
      : null,
  'Reorder branches': item.distributionStatus.known
      ? item.distributionStatus.reorder
      : null,
  'Final order branches': item.distributionStatus.known
      ? item.distributionStatus.finalOrders
      : null,
  'Stock or final order branches': item.distributionStatus.known
      ? item.distributionStatus.covered
      : null,
  'Uncovered branches': item.distributionStatus.known
      ? item.distributionStatus.uncovered
      : null,
  'Order run date': stockMap(item.data['distribution'])['run_date'],
  'New product maximum age': item.distributionRules.maxAgeDays,
  'Distribution minimum STORE stock': item.distributionRules.minStoreStock,
  'Distribution maximum covered branches':
      item.distributionRules.maxCoveredBranches,
};

String catalogCsv(List<Map<String, dynamic>> rows) {
  if (rows.isEmpty) return '';
  final columns = rows.first.keys.toList();
  // Display values are decorated before they reach the CSV encoder/download.
  return '\uFEFF${const ListToCsvConverter().convert([
    columns,
    for (final r in rows) [for (final c in columns) StoreBranchIdentityRegistry.exportValue(c, r[c]) ?? ''],
  ])}';
}

Future<void> saveCatalogCsv(List<Map<String, dynamic>> rows, String fileName) =>
    platform.saveCsv(catalogCsv(rows), fileName);
