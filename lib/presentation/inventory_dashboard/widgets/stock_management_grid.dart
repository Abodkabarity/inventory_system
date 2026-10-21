import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../domain/entities/stock_management.dart';
import '../../../core/utils/stock_item_added_date.dart';
import 'stock_expiry_grid.dart' show expiryRemainingLabel;
import 'stock_management_formatters.dart';
import 'stock_selectable_cell_text.dart';
import 'stock_sales_summary.dart';

const _ink = Color(0xFF142C40);
const _muted = Color(0xFF64748B);
const _teal = Color(0xFF008A83);
const _red = Color(0xFFC63E55);
const _amber = Color(0xFFB76C06);
const _line = Color(0xFFE9E2D8);
final _number = NumberFormat('#,##0.##');
String _qty(dynamic value) => _number.format(stockNumber(value));
String _date(DateTime? value) =>
    value == null ? '—' : DateFormat('dd MMM yyyy').format(value);
DateTime? _calendarDate(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed == null
      ? null
      : DateTime.utc(parsed.year, parsed.month, parsed.day);
}

DateTime _dubaiToday() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 4));
  return DateTime.utc(now.year, now.month, now.day);
}

DateTime _sixMonthsAfter(DateTime today) {
  final year = today.year + (today.month + 5) ~/ 12;
  final month = (today.month + 5) % 12 + 1;
  final end = DateTime.utc(year, month + 1, 0).day;
  return DateTime.utc(year, month, math.min(today.day, end));
}

/// An MRN expiry is historical receipt information; it is not a batch-stock
/// balance. Only dates strictly before the six-calendar-month boundary alert.
bool stockMrnExpiryIsNear(DateTime? expiry, DateTime today) =>
    expiry != null &&
    DateTime.utc(
      expiry.year,
      expiry.month,
      expiry.day,
    ).isBefore(_sixMonthsAfter(today));

class StockManagementGrid extends StatefulWidget {
  final List<StockManagementItem> items;
  final ScrollController horizontalController;
  final ValueChanged<StockManagementItem> onOpen;
  final void Function(int visible, bool filtered) onViewChanged;
  const StockManagementGrid({
    super.key,
    required this.items,
    required this.horizontalController,
    required this.onOpen,
    required this.onViewChanged,
  });

  @override
  State<StockManagementGrid> createState() => StockManagementGridState();
}

class StockManagementGridState extends State<StockManagementGrid> {
  late final StockManagementGridSource source;
  List<StockManagementItem> get visibleItems => [
    for (final row in source.effectiveRows) source.itemFor(row),
  ];
  final _widths = <String, double>{};
  @override
  void initState() {
    super.initState();
    source = StockManagementGridSource(
      widget.items,
      onOpen: (item) => widget.onOpen(item),
    );
    _publishCount();
  }

