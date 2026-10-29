import '../../domain/entities/stock_supply_insight.dart';
import '../../domain/entities/stock_catalog.dart';
import '../../domain/entities/stock_management.dart';
import 'stock_item_added_date.dart';

Map<String, dynamic> catalogExportRow(StockCatalogItem item) => {
  'Item code': item.code,
  'Product': item.name,
  'Reference': item.text('reference'),
  'Item status': item.itemStatus,
  'Created date': formatStockItemAddedDate(
    item.data['added_date_time'],
    empty: '',
  ),
  'Category': item.text('category'),
  'Supplier': item.text('supplier'),
  'Ingredient': item.text('main_ingredient'),
  'Indication': item.text('indication'),
  'Sub-category': item.text('sub_category'),
  'Company': item.text('company'),
  'Branches stock': item.number('branches_stock'),
  'STORE stock': item.number('store_stock'),
  'APG stock': item.number('apg_stock'),
  'APG branches only': item.number('apg_branches_stock'),
  '71 branches stock': item.number('stock_71'),
  'Total stock': item.number('total_stock'),
  'Cover days': item.days,
  'STORE / Total Stock %': item.storeTotalPercent,
  'Purchase Status': item.purchaseStatus,
  for (final year in catalogSalesYears(item)) ...{
    'Sales $year': item.year(year)['total'] ?? 0,
    'Cash $year': item.year(year)['cash'] ?? 0,
    'Insurance $year': item.year(year)['insurance'] ?? 0,
    'Online $year': item.year(year)['online'] ?? 0,
  },
  'Last 3 days Qty': item.number('last_3_sales'),
  'Previous 42 days Qty': item.number('baseline_sales'),
  '3-day daily average': item.data['recent_daily'],
  '42-day daily average': item.data['baseline_daily'],
  'Sales 45D': item.number('recent_sales'),
  'Growth %': item.growth,
  'Status': item.signal,
  ...StockSupplyInsight.of(item).exportFields,
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
  'Reorder branches': item.distributionStatus.orderDataAvailable
      ? item.distributionStatus.reorder
      : null,
  'Final order branches': item.distributionStatus.orderDataAvailable
      ? item.distributionStatus.finalOrders
      : null,
  'Reorder Qty': item.distributionStatus.orderDataAvailable
      ? item.distributionStatus.reorderQuantity
      : null,
  'Final Reorder Qty': item.distributionStatus.orderDataAvailable
      ? item.distributionStatus.finalQuantity
      : null,
  'Order data complete': item.distributionStatus.known ? 'Yes' : 'No',
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

/// Keep chart exports aligned with every plotted month, including zero months.
List<Map<String, dynamic>> catalogMonthlyExportRows(StockCatalogItem item) {
  final insight = StockSupplyInsight.of(item);
  final evidence = {for (final row in insight.months) row['month']: row};
  return [
    for (final row in catalogMonthlySeries(item))
      {
        ...row,
        if (insight.hasChartPeriods) ...{
          'STORE chart timeline': insight.chartMonthDescription(row['month']),
          'STORE receipt timeline': insight
              .chartArrivalsInMonth(row['month'])
              .map(
                (r) =>
                    '${r['date']}: ${StockSupplyInsight.arrivalLabel(r)} · ${r['qty']} Qty',
              )
              .join('; '),
          'STORE chart timeline basis': insight.chartNeedsReview
              ? 'Estimated · Stock history needs checking'
              : 'Estimated from STORE movements and historical sales',
        },
        if (row['source'] != null)
          'source': row['source'] == 'sales_last_45_days'
              ? 'Daily sales'
              : 'Monthly history',
        if (evidence[row['month']] case final month?) ...{
          'STORE empty days': month['empty_days'],
          'STORE stocked days': month['available_days'],
          'STORE partial days': month['partial_days'],
          'STORE analysis basis': insight.basis,
          'STORE evidence note': insight.basisDescription,
          if (insight.hasSupplyAnalysis) ...{
            'STORE supply interruption days': month['limited_days'],
            'STORE learned daily demand': insight.demandModel['daily_qty'],
            'STORE recovery Qty threshold': insight.demandModel['recovery_qty'],
            'STORE supply interruption basis':
                'Estimated from historical demand and STORE movements',
          },
        },
      },
  ];
}
