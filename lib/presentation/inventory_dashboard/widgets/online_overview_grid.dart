import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:syncfusion_flutter_core/theme.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/stock_item_added_date.dart';
import '../../../domain/entities/online_overview.dart';
import '../../../domain/entities/stock_management.dart' show stockNumber;
import 'stock_catalog_visuals.dart';

Color onlineRankColor(OnlineRank rank) => switch (rank) {
  OnlineRank.a => catalogTeal,
  OnlineRank.b => catalogBlue,
  OnlineRank.c => catalogRose,
  OnlineRank.n => const Color(0xFFB66A09),
  OnlineRank.m => catalogOrange,
  OnlineRank.t => catalogPurple,
  OnlineRank.s => const Color(0xFF167DA5),
  OnlineRank.review => catalogMuted,
};

String onlineRankTitle(OnlineRank rank) => switch (rank) {
  OnlineRank.a => 'A · High priority',
  OnlineRank.b => 'B · Medium sales',
  OnlineRank.c => 'C · Low sales',
  OnlineRank.n => 'N · New, no online stock',
  OnlineRank.m => 'M · No stock or sales',
  OnlineRank.t => 'T · Stock with no recent sales',
  OnlineRank.s => 'S · In-house',
  OnlineRank.review => 'Needs review',
};

String onlinePriorityLabel(OnlineOverviewRow row) =>
    switch (row.classification['priority_route']) {
      'network_quantity' => 'A · Strong sales in many branches',
      'concentrated_quantity' => 'A · Strong sales in fewer branches',
      'sales_value' => 'A · High sales value',
      'premium_repeat' => 'A · Regular sales, high price',
      'forecast_quantity' => 'A · High expected Qty',
      'forecast_value' => 'A · High expected sales value',
      'wide_branch_sales' => 'A · Sales in many branches',
      'high_sales_qty' => 'A · High Qty sold',
      'high_sales_value' => 'A · High sales value',
      _ => onlineRankTitle(row.rank),
    };

String onlinePlainReason(OnlineOverviewRow row) {
  if (row.usesActualSales) return row.reason;
  if (row.hasSalesForecast) return '${row.salesForecast['reason']}';
  final data = row.classification;
  final cuts = row.classThresholds;
  final units = row.networkSales26;
  final lastYear = stockNumber(data['sales_2025']);
  final sellingMonths = stockNumber(data['selling_months_2026']).toInt();
  final value = data['estimated_network_sales_value'];
  final valueTarget = cuts['value_high'];
  final hasSalesFacts = data['sales_2026'] != null && cuts['high'] != null;
  final soldThisYear = catalogQty(units);
  final branchCount = row.sellingBranches26;
  final branches = '$branchCount ${branchCount == 1 ? 'branch' : 'branches'}';

  switch (row.rank) {
    case OnlineRank.a:
      if (data['priority_route'] == 'premium_repeat') {
        final periods = stockNumber(data['selling_periods_last_12']).toInt();
        return 'Retail AED ${catalogQty(row.retail)}. Sold in $periods of the '
            'last 4 three-month periods, including the most recent.';
      }
      if (!hasSalesFacts) return 'This product sold well in several months.';
      final repeat = sellingMonths == 2
          ? 'It sold in 2 months in 2026 and also sold in 2025.'
          : 'It sold in $sellingMonths months and sold recently.';
      if (data['priority_route'] == 'sales_value' && value != null) {
        return 'Estimated online sales: AED ${catalogQty(value)}. '
            'Top 10% by sales value. $repeat';
      }
      return 'Online sales: $soldThisYear Qty in $branches. '
          'Top 25% by Qty. $repeat';
    case OnlineRank.b:
      if (!hasSalesFacts) return 'Medium online sales.';
      if (stockNumber(data['recent_3_qty']) <= 0) {
        return 'Online sales in 2026: $soldThisYear Qty. There were no sales left after returns in the last 3 full months.';
      }
      if (sellingMonths < 3 && (sellingMonths < 2 || lastYear <= 0)) {
        return 'Sold $soldThisYear Qty in $sellingMonths ${sellingMonths == 1 ? 'month' : 'months'}. '
            'A needs sales in 3 months, or 2 months plus sales in 2025.';
      }
      final valueReason = value == null || valueTarget == null
          ? ''
          : stockNumber(value) < stockNumber(valueTarget)
          ? ' Sales value was below the top 10%.'
          : ' A by value needs at least 3 Qty sold over 3 months.';
      return 'Sold $soldThisYear Qty in $branches. A by Qty is for the top '
          '25% of online sellers.$valueReason';
    case OnlineRank.c:
      if (!hasSalesFacts) return 'Low online sales.';
      if (units.clamp(0, double.infinity) +
              lastYear.clamp(0, double.infinity) <=
          2) {
        return 'Sold ${catalogQty(lastYear)} Qty in 2025 and $soldThisYear Qty in 2026. Sales were low across both years.';
      }
      if (units <= 0) {
        return 'Sold ${catalogQty(lastYear)} Qty in 2025. Sales after returns were zero or less in 2026.';
      }
      final bTarget = math.max(
        math.max(2, stockNumber(cuts['low'])),
        branchCount > 4 ? 0 : stockNumber(cuts['median']),
      );
      return 'Sold $soldThisYear Qty in $branches. With that many branches, B needs more than ${catalogQty(bTarget)} Qty.';
    case OnlineRank.m:
      return 'Online stock is 0 Qty. No online sales were recorded in 2025 or 2026.';
    case OnlineRank.n:
      return 'First MRN ${catalogDate(row.productAge['first_mrn'])}. '
          'Less than 6 months since the first MRN. Stock is 0 Qty in every online branch. '
          'STORE stock: ${catalogQty(row.storeStock)} Qty.';
    case OnlineRank.t:
      return 'Stock is available in online branches. No online sales were recorded in the last 6 full months or the current month.';
    case OnlineRank.s:
      return 'Sales Orientation is INHOUSE. This product is assigned S.';
    case OnlineRank.review:
      return 'No online sales were found. Check missing stock reports or negative stock figures.';
  }
}

