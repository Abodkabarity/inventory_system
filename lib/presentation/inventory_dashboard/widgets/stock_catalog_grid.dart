import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/stock_item_added_date.dart';
import '../../../domain/entities/stock_management.dart';
import '../../../domain/entities/stock_catalog.dart';
import 'stock_catalog_visuals.dart';
import 'stock_sales_summary.dart';

class StockCatalogGrid extends StatefulWidget {
  final List<StockCatalogItem> items;
  final ValueChanged<StockCatalogItem> onOpen;
  final void Function(List<StockCatalogItem> rows, bool filtered)?
  onViewChanged;
  const StockCatalogGrid({
    super.key,
    required this.items,
    required this.onOpen,
    this.onViewChanged,
  });
  @override
  State<StockCatalogGrid> createState() => StockCatalogGridState();
}

class StockCatalogGridState extends State<StockCatalogGrid> {
  late final _CatalogGridSource _source;
  final _scroll = ScrollController();
  final _widths = <String, double>{};
  bool _viewScheduled = false;
  List<StockCatalogItem> get visibleItems => [
    for (final row in _source.effectiveRows) _source.itemFor(row),
  ];
  void clearFilters() {
    _source.clearFilters();
    _publishView();
  }

  void clearSorting() {
    _source.sortedColumns.clear();
    _source.sort();
    _publishView();
  }

  void _publishView() {
    if (_viewScheduled) return;
    _viewScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewScheduled = false;
      if (mounted) {
        widget.onViewChanged?.call(
          visibleItems,
          _source.filterConditions.isNotEmpty,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _source = _CatalogGridSource(widget.items);
    _publishView();
  }

  @override
  void didUpdateWidget(covariant StockCatalogGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items)) {
      _source.update(widget.items);
      _publishView();
    }
  }

