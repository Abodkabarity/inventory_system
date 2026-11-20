import '../../domain/entities/online_overview.dart';
import 'store_branch_identity_registry.dart';

/// Decorate branch cells before passing these rows to the browser worker.
List<Map<String, dynamic>> onlineOverviewExportRows(
  List<OnlineOverviewRow> rows, {
  required OnlineOverviewSnapshot snapshot,
  required OnlineSalesScope scope,
  Map<String, OnlineProductAudit> audits = const {},
}) => [
  for (final row in rows)
    {
      'item_code': row.item.code,
      'item_name': row.item.name,
      'rank': row.rank.label,
      'rank_reason': row.reason,
      'item_status': row.item.itemStatus,
      'purchase_status': row.purchaseStatus,
      'sales_orientation': row.item.data['sales_orientation'],
      'branch_name': row.branchNames.length == 1
          ? StoreBranchIdentityRegistry.exportValue(
              'branch_name',
              row.branchNames.single,
            )
          : 'All online branches',
      'online_branches': row.branchNames
          .map(StoreBranchIdentityRegistry.displayName)
          .join(' / '),
      'sales_scope': scope.label,
      'sales_2025': row.sales25,
      'comparable_2025_qty': row.comparable25,
      'sales_2026': row.sales26,
      'last_3_completed_months_qty': row.recentQty,
      'selling_months_2026': row.sellingMonths,
      'retail': row.priceKnown ? row.retail : null,
      'estimated_retail_value_2026': row.estimatedValue,
      'value_basis': 'Net Qty x current Retail; not actual historical revenue',
      if (row.usesActualSales) ...{
        'ranking_sales_from': row.actualSales['sales_from'],
        'rank_before_actual_sales_trial': row.classification['previous_rank'],
        'ranking_sales_through': row.actualSales['sales_through'],
        'online_qty_last_6_full_months': row.actualSales['actual_qty'],
        'online_value_last_6_full_months_at_current_retail':
            row.actualSales['actual_value'],
        'selling_branches_last_6_full_months':
            row.actualSales['selling_branches'],
        'selling_months_last_6_full_months': row.actualSales['selling_months'],
        'six_month_comparison_qty': row.actualSales['qty_score'],
        'six_month_comparison_value': row.actualSales['value_score'],
        'a_rules_met': (row.actualSales['routes'] as List? ?? []).join(' / '),
      },
      'classification_basis': row.classification['basis'],
      'classification_version': row.classification['version'],
      'classification_rules_version': row.classification['rules_version'],
      'rank_before_six_month_trial': row.classification['previous_rank'],
      'mrn_product_age': row.productAge['status'],
      'first_mrn_date': row.productAge['first_mrn'],
      'new_product_until': row.productAge['new_until'],
      'product_age_as_of': row.productAge['as_of'],
      'months_since_first_mrn': row.productAge['months_since_mrn'],
      'first_online_sale_month': row.productAge['first_online_sale_month'],
      'months_from_mrn_to_first_online_sale':
          row.productAge['months_to_first_sale'],
      'new_product_available_months': row.productAge['available_months'],
      'new_product_age_adjusted': row.productAge['age_adjusted'],
      'forecast_horizon_months': row.hasSalesForecast ? 6 : null,
      'forecast_from': row.hasSalesForecast
          ? row.salesForecast['forecast_from']
          : null,
      'forecast_to': row.hasSalesForecast
          ? row.salesForecast['forecast_to']
          : null,
      'forecast_qty': row.hasSalesForecast ? row.salesForecast['qty'] : null,
      'forecast_estimated_sales_aed': row.hasSalesForecast
          ? row.salesForecast['estimated_value']
          : null,
      'forecast_method': row.hasSalesForecast
          ? row.salesForecast['model']
          : null,
      'suggested_online_branches': row.hasSalesForecast
          ? row.forecastBranches
                .map(StoreBranchIdentityRegistry.displayName)
                .join(' / ')
          : null,
      'classification_through': row.classThresholds['through'],
      'stock_snapshot_date': row.classification['stock_day'],
      'network_online_qty_2026_completed_months': row.networkSales26,
      'network_selling_branches_2026': row.sellingBranches26,
      'network_total_branches': row.networkBranchCount,
      'network_selling_coverage_pct_points': row.networkCoverage * 100,
      'quantity_lower_quartile': row.classThresholds['low'],
      'quantity_median': row.classThresholds['median'],
      'quantity_upper_quartile': row.classThresholds['high'],
      'A_network_spread_minimum_branches':
          row.classThresholds['minimum_A_branches'],
      'A_value_threshold_aed': row.classThresholds['value_high'],
      'estimated_network_sales_value_aed':
          row.classification['estimated_network_sales_value'],
      'priority_branches': row.priorityBranches
          .map(StoreBranchIdentityRegistry.displayName)
          .join(' / '),
      'class_evidence_status': row.evidenceStatus,
      'class_evidence_note': row.evidenceNote,
      'last_online_selling_month': row.classification['last_selling_month'],
      'verified_recent_stocked_days':
          row.classification['recent_verified_stocked_days'],
      'ever_entered_online': row.classification['ever_entered'],
      'complete_stock_history': row.classification['full_history'],
      'price_affects_abc': row.classification['price_affects_abc'] == true,
      'ml_suggested_abc': row.modelPrediction['class'],
      'ml_uncalibrated_score': row.modelPrediction['score'],
      'ml_model_version': row.modelPrediction['model_version'],
      'ml_use': row.modelPrediction['use'],
      'ml_disagrees_with_current_class': row.classification['ml_disagrees'],
      'store_stock': row.storeStock,
      'other_branch_stock': row.otherBranchStock,
      'online_plus_store_stock': row.combinedStock,
      'online_physical_stock': row.onlineStock,
      'online_stock_cover_days': row.stockCoverDays,
      'current_reported_online_qty': row.displayedStock,
      'online_availability': row.availability,
      'stock_reported_branches': row.reportCount,
      'stock_total_branches': row.branchNames.length,
      'branches_with_stock': row.stockedBranches,
      'stock_is_partial': row.partialStock,
      'missing_branch_reports': row.missingBranches
          .map(StoreBranchIdentityRegistry.displayName)
          .join(' / '),
      'a_qualification': row.aQualification,
      'repeat_demand_evidence': row.repeatEvidence,
      'class_assessment': row.cExplanation,
      'minimum_stocked_days_per_branch': row.stockedDays,
      'history_basis': audits[row.item.code] == null
          ? snapshot.generation.isEmpty
                ? 'Not checked'
                : 'Prepared server result; unknown evidence remains blank'
          : audits[row.item.code]!.branches.values.any((a) => a.estimated)
          ? 'Includes reconciled estimates; review product evidence'
          : 'See branch evidence; incomplete branches remain unknown',
      'supply_status': row.supply,
      'suggested_action': row.action,
      'supplier': row.item.text('supplier'),
      'category': row.item.text('category'),
      'main_ingredient': row.item.text('main_ingredient'),
      'created_date': row.item.data['added_date_time'],
      'catalog_snapshot_at': snapshot.catalog.meta['refreshed_at'],
      'loaded_at': snapshot.loadedAt.toIso8601String(),
      'history_through':
          audits[row.item.code]?.through.toIso8601String() ??
          snapshot.serverMeta['history_through'],
      'prepared_generation': snapshot.generation,
    },
];
