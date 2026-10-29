import '../../../domain/entities/stock_supply_insight.dart';
import 'stock_supply_insight_widgets.dart';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import '../../../domain/entities/stock_expiry.dart';
import '../../../core/utils/stock_item_added_date.dart';
import 'stock_management_formatters.dart';
import 'stock_selectable_cell_text.dart';
import 'stock_sales_summary.dart';
import 'stock_receipt_quantity.dart';

const _ink = Color(0xFF142C40),
    _muted = Color(0xFF64748B),
    _teal = Color(0xFF008A83),
    _line = Color(0xFFE9E2D8);

/// Uses calendar months rather than dividing by 30. This keeps the label
/// natural: an expiry on 01 Dec from 08 Oct reads "1 month · 23 days left".
String expiryRemainingLabel({
  required int daysLeft,
  required DateTime? expiryDate,
}) {
  if (daysLeft < 0) return '${-daysLeft} days overdue';
  if (daysLeft == 0) return 'Expires today';
  if (daysLeft < 31 || expiryDate == null) return '$daysLeft days left';

  final start = DateTime(
    expiryDate.year,
    expiryDate.month,
    expiryDate.day,
  ).subtract(Duration(days: daysLeft));
  var months =
      (expiryDate.year - start.year) * 12 + expiryDate.month - start.month;
  while (months > 0 && _addMonths(start, months).isAfter(expiryDate)) {
    months--;
  }
  if (months == 0) return '$daysLeft days left';
  final calendarAnchor = _addMonths(start, months);
  final remainingDays = expiryDate.difference(calendarAnchor).inDays;
  final monthLabel = '$months ${months == 1 ? 'month' : 'months'}';
  if (remainingDays == 0) return '$monthLabel left';
  return '$monthLabel · $remainingDays days left';
}

DateTime _addMonths(DateTime date, int months) {
  final totalMonths = date.year * 12 + date.month - 1 + months;
  final year = totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, math.min(date.day, lastDay));
}

/// The same Syncfusion grid engine used by Inventory Daily Order. Values stay
/// typed (dates/numbers/text) so Excel-style filters and sorting remain correct.
class StockExpiryGrid extends StatefulWidget {
  final bool readOnly;
  final List<StockExpiryAlert> alerts;
  final Set<String> busy, fading;
  final ScrollController horizontalController;
  final ValueChanged<StockExpiryAlert> onOpen, onReview;
  final Color Function(StockExpiryAlert) riskColor;
  final void Function(int visible, bool filtered) onViewChanged;
  const StockExpiryGrid({
    super.key,
    this.readOnly = false,
    required this.alerts,
    required this.busy,
    required this.fading,
    required this.horizontalController,
    required this.onOpen,
    required this.onReview,
    required this.riskColor,
    required this.onViewChanged,
  });
  @override
  State<StockExpiryGrid> createState() => StockExpiryGridState();
}

class StockExpiryGridState extends State<StockExpiryGrid> {
  late final StockExpiryGridSource source;
  List<StockExpiryAlert> get visibleAlerts => [
    for (final row in source.effectiveRows) source.alertFor(row),
  ];
  final _widths = <String, double>{};
  @override
  void initState() {
    super.initState();
    source = StockExpiryGridSource(
      readOnly: widget.readOnly,
      alerts: widget.alerts,
      busy: widget.busy,
      fading: widget.fading,
      onOpen: (a) => widget.onOpen(a),
      onReview: (a) => widget.onReview(a),
      riskColor: (a) => widget.riskColor(a),
    );
    _publishCount();
  }