  @override
  void dispose() {
    _source.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) => SfDataGridTheme(
      data: SfDataGridThemeData(
        headerColor: const Color(0xFFF0F4FC),
        gridLineColor: const Color(0xFFE8EEF7),
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
        key: const ValueKey('stock-catalog-grid'),
        source: _source,
        horizontalScrollController: _scroll,
        isScrollbarAlwaysShown: true,
        allowColumnsResizing: true,
        allowFiltering: true,
        allowSorting: true,
        allowMultiColumnSorting: true,
        onFilterChanged: (_) => _publishView(),
        onColumnSortChanged: (_, _) => _publishView(),
        placeholder: const Center(
          child: Text(
            'No products match these filters.',
            style: TextStyle(color: catalogMuted),
          ),
        ),
        frozenColumnsCount: size.maxWidth >= 780 ? 1 : 0,
        headerRowHeight: 54,
        rowHeight: 88 * MediaQuery.textScalerOf(context).scale(1),
        gridLinesVisibility: GridLinesVisibility.horizontal,
        headerGridLinesVisibility: GridLinesVisibility.both,
        onColumnResizeUpdate: (d) {
          setState(() => _widths[d.column.columnName] = d.width);
          return true;
        },
        onCellTap: (d) {
          final i = d.rowColumnIndex.rowIndex - 1;
          if (i >= 0 && i < _source.effectiveRows.length) {
            widget.onOpen(_source.itemFor(_source.effectiveRows[i]));
          }
        },
        columns: [
          for (final c in _CatalogGridSource.columns)
            GridColumn(
              columnName: c.$1,
              width: _widths[c.$1] ?? c.$3,
              minimumWidth: 100,
              filterIconPadding: const EdgeInsets.symmetric(horizontal: 6),
              label: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Align(
                  alignment: c.$1 == 'product'
                      ? Alignment.centerLeft
                      : Alignment.center,
                  child: Tooltip(
                    message: c.$4,
                    child: Text(
                      c.$2,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: catalogInk,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _CatalogGridSource extends DataGridSource {
  List<DataGridRow> _rows = [];
  final _identity = <DataGridRow, StockCatalogItem>{};
  final _positions = <DataGridRow, int>{};
  static const columns = [
    (
      'product',
      'PRODUCT',
      340.0,
      'Product identity. Open any row for details.',
    ),
    ('item_status', 'ITEM STATUS', 200.0, 'Product purchase status.'),
    (
      'added_date_time',
      'CREATED DATE',
      160.0,
      'Product created date (day/month/year).',
    ),
    (
      'status',
      'STATUS',
      165.0,
      'Purple: ≥2× daily demand and ≥3 recent Qty, or new demand. Red: 45-day sales exceed stock.',
    ),
    (
      'branches_stock',
      'BRANCHES STOCK',
      155.0,
      'All active registered branches. STORE is excluded.',
    ),
    ('store_stock', 'STORE STOCK', 145.0, 'Current STORE warehouse balance.'),
    ('apg_stock', 'APG STOCK', 145.0, 'APG stock balance including STORE.'),
    (
      'total_stock',
      'TOTAL STOCK',
      150.0,
      'STORE + all active branches. Do not add APG again.',
    ),
    (
      'cover',
      'STOCK COVER',
      175.0,
      'Filter in days: total stock ÷ 45-day daily net sales. Months use 30 days.',
    ),
    ('ratio', 'STORE / TOTAL STOCK', 180.0, 'STORE stock ÷ total stock × 100.'),
    (
      'sales_2025',
      'SALES 2025',
      285.0,
      'Net Qty across Cash, Insurance and Online, all source branches.',
    ),
    (
      'sales_2026',
      'SALES 2026',
      285.0,
      'Uploaded 2026 net Qty, all source branches. May be partial.',
    ),
    (
      'last_3_sales',
      'LAST 3 DAYS',
      145.0,
      'Net Qty in the latest three calendar days ending on uploaded sales date.',
    ),
    (
      'recent_sales',
      'SALES 45D',
      155.0,
      'Total net Qty across the latest 45-day sales window, including returns.',
    ),
    (
      'reorder_branches',
      'REORDER BRANCHES',
      165.0,
      'Eligible branches with requested reorder quantity.',
    ),
    (
      'final_order_branches',
      'FINAL ORDER BRANCHES',
      175.0,
      'Eligible branches with planned final-order quantity, not confirmed delivery.',
    ),
    ('category', 'CATEGORY', 190.0, 'Product category.'),
    ('supplier', 'SUPPLIER', 250.0, 'Product supplier.'),
    ('main_ingredient', 'INGREDIENT', 260.0, 'Main ingredient.'),
    ('indication', 'INDICATION', 300.0, 'Product indication.'),
    ('sub_category', 'SUB-CATEGORY', 200.0, 'Product sub-category.'),
  ];
  _CatalogGridSource(List<StockCatalogItem> items) {
    _replaceRows(items);
  }
  StockCatalogItem itemFor(DataGridRow row) => _identity[row]!;
  void update(List<StockCatalogItem> items) {
    _replaceRows(items);
    notifyListeners();
  }

  dynamic _value(StockCatalogItem item, String column) => switch (column) {
    'product' => item.name,
    'item_status' => item.itemStatus,
    'category' ||
    'supplier' ||
    'main_ingredient' ||
    'indication' ||
    'sub_category' => item.text(column),
    'added_date_time' => stockItemAddedDate(item.data['added_date_time']),
    'reorder_branches' =>
      item.distributionStatus.orderDataAvailable
          ? item.distributionStatus.reorder
          : null,
    'final_order_branches' =>
      item.distributionStatus.orderDataAvailable
          ? item.distributionStatus.finalOrders
          : null,
    'status' => item.signal,
    'cover' => item.days,
    'ratio' => item.storeTotalPercent,
    'sales_2025' || 'sales_2026' => stockNumber(
      item.year(column == 'sales_2025' ? 2025 : 2026)['total'],
    ),
    _ => item.number(column),
  };
  void _replaceRows(List<StockCatalogItem> items) {
    _identity.clear();
    _positions.clear();
    _rows = [
      for (final item in items)
        DataGridRow(
          cells: [
            for (final c in columns)
              DataGridCell<dynamic>(
                columnName: c.$1,
                value: _value(item, c.$1),
              ),
          ],
        ),
    ];
    for (var i = 0; i < _rows.length; i++) {
      _identity[_rows[i]] = items[i];
      _positions[_rows[i]] = i;
    }
  }

  @override
  List<DataGridRow> get rows => _rows;
  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final item = _identity[row]!;
    final color = catalogSignalColor(item);
    return DataGridRowAdapter(
      color: item.distributionStatus.needsDistribution
          ? const Color(0xFFFFF7ED)
          : item.surge || item.newDemand
          ? const Color(0xFFF6F0FF)
          : item.salesExceedStock
          ? const Color(0xFFFFF5F7)
          : _positions[row]!.isEven
          ? Colors.white
          : const Color(0xFFFAFCFF),
      cells: [
        for (final c in columns)
          Container(
            alignment: c.$1 == 'product'
                ? Alignment.centerLeft
                : Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: switch (c.$1) {
              'category' ||
              'supplier' ||
              'main_ingredient' ||
              'indication' ||
              'sub_category' => Tooltip(
                message: item.text(c.$1),
                child: Text(
                  item.text(c.$1).isEmpty ? '—' : item.text(c.$1),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: catalogInk,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              'product' => Row(
                children: [
                  Container(
                    width: 4,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: catalogInk,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.code}  ·  ${item.text('company')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: catalogMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: catalogMuted,
                    size: 18,
                  ),
                ],
              ),
              'status' => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Tooltip(
                    message: item.signal,
                    child: CatalogPill(item.signal, color: color),
                  ),
                  if ((item.surge || item.newDemand) && item.salesExceedStock)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Sales > stock',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: catalogRose,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              'reorder_branches' || 'final_order_branches' => Tooltip(
                message: item.distributionStatus.orderDataAvailable
                    ? '${item.distributionStatus.known ? 'Complete' : 'Partial'} Daily Order data • ${stockMap(item.data['distribution'])['run_date']}'
                    : 'Current Daily Order data unavailable',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _value(item, c.$1) == null
                          ? '—'
                          : '${_value(item, c.$1)}',
                      style: const TextStyle(
                        color: catalogInk,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (item.distributionStatus.orderDataAvailable) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Qty ${catalogQty(c.$1 == 'reorder_branches' ? item.distributionStatus.reorderQuantity : item.distributionStatus.finalQuantity)}${item.distributionStatus.known ? '' : ' · partial'}',
                        style: const TextStyle(
                          color: catalogMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              'added_date_time' => Text(
                formatStockItemAddedDate(item.data['added_date_time']),
                style: const TextStyle(
                  color: catalogInk,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              'item_status' => Tooltip(
                message: item.itemStatus.isEmpty
                    ? 'Not specified'
                    : item.itemStatus,
                child: Text(
                  item.itemStatus.isEmpty ? '—' : item.itemStatus,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: catalogInk,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              'cover' => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    catalogCover(item),
                    style: TextStyle(
                      color: item.days != null && item.days! < 30
                          ? catalogRose
                          : catalogTeal,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: 100,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: LinearProgressIndicator(
                        value: item.days == null
                            ? 0
                            : (item.days! / 90).clamp(0, 1),
                        minHeight: 5,
                        color: item.days != null && item.days! < 30
                            ? catalogRose
                            : catalogTeal,
                        backgroundColor: const Color(0xFFE9EFF7),
                      ),
                    ),
                  ),
                ],
              ),
              'ratio' => Text(
                item.storeTotalPercent == null
                    ? '—'
                    : '${item.storeTotalPercent!.toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: catalogBlue,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              'sales_2025' => StockSalesSummary(
                data: item.year(2025),
                totalColor: catalogBlue,
              ),
              'sales_2026' => StockSalesSummary(
                data: item.year(2026),
                totalColor: catalogTeal,
              ),
              _ => Text(
                catalogQty(item.number(c.$1)),
                style: TextStyle(
                  color:
                      c.$1 == 'last_3_sales' && (item.surge || item.newDemand)
                      ? catalogPurple
                      : catalogInk,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            },
          ),
      ],
    );
  }
}