String onlineStockNote(OnlineOverviewRow row) => row.reportCount == null
    ? 'Stock reports unavailable'
    : '${row.reportCount} of ${row.branchNames.length} branches reported';

const onlineStockCoverBasis =
    'Based on average daily online sales in the last 3 full months.';

String onlineStockCoverLabel(double? days) {
  if (days == null) return '—';
  if (days > 0 && days < 1) return '< 1 day';
  final fullDays = days.floor();
  return '${catalogQty(fullDays)} ${fullDays == 1 ? 'day' : 'days'}';
}

String onlineStockCoverNote(OnlineOverviewRow row) {
  if (row.partialStock || row.onlineStock == null) {
    return 'Stock reports are incomplete.';
  }
  if (row.onlineStock! < 0) return 'Check the negative stock balance.';
  if (row.stockCoverSalesWindowDays == null) {
    return 'The sales period is unavailable.';
  }
  if (row.recentQty <= 0) {
    return 'No positive online sales in the last 3 full months.';
  }
  return onlineStockCoverBasis;
}

class OnlineStockCoverBar extends StatelessWidget {
  final double? days;
  final String? title, note;
  const OnlineStockCoverBar({
    super.key,
    required this.days,
    this.title,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (days) {
      null => catalogMuted,
      < 7 => catalogRose,
      < 14 => catalogOrange,
      < 30 => catalogBlue,
      _ => catalogTeal,
    };
    final label = onlineStockCoverLabel(days);
    const bands =
        'Red under 7 days. Orange from 7 to 13 days. '
        'Blue from 14 to 29 days. Green from 30 days.';
    return Tooltip(
      message: days == null
          ? note ?? 'Stock cover unavailable'
          : '${note ?? onlineStockCoverBasis} $bands',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: title == null
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Text(
            title == null ? label : '$title · $label',
            style: TextStyle(
              color: days == null
                  ? color
                  : Color.alphaBlend(catalogInk.withValues(alpha: .36), color),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 100,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: ((days ?? 0) / 90).clamp(0.0, 1.0),
                minHeight: 5,
                color: color,
                backgroundColor: days == 0
                    ? color.withValues(alpha: .2)
                    : const Color(0xFFE9EFF7),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String onlinePurchaseLabel(String status) =>
    switch (status.trim().toUpperCase()) {
      'OOS' => 'Out of stock',
      'AVAILABLE' => 'Available',
      'NOT AVAILABLE' => 'Not available',
      'DISCONTINUED' => 'Discontinued',
      _ => status,
    };

String onlineItemLabel(String status) =>
    status.trim().toUpperCase() == '1#NORMAL PURCHASE'
    ? 'Normal purchase'
    : status;

class OnlineOverviewGridSource extends DataGridSource {
  final ValueChanged<OnlineOverviewRow> onOpen, onAudit;
  final _identity = <DataGridRow, OnlineOverviewRow>{};
  final _positions = <DataGridRow, int>{};
  List<DataGridRow> _rows = [];
  final _preparedGridRows = Expando<DataGridRow>('online-prepared-grid-row');
  bool actualSales = false;
  String columnTitle(String key, String fallback) => !actualSales
      ? fallback
      : switch (key) {
          'coverage' => 'Branches with sales · 6 months',
          'forecast_qty' => 'Sold · 6 months (Qty)',
          'forecast_value' => 'Sales value · 6 months (AED)',
          'plan_branches' => 'Branches to keep stock',
          'months' => 'Months with sales · 6 months',
          _ => fallback,
        };
  static const columns = <(String, String, double)>[
    ('rank', 'Priority', 130),
    ('product', 'Product', 300),
    ('online_stock', 'Online stock', 160),
    ('store', 'Store stock', 165),
    ('other_branch_stock', 'Other branch stock', 175),
    ('stock_cover', 'Stock cover', 140),
    ('sales26', 'Sold in 2026', 150),
    ('coverage', 'Branches with sales', 175),
    ('purchase_status', 'Purchase status', 195),
    ('forecast_qty', 'Next 6 months Qty', 180),
    ('forecast_value', 'Next 6 months (AED)', 195),
    ('plan_branches', 'Planned branches', 170),
    ('item_status', 'Item status', 165),
    ('availability', 'Stock status', 210),
    ('stocked_branches', 'Branches with stock', 185),
    ('recent', 'Last 3 months', 160),
    ('retail', 'Price (AED)', 135),
    ('value', 'Estimated sales (AED)', 195),
    ('sales25', 'Sold in 2025', 145),
    ('comparable25', 'Same months in 2025', 190),
    ('months', 'Months with sales', 180),
    ('days', 'Past days with stock', 160),
    ('supply', 'Warehouse supply', 215),
    ('reason', 'Why this priority?', 340),
    ('action', 'Next step', 315),
    ('supplier', 'Supplier', 230),
    ('category', 'Category', 190),
    ('ingredient', 'Ingredient', 260),
    ('created', 'Date added', 155),
    ('audit', 'Stock history', 150),
  ];
  OnlineOverviewGridSource({required this.onOpen, required this.onAudit});
  List<OnlineOverviewRow> get displayedRows =>
      effectiveRows.map((row) => _identity[row]!).toList();
  Object? _value(OnlineOverviewRow row, String key) => switch (key) {
    'rank' => row.rank.label,
    'product' => '${row.item.name}\n${row.item.code}',
    'coverage' =>
      row.usesActualSales
          ? '${row.actualSales['selling_branches']} of ${row.networkBranchCount}'
          : '${row.sellingBranches26} of ${row.networkBranchCount}',
    'item_status' => onlineItemLabel(row.item.itemStatus),
    'purchase_status' => row.purchaseStatus,
    'sales26' => row.sales26,
    'forecast_qty' =>
      row.usesActualSales
          ? row.actualSales['actual_qty']
          : row.hasSalesForecast
          ? row.salesForecast['qty']
          : null,
    'forecast_value' =>
      row.usesActualSales
          ? row.actualSales['actual_value']
          : row.hasSalesForecast
          ? row.salesForecast['estimated_value']
          : null,
    'plan_branches' =>
      row.usesActualSales
          ? row.priorityBranches.length
          : row.hasSalesForecast
          ? row.forecastBranches.length
          : null,
    'recent' => row.recentQty,
    'retail' => row.priceKnown ? row.retail : null,
    'value' => row.estimatedValue,
    'sales25' => row.sales25,
    'comparable25' => row.comparable25,
    'months' =>
      row.usesActualSales
          ? row.actualSales['selling_months']
          : row.sellingMonths,
    'store' => row.storeStock,
    'online_stock' => row.displayedStock,
    'other_branch_stock' => row.otherBranchStock,
    'stock_cover' => row.stockCoverDays,
    'availability' => row.availability,
    'stocked_branches' => row.stockedBranches,
    'days' => row.stockedDays,
    'supply' => row.supply,
    'reason' => onlinePlainReason(row),
    'action' => row.action,
    'supplier' => row.item.text('supplier'),
    'category' => row.item.text('category'),
    'ingredient' => row.item.text('main_ingredient'),
    'created' => stockItemAddedDate(row.item.data['added_date_time']),
    'audit' => row.stockedDays == null ? 'Check history' : 'Checked',
    _ => null,
  };

  void replace(List<OnlineOverviewRow> rows) {
    if (rows.isNotEmpty) actualSales = rows.any((row) => row.usesActualSales);
    _identity.clear();
    _positions.clear();
    _rows = [
      for (final row in rows)
        _preparedGridRows[row] ??= DataGridRow(
          cells: [
            for (final column in columns)
              DataGridCell<dynamic>(
                columnName: column.$1,
                value: _value(row, column.$1),
              ),
          ],
        ),
    ];
    for (var i = 0; i < rows.length; i++) {
      _identity[_rows[i]] = rows[i];
      _positions[_rows[i]] = i;
    }
    notifyListeners();
  }

  @override
  List<DataGridRow> get rows => _rows;
  OnlineOverviewRow itemFor(DataGridRow row) => _identity[row]!;
  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final item = _identity[row]!;
    final color = onlineRankColor(item.rank);
    return DataGridRowAdapter(
      color: item.rank == OnlineRank.m
          ? const Color(0xFFFFFAF4)
          : _positions[row]!.isEven
          ? Colors.white
          : const Color(0xFFFAFBFE),
      cells: [
        for (final cell in row.getCells())
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            alignment: cell.columnName == 'product'
                ? Alignment.centerLeft
                : Alignment.center,
            child: DefaultTextStyle.merge(
              textAlign: cell.columnName == 'product'
                  ? TextAlign.start
                  : TextAlign.center,
              child: switch (cell.columnName) {
                'rank' => Tooltip(
                  message:
                      '${onlinePriorityLabel(item)}. ${onlinePlainReason(item)}',
                  child: CatalogPill(item.rank.label, color: color),
                ),
                'purchase_status' => CatalogPill(
                  onlinePurchaseLabel(item.purchaseStatus),
                  color: catalogPurple,
                ),
                'created' => Text(
                  formatStockItemAddedDate(item.item.data['added_date_time']),
                  style: const TextStyle(color: catalogInk, fontSize: 13),
                ),
                'online_stock' => Tooltip(
                  message: onlineStockNote(item),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        item.displayedStock == null
                            ? 'Unknown'
                            : catalogQty(item.displayedStock),
                        style: const TextStyle(
                          color: catalogTeal,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (item.partialStock) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Partial total',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: catalogOrange,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                'availability' => Tooltip(
                  message: '${item.availability}. ${onlineStockNote(item)}.',
                  child: CatalogPill(
                    item.availability,
                    color:
                        item.branchesWithStock == null || item.reportCount == 0
                        ? catalogMuted
                        : item.branchesWithStock == item.branchNames.length
                        ? catalogTeal
                        : catalogOrange,
                  ),
                ),
                'stock_cover' => Center(
                  child: OnlineStockCoverBar(
                    days: cell.value as double?,
                    note: onlineStockCoverNote(item),
                  ),
                ),
                'product' => InkWell(
                  onTap: () => onOpen(item),
                  child: Tooltip(
                    message: '${item.item.name}\n${item.item.code}',
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: catalogInk,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          item.item.code,
                          style: const TextStyle(
                            color: catalogMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                'audit' => TextButton.icon(
                  onPressed: () => onAudit(item),
                  icon: const Icon(Icons.fact_check_outlined, size: 16),
                  label: const Text('Check', style: TextStyle(fontSize: 12)),
                ),
                _ => Tooltip(
                  message: '${cell.value ?? 'Unknown / not checked'}',
                  child: Text(
                    cell.value == null
                        ? '—'
                        : cell.value is num
                        ? NumberFormat('#,##0.##').format(cell.value)
                        : '${cell.value}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: cell.value is num ? 16 : 14,
                      fontWeight: cell.value is num
                          ? FontWeight.w800
                          : FontWeight.w500,
                      color: switch (cell.columnName) {
                        'value' ||
                        'other_branch_stock' ||
                        'online_stock' ||
                        'forecast_value' => catalogTeal,
                        'forecast_qty' => catalogBlue,
                        'sales26' || 'recent' => catalogBlue,
                        'sales25' || 'retail' => catalogPurple,
                        _ => catalogInk,
                      },
                    ),
                  ),
                ),
              },
            ),
          ),
      ],
    );
  }
}

class OnlineOverviewGrid extends StatefulWidget {
  final OnlineOverviewGridSource source;
  final VoidCallback onFiltersChanged;
  const OnlineOverviewGrid({
    super.key,
    required this.source,
    required this.onFiltersChanged,
  });
  @override
  State<OnlineOverviewGrid> createState() => _OnlineOverviewGridState();
}

class _OnlineOverviewGridState extends State<OnlineOverviewGrid> {
  final _scroll = ScrollController();
  final _widths = <String, double>{};
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) => SfDataGridTheme(
      data: SfDataGridThemeData(
        headerColor: const Color(0xFFF0F4FC),
        gridLineColor: const Color(0xFFD7E2F0),
        frozenPaneLineColor: const Color(0xFFBDCCE0),
        frozenPaneLineWidth: 1,
        selectionColor: Colors.transparent,
        filterIconColor: AppColors.primaryColor,
        filterIconHoverColor: AppColors.primaryColor,
        sortIconColor: AppColors.primaryColor,
        filterPopupBackgroundColor: Colors.white,
        filterPopupTextStyle: const TextStyle(color: catalogInk, fontSize: 13),
        filterPopupIconColor: AppColors.primaryColor,
        filterPopupInputBorderColor: AppColors.primaryColor,
        filterPopupCheckColor: Colors.white,
        filterPopupCheckboxFillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primaryColor
              : Colors.white,
        ),
        okFilteringLabelButtonColor: AppColors.primaryColor,
        okFilteringLabelColor: Colors.white,
        cancelFilteringLabelButtonColor: Colors.white,
        cancelFilteringLabelColor: AppColors.primaryColor,
        searchAreaFocusedBorderColor: AppColors.primaryColor,
        searchAreaCursorColor: AppColors.primaryColor,
        filterPopupTopDividerColor: const Color(0xFFE8EEF7),
        filterPopupBottomDividerColor: const Color(0xFFE8EEF7),
      ),
      child: SfDataGrid(
        key: const ValueKey('online-overview-grid'),
        source: widget.source,
        horizontalScrollController: _scroll,
        isScrollbarAlwaysShown: true,
        allowColumnsResizing: true,
        allowSorting: true,
        allowMultiColumnSorting: true,
        allowFiltering: true,
        rowHeight: 88 * MediaQuery.textScalerOf(context).scale(1),
        headerRowHeight: 60 * MediaQuery.textScalerOf(context).scale(1),
        frozenColumnsCount: size.maxWidth >= 1000 ? 2 : 0,
        gridLinesVisibility: GridLinesVisibility.both,
        headerGridLinesVisibility: GridLinesVisibility.both,
        onFilterChanged: (_) => widget.onFiltersChanged(),
        onColumnSortChanged: (_, _) => widget.onFiltersChanged(),
        onColumnResizeUpdate: (details) {
          setState(() => _widths[details.column.columnName] = details.width);
          return true;
        },
        onCellTap: (details) {
          final index = details.rowColumnIndex.rowIndex - 1;
          final column = details.rowColumnIndex.columnIndex;
          if (index >= 0 &&
              index < widget.source.effectiveRows.length &&
              column >= 0 &&
              column < OnlineOverviewGridSource.columns.length &&
              OnlineOverviewGridSource.columns[column].$1 != 'audit' &&
              OnlineOverviewGridSource.columns[column].$1 != 'product') {
            widget.source.onOpen(
              widget.source.itemFor(widget.source.effectiveRows[index]),
            );
          }
        },
        placeholder: const Center(
          child: Text(
            'No products match these filters.',
            style: TextStyle(color: catalogMuted),
          ),
        ),
        columns: [
          for (final column in OnlineOverviewGridSource.columns)
            GridColumn(
              columnName: column.$1,
              visible: column.$1 != 'days' && column.$1 != 'value',
              width:
                  _widths[column.$1] ??
                  (size.maxWidth < 600
                      ? switch (column.$1) {
                          'rank' => 76,
                          'product' => 157,
                          'online_stock' => 105,
                          _ => column.$3,
                        }
                      : column.$3),
              allowFiltering:
                  column.$1 != 'audit' &&
                  (size.maxWidth >= 600 ||
                      !const {
                        'rank',
                        'product',
                        'online_stock',
                      }.contains(column.$1)),
              allowSorting: column.$1 != 'audit',
              label: Container(
                alignment: column.$1 == 'product'
                    ? Alignment.centerLeft
                    : Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  size.maxWidth < 600
                      ? switch (column.$1) {
                          'rank' => 'Rank',
                          'online_stock' => 'Stock',
                          _ => widget.source.columnTitle(column.$1, column.$2),
                        }
                      : widget.source.columnTitle(column.$1, column.$2),
                  textAlign: column.$1 == 'product'
                      ? TextAlign.start
                      : TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: catalogInk,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