  @override
  void didUpdateWidget(covariant StockManagementGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.items, oldWidget.items)) {
      source.update(widget.items);
      _publishCount();
    }
  }

  void clearFilters() {
    source.clearFilters();
    _publishCount();
  }

  void _publishCount() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onViewChanged(
          source.effectiveRows.length,
          source.filterConditions.isNotEmpty,
        );
      }
    });
  }

  @override
  void dispose() {
    source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) => SfDataGridTheme(
      data: SfDataGridThemeData(
        headerColor: const Color(0xFFFAF3E8),
        gridLineColor: _line,
        selectionColor: Colors.transparent,
        sortIconColor: _teal,
        filterIconColor: _teal,
        filterIconHoverColor: _teal,
        filterPopupBackgroundColor: const Color(0xFFFFFDF9),
        filterPopupTextStyle: const TextStyle(color: _ink, fontSize: 14),
        filterPopupIconColor: _teal,
        filterPopupInputBorderColor: _teal,
        filterPopupCheckColor: Colors.white,
        filterPopupCheckboxFillColor: const WidgetStatePropertyAll(_teal),
      ),
      child: SfDataGrid(
        key: const ValueKey('overview-excel-grid'),
        source: source,
        horizontalScrollController: widget.horizontalController,
        allowFiltering: true,
        allowSorting: true,
        allowMultiColumnSorting: true,
        allowColumnsResizing: true,
        columnWidthMode: ColumnWidthMode.none,
        frozenColumnsCount: size.maxWidth >= 650 ? 1 : 0,
        gridLinesVisibility: GridLinesVisibility.both,
        headerGridLinesVisibility: GridLinesVisibility.both,
        isScrollbarAlwaysShown: true,
        rowHeight: math.max(88, 88 * MediaQuery.textScalerOf(context).scale(1)),
        headerRowHeight: 52,
        onColumnResizeUpdate: (details) {
          setState(() => _widths[details.column.columnName] = details.width);
          return true;
        },
        onFilterChanged: (_) => _publishCount(),
        onCellTap: (details) {
          final index = details.rowColumnIndex.rowIndex - 1;
          if (index < 0 || index >= source.effectiveRows.length) return;
          widget.onOpen(source.itemFor(source.effectiveRows[index]));
        },
        columns: StockManagementGridSource.columns
            .map(
              (c) => GridColumn(
                columnName: c.$1,
                width: _widths[c.$1] ?? c.$3,
                minimumWidth: c.$1 == 'item_name' ? 240 : 100,
                label: Container(
                  alignment: c.$1 == 'item_name' || c.$1.startsWith('sales_')
                      ? Alignment.center
                      : Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Tooltip(
                    message: '${c.$2} · Excel filter & sort',
                    child: Text(
                      c.$2,
                      textAlign:
                          c.$1 == 'item_name' || c.$1.startsWith('sales_')
                          ? TextAlign.center
                          : TextAlign.start,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF705B49),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    ),
  );
}

class StockManagementGridSource extends DataGridSource {
  static const columns = <(String, String, double)>[
    ('item_name', 'PRODUCT / SUPPLIER', 350),
    ('last_mrn_date', 'MRN date', 175),
    ('expiry_date', 'Expiry date', 200),
    ('ordered_quantity', 'Ordered Qty', 150),
    ('received_quantity', 'Received Qty', 155),
    ('vendor', 'Vendor', 160),
    ('store_stock', 'Store', 115),
    ('branches_stock', 'Branches', 140),
    ('total_stock', 'Total stock', 155),
    ('store_total_percent', 'Store / Total stock', 180),
    ('days_on_hand', 'Days on hand', 175),
    ('sales_2025', '2025 sales · qty', 300),
    ('sales_2026', '2026 sales · qty', 300),
    ('best_months', 'Best month · 25 / 26', 235),
    ('item_code', 'Item code', 150),
    ('added_date_time', 'Created date', 160),
    ('supplier', 'SUPPLIER', 250),
    ('company', 'COMPANY', 220),
    ('category', 'CATEGORY', 190),
    ('stock_status', 'Stock status', 175),
  ];
  List<DataGridRow> _rows = [];
  final ValueChanged<StockManagementItem> onOpen;
  final _items = <DataGridRow, StockManagementItem>{};
  final _indexes = <DataGridRow, int>{};
  StockManagementGridSource(
    List<StockManagementItem> items, {
    required this.onOpen,
  }) {
    _replaceRows(items);
  }

  StockManagementItem itemFor(DataGridRow row) => _items[row]!;
  void _replaceRows(List<StockManagementItem> items) {
    _items.clear();
    _indexes.clear();
    _rows = [
      for (var index = 0; index < items.length; index++)
        DataGridRow(
          cells: [
            for (final c in columns)
              DataGridCell<dynamic>(
                columnName: c.$1,
                value: _value(items[index], c.$1),
              ),
          ],
        ),
    ];
    for (var index = 0; index < _rows.length; index++) {
      _items[_rows[index]] = items[index];
      _indexes[_rows[index]] = index;
    }
  }

  void update(List<StockManagementItem> items) {
    _replaceRows(items);
    notifyListeners();
  }

  @override
  List<DataGridRow> get rows => _rows;

  dynamic _value(StockManagementItem item, String key) => switch (key) {
    'item_name' => item.name.toUpperCase(),
    'last_mrn_date' || 'expiry_date' => _calendarDate(item.text(key)),
    'item_code' => item.text(key),
    'added_date_time' => stockItemAddedDate(item.data[key]),
    'supplier' || 'company' || 'category' => item.text(key).toUpperCase(),
    'stock_status' => item.status,
    'ordered_quantity' || 'received_quantity' => item.number(key),
    'total_stock' || 'store_stock' || 'branches_stock' => item.number(key),
    'vendor' => formatStockVendor(item.data['vendor']),
    'store_total_percent' => item.storeTotalPercent,
    'days_on_hand' => item.days,
    'sales_2025' || 'sales_2026' =>
      item.year(key.endsWith('2025') ? 2025 : 2026)['total'] == null
          ? null
          : stockNumber(item.year(key.endsWith('2025') ? 2025 : 2026)['total']),
    'best_months' =>
      '${item.year(2025)['best_month'] ?? ''} · ${item.year(2026)['best_month'] ?? ''}',
    _ => null,
  };

  Widget _text(
    String text, {
    Color color = _ink,
    double size = 14,
    bool strong = false,
    int lines = 1,
    Key? key,
  }) => StockSelectableCellText(
    text,
    key: key,
    maxLines: lines,
    style: TextStyle(
      color: color,
      fontSize: size,
      fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
    ),
  );

  Widget _stack(List<Widget> children) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  );

  Widget _badge(Widget child, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(9),
    ),
    child: child,
  );

  Widget _cell(StockManagementItem item, DataGridCell<dynamic> cell) {
    final key = cell.columnName, value = cell.value;
    switch (key) {
      case 'item_name':
        return _stack([
          Tooltip(
            message: value as String,
            child: _text(value, strong: true, size: 15, lines: 2),
          ),
          const SizedBox(height: 3),
          StockSelectableCellText.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: item.code,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(text: ' · ${item.text('supplier').toUpperCase()}'),
              ],
            ),
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
          ),
        ]);
      case 'added_date_time':
        return _text(formatStockItemAddedDate(item.data[key]), strong: true);
      case 'last_mrn_date':
        return _stack([
          _badge(
            _text(
              _date(value as DateTime?),
              key: ValueKey('mrn-date:${item.code}'),
              strong: true,
              size: 15,
            ),
            _ink,
          ),
          const SizedBox(height: 3),
          _text(
            'Received ${_qty(item.number('last_mrn_qty'))}',
            color: _muted,
            size: 11,
          ),
        ]);
      case 'expiry_date':
        final expiry = value as DateTime?;
        if (expiry == null) {
          return _text('No date on latest MRN', color: _muted, size: 12);
        }
        final today = _dubaiToday();
        final near = stockMrnExpiryIsNear(expiry, today);
        final expired = expiry.isBefore(today);
        final days = expiry.difference(today).inDays;
        final color = near ? _red : _teal;
        return Tooltip(
          message:
              'Earliest expiry recorded in the latest MRN. Confirm current batch stock before acting.',
          child: _badge(
            _stack([
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: _text(
                      _date(expiry),
                      color: color,
                      strong: true,
                      size: 15,
                    ),
                  ),
                  if (near) ...[
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _red,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const StockSelectableCellText(
                        'Expiry',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              _text(
                expired
                    ? 'Expired · ${-days} days ago'
                    : expiryRemainingLabel(
                        daysLeft: days,
                        expiryDate: DateTime(
                          expiry.year,
                          expiry.month,
                          expiry.day,
                        ),
                      ),
                color: near ? _red : _muted,
                size: 12,
                strong: near,
              ),
            ]),
            color,
          ),
        );
      case 'received_quantity':
        return Tooltip(
          message:
              'Quantity received for the displayed expiry date on the latest MRN. It is not the current batch stock.',
          child: _text(_qty(value), strong: true, size: 16),
        );
      case 'ordered_quantity':
        return Tooltip(
          message:
              'Quantity ordered for the displayed expiry date on the latest MRN.',
          child: _text(_qty(value), strong: true, size: 16),
        );
      case 'total_stock':
        final color = item.status == 'no_stock'
            ? _red
            : item.status == 'low_cover'
            ? _amber
            : _teal;
        return Align(
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _text(_qty(value), size: 18, strong: true),
              const SizedBox(height: 4),
              _badge(
                _text(
                  switch (item.status) {
                    'no_stock' => 'No Stock',
                    'low_cover' => 'Below 30 days',
                    'no_sales' => 'No recent sales',
                    _ => 'In stock',
                  },
                  color: color,
                  size: 11,
                  strong: true,
                ),
                color,
              ),
            ],
          ),
        );
      case 'branches_stock':
        return _stack([
          _text(_qty(value), color: _teal, size: 16, strong: true),
          _text(
            '${_qty(item.number('stocked_branches'))} stocked',
            color: _muted,
            size: 11,
          ),
        ]);
      case 'store_stock':
        return _text(
          _qty(value),
          color: const Color(0xFF4169D8),
          size: 16,
          strong: true,
        );
      case 'store_total_percent':
        return _text(formatStockPercentage(value is num ? value : null));
      case 'days_on_hand':
        return _text(
          item.status == 'no_stock'
              ? 'No stock'
              : value == null
              ? 'No recent sales'
              : '${_qty(value)} days',
          color: item.status == 'low_cover' ? _amber : _teal,
          strong: true,
        );
      case 'sales_2025':
      case 'sales_2026':
        return StockSalesSummary(
          data: item.year(key.endsWith('2025') ? 2025 : 2026),
          totalColor: _ink,
        );
      case 'best_months':
        final y25 = item.year(2025), y26 = item.year(2026);
        return _stack([
          _text('2025 · ${y25['best_month'] ?? '—'}', strong: true),
          _text('2026 · ${y26['best_month'] ?? '—'}', strong: true),
        ]);
      default:
        return Tooltip(
          message: value?.toString() ?? 'Unavailable',
          child: _text(value?.toString() ?? '—'),
        );
    }
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final item = itemFor(row);
    final expiry = _calendarDate(item.text('expiry_date'));
    final near = stockMrnExpiryIsNear(expiry, _dubaiToday());
    final alternate = (_indexes[row] ?? 0).isOdd;
    final tint = near ? _red : _teal;
    return DataGridRowAdapter(
      color: Color.alphaBlend(
        tint.withValues(
          alpha: near ? (alternate ? .075 : .045) : (alternate ? .025 : 0),
        ),
        Colors.white,
      ),
      cells: [
        for (final cell in row.getCells())
          Container(
            decoration: cell.columnName == 'item_name' && near
                ? const BoxDecoration(
                    border: Border(left: BorderSide(color: _red, width: 3)),
                  )
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: cell.columnName == 'item_name'
                ? Alignment.centerLeft
                : Alignment.center,
            child: StockCellTapScope(
              onTap: () => onOpen(item),
              child: _cell(item, cell),
            ),
          ),
      ],
    );
  }
}