  @override
  void didUpdateWidget(covariant StockExpiryGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.alerts, oldWidget.alerts) ||
        !setEquals(widget.busy, oldWidget.busy) ||
        !setEquals(widget.fading, oldWidget.fading)) {
      source.update(widget.alerts, widget.busy, widget.fading);
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
        key: const ValueKey('expiry-excel-grid'),
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
        rowHeight: math.max(78, 78 * MediaQuery.textScalerOf(context).scale(1)),
        headerRowHeight: 52,
        onColumnResizeUpdate: (details) {
          setState(() => _widths[details.column.columnName] = details.width);
          return true;
        },
        onFilterChanged: (_) => _publishCount(),
        onCellTap: (details) {
          final index = details.rowColumnIndex.rowIndex - 1;
          if (index < 0 || index >= source.effectiveRows.length) return;
          final column = details.column.columnName;
          // Action buttons own their gestures; never also open a second dialog.
          if (column == 'note') return;
          widget.onOpen(source.alertFor(source.effectiveRows[index]));
        },
        columns: StockExpiryGridSource.columns
            .map(
              (c) => GridColumn(
                columnName: c.$1,
                width: _widths[c.$1] ?? c.$3,
                minimumWidth: c.$1 == 'note'
                    ? 220
                    : c.$1 == 'item_name'
                    ? 240
                    : c.$1 == 'sales_2025' || c.$1 == 'sales_2026'
                    ? 260
                    : 100,
                label: Container(
                  alignment:
                      c.$1 == 'item_name' ||
                          c.$1 == 'sales_2025' ||
                          c.$1 == 'sales_2026'
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
                          c.$1 == 'item_name' ||
                              c.$1 == 'sales_2025' ||
                              c.$1 == 'sales_2026'
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

class StockExpiryGridSource extends DataGridSource {
  final bool readOnly;
  static const columns = <(String, String, double)>[
    ('item_name', 'PRODUCT / SUPPLIER', 340),
    ('reference', 'Reference', 190),
    ('last_receipt_date', 'MRN date', 175),
    ('expiry_date', 'Expiry date', 160),
    ('ordered_qty', 'Ordered Qty', 150),
    ('received_qty', 'Total Qty', 190),
    ('vendor', 'Vendor', 160),
    ('note', 'Note / review', 250),
    ('store_stock', 'Store stock', 125),
    ('branches_stock', 'Branches stock', 150),
    ('total_stock', 'Total stock', 145),
    ('supply_review', 'STORE history', 210),
    ('store_total_percent', 'Store / Total stock', 180),
    ('days_on_hand', 'Days on hand', 165),
    ('purchase_status_items', 'Purchase Status', 220),
    ('sales_2025', '2025 sales · qty', 300),
    ('sales_2026', '2026 sales · qty', 300),
    ('best_month_2025', 'Best month · 2025', 185),
    ('best_month_2026', 'Best month · 2026', 185),
    ('item_code', 'Item code', 155),
    ('added_date_time', 'Created date', 160),
    ('supplier', 'SUPPLIER', 250),
    ('company', 'COMPANY', 220),
    ('category', 'CATEGORY', 190),
    ('review_state', 'Review status', 190),
    ('stock_status', 'Stock status', 175),
  ];
  final ValueChanged<StockExpiryAlert> onOpen, onReview;
  final Color Function(StockExpiryAlert) riskColor;
  List<DataGridRow> _rows = [];
  final _alerts = <DataGridRow, StockExpiryAlert>{};
  Set<String> _busy = {}, _fading = {};
  StockExpiryGridSource({
    this.readOnly = false,
    required List<StockExpiryAlert> alerts,
    required Set<String> busy,
    required Set<String> fading,
    required this.onOpen,
    required this.onReview,
    required this.riskColor,
  }) {
    _replaceRows(alerts, busy, fading);
    sortedColumns.add(
      const SortColumnDetails(
        name: 'last_receipt_date',
        sortDirection: DataGridSortDirection.descending,
      ),
    );
    sort();
  }
  StockExpiryAlert alertFor(DataGridRow row) => _alerts[row]!;
  void _replaceRows(
    List<StockExpiryAlert> alerts,
    Set<String> busy,
    Set<String> fading,
  ) {
    _busy = busy;
    _fading = fading;
    _alerts.clear();
    _rows = alerts.map((a) {
      final row = DataGridRow(
        cells: columns
            .map(
              (c) => DataGridCell<dynamic>(
                columnName: c.$1,
                value: _value(a, c.$1),
              ),
            )
            .toList(),
      );
      _alerts[row] = a;
      return row;
    }).toList();
  }

  void update(
    List<StockExpiryAlert> alerts,
    Set<String> busy,
    Set<String> fading,
  ) {
    _replaceRows(alerts, busy, fading);
    notifyListeners();
  }

  @override
  List<DataGridRow> get rows => _rows;

  dynamic _value(StockExpiryAlert a, String key) {
    final p = a.product;
    switch (key) {
      case 'item_name':
        return p.name.toUpperCase();
      case 'item_code':
        return a.code;
      case 'purchase_status_items':
        return p.purchaseStatus;
      case 'reference':
        return a.text(key);
      case 'added_date_time':
        return stockItemAddedDate(p.data[key]);
      case 'supplier':
      case 'company':
      case 'category':
        return p.text(key).toUpperCase();
      case 'last_receipt_date':
        return DateTime.tryParse(a.text(key));
      case 'expiry_date':
        return DateTime.tryParse(a.expiry);
      case 'ordered_qty':
        return _number(a.data[key]);
      case 'received_qty':
        return a.number(a.data.containsKey('total_qty') ? 'total_qty' : key);
      case 'vendor':
        return formatStockVendor(a.data[key]);
      case 'supply_review':
        return StockSupplyInsight.of(p).label;
      case 'note':
        return a.note;
      case 'review_state':
        return a.newReceipts
            ? 'New receipts · review again'
            : a.reviewed
            ? 'Reviewed'
            : 'Awaiting review';
      case 'stock_status':
        return p.stockAvailable ? _status(p.status) : 'No snapshot';
      case 'store_total_percent':
        return p.storeTotalPercent;
      case 'days_on_hand':
        return p.stockAvailable ? p.days : null;
      case 'total_stock':
      case 'store_stock':
      case 'branches_stock':
        return p.stockAvailable ? p.number(key) : null;
      case 'sales_2025':
      case 'sales_2026':
        return _number(p.year(key.endsWith('2025') ? 2025 : 2026)['total']);
      case 'best_month_2025':
      case 'best_month_2026':
        final year = key.endsWith('2025') ? 2025 : 2026;
        final y = p.year(year);
        final parts = y['best_month']?.toString().split('/') ?? [];
        return parts.length == 2
            ? DateTime.tryParse('${parts[1]}-${parts[0].padLeft(2, '0')}-01')
            : null;
      default:
        return null;
    }
  }

  static double? _number(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  static String _qty(dynamic value) =>
      value == null ? '—' : NumberFormat('#,##0.##').format(value);
  static String _date(dynamic value) =>
      value is DateTime ? DateFormat('dd MMM yyyy').format(value) : '—';
  static String _status(String status) => switch (status) {
    'no_stock' => 'No stock',
    'low_cover' => 'Below 30 days',
    'no_sales' => 'No recent sales',
    _ => 'In stock',
  };
  Widget _text(
    String value, {
    Key? key,
    Color color = _ink,
    double size = 14,
    bool strong = false,
    int lines = 1,
  }) => StockSelectableCellText(
    value,
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
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(9),
    ),
    child: child,
  );

  Widget _cell(StockExpiryAlert a, DataGridCell<dynamic> cell) {
    final key = cell.columnName, value = cell.value;
    final p = a.product, risk = riskColor(a);
    switch (key) {
      case 'purchase_status_items':
        return Tooltip(
          message: p.purchaseStatus,
          child: _text(p.purchaseStatus, lines: 3),
        );
      case 'supply_review':
        return StockSupplyReviewCell(item: a.product);
      case 'reference':
        final reference = a.text('reference');
        return Tooltip(
          message: reference,
          child: _text(reference.isEmpty ? '—' : reference, lines: 3),
        );
      case 'item_name':
        return _stack([
          Tooltip(
            message: value as String,
            child: _text(
              value,
              key: ValueKey('expiry-product:${a.key}'),
              strong: true,
              size: 15,
              lines: 2,
            ),
          ),
          const SizedBox(height: 3),
          StockSelectableCellText.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: a.code,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(text: ' · ${p.text('supplier').toUpperCase()}'),
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
      case 'last_receipt_date':
        return Tooltip(
          message:
              'Only receipts on this MRN date with this expiry are included.',
          child: _stack([
            _badge(
              _text(
                _date(value),
                key: ValueKey('mrn-date:${a.key}'),
                strong: true,
                size: 15,
              ),
              _ink,
            ),
            if (a.text('last_receipt_date') != p.text('last_mrn_date'))
              _text(
                'Latest: ${_date(DateTime.tryParse(p.text('last_mrn_date')))}',
                color: _muted,
                size: 11,
              ),
          ]),
        );
      case 'added_date_time':
        return _text(formatStockItemAddedDate(p.data[key]), strong: true);
      case 'expiry_date':
        final label = expiryRemainingLabel(
          daysLeft: a.days,
          expiryDate: value as DateTime?,
        );
        return _badge(
          _stack([
            _text(_date(value), color: risk, strong: true, size: 15),
            const SizedBox(height: 4),
            _text(label, color: risk, strong: true, size: 12),
          ]),
          risk,
        );
      case 'note':
        final disabled = _busy.contains(a.key);
        return _stack([
          Tooltip(
            message: a.note.isEmpty ? 'No note yet' : a.note,
            child: _text(
              a.note.isEmpty
                  ? a.newReceipts
                        ? 'New receipts · review again'
                        : a.reviewed
                        ? 'Reviewed · note retained'
                        : 'Awaiting review'
                  : a.note,
              color: _muted,
              size: 12,
            ),
          ),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  key: ValueKey('note:${a.key}'),
                  onPressed: disabled ? null : () => onOpen(a),
                  style: TextButton.styleFrom(
                    foregroundColor: _teal,
                    backgroundColor: _teal.withValues(alpha: .06),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: Text(
                    a.note.isEmpty ? 'Note / details' : 'View note',
                    style: const TextStyle(color: _teal, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              if (!readOnly)
                IconButton(
                  key: ValueKey('review:${a.key}'),
                  tooltip: a.reviewed ? 'Reopen alarm' : 'Mark reviewed',
                  onPressed: disabled ? null : () => onReview(a),
                  style: IconButton.styleFrom(
                    backgroundColor: _teal.withValues(alpha: .08),
                    minimumSize: const Size(34, 34),
                    padding: const EdgeInsets.all(6),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: disabled
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          a.reviewed
                              ? Icons.undo_rounded
                              : Icons.task_alt_rounded,
                          color: _teal,
                          size: 22,
                        ),
                ),
            ],
          ),
        ]);
      case 'total_stock':
        return Align(
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _text(
                value == null ? 'Unavailable' : _qty(value),
                strong: true,
                size: 18,
              ),
              const SizedBox(height: 4),
              _badge(
                _text(
                  p.stockAvailable ? _status(p.status) : 'No snapshot',
                  color: _muted,
                  size: 11,
                ),
                _muted,
              ),
            ],
          ),
        );
      case 'branches_stock':
        return _stack([
          _text(_qty(value), strong: true, size: 16),
          const SizedBox(height: 3),
          _text(
            p.stockAvailable
                ? '${_qty(p.number('stocked_branches'))} stocked'
                : 'No snapshot',
            color: _muted,
            size: 11,
          ),
        ]);
      case 'store_total_percent':
        return _text(formatStockPercentage(value is num ? value : null));
      case 'days_on_hand':
        return _text(
          !p.stockAvailable
              ? 'Unavailable'
              : p.status == 'no_stock'
              ? 'No stock'
              : value == null
              ? 'No recent sales'
              : '${_qty(value)} days',
          strong: true,
        );
      case 'sales_2025':
      case 'sales_2026':
        final year = key.endsWith('2025') ? 2025 : 2026;
        return StockSalesSummary(data: p.year(year), totalColor: _ink);
      case 'best_month_2025':
      case 'best_month_2026':
        final y = p.year(key.endsWith('2025') ? 2025 : 2026);
        return _stack([
          _text(
            value is DateTime ? DateFormat('MMM yyyy').format(value) : '—',
            strong: true,
          ),
          const SizedBox(height: 3),
          _text('Qty ${_qty(y['best_qty'])}', color: _muted, size: 12),
        ]);
      case 'ordered_qty':
        return Tooltip(
          message:
              'Quantity ordered for the MRN receipts linked to this expiry date.',
          child: _text(_qty(value), strong: true, size: 16),
        );
      case 'received_qty':
        return Tooltip(
          message:
              'Reported total_qty for this receipt day and expiry. Bonus is a note only.',
          child: StockReceiptQuantity(
            quantity: _number(value) ?? 0,
            bonus: a.number('bonus'),
          ),
        );
      default:
        return Tooltip(
          message: value?.toString() ?? 'Unavailable',
          child: _text(value is num ? _qty(value) : value?.toString() ?? '—'),
        );
    }
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final a = alertFor(row), risk = riskColor(a);
    final alternate = _rows.indexOf(row).isOdd;
    return DataGridRowAdapter(
      color: Color.alphaBlend(
        risk.withValues(alpha: alternate ? .065 : .04),
        Colors.white,
      ),
      cells: row
          .getCells()
          .map(
            (cell) => AnimatedOpacity(
              opacity: _fading.contains(a.key) ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              child: Container(
                decoration: cell.columnName == 'item_name'
                    ? BoxDecoration(
                        border: Border(left: BorderSide(color: risk, width: 3)),
                      )
                    : null,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: cell.columnName == 'item_name'
                    ? Alignment.centerLeft
                    : Alignment.center,
                child: StockCellTapScope(
                  onTap: () => onOpen(a),
                  child: _cell(a, cell),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
