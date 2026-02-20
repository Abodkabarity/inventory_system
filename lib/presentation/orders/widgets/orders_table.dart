import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/daily_order_row.dart';
import '../bloc/orders_state.dart';

class OrdersTable extends StatefulWidget {
  final List<DailyOrderRow> rows;
  final bool isLoading;
  final Set<String> visibleOptionalColumns;

  // ✅ NEW
  final Map<String, FinalReorderEdit> finalEdits;
  final ValueChanged<DailyOrderRow> onTapFinalReorder;

  const OrdersTable({
    super.key,
    required this.rows,
    required this.isLoading,
    required this.visibleOptionalColumns,
    required this.finalEdits,
    required this.onTapFinalReorder,
  });

  static const List<String> coreColumns = [
    'branch',
    'item_code',
    'item_name',
    'branch_stock',
    'mismatch_stock',
    'store_stock',
    'pending_stock_received',
    'extra_qty_more_than_month',
    'max_adjustment_30d',
    'demand_for_30_days',
    'final_reorder_qty_store_stock_gt_0',
    'qty_30_days_from_last_45d',
    'branch_formulary',
    'assortment_qty_base_stock',
    'assortment_by',
    'item_purchase_type',
    'category',
    'is_upp',
    'upp_thiqa',
    'upp_basic',
    'item_minimum_order_unit',
  ];

  static const Map<String, String> titles = {
    'branch': 'BRANCH',
    'item_code': 'ITEM CODE',
    'item_name': 'ITEM NAME',
    'branch_stock': 'BRANCH STOCK',
    'mismatch_stock': 'MISMATCH STOCK',
    'store_stock': 'STORE STOCK',
    'pending_stock_received': 'PENDING STOCK',
    'extra_qty_more_than_month': 'EXTRA QTY (> MONTH)',
    'max_adjustment_30d': 'MAX ADJ (30D)',
    'demand_for_30_days': 'DEMAND 30D',
    'final_reorder_qty_store_stock_gt_0': 'FINAL REORDER\n(Store > 0)',
    'qty_30_days_from_last_45d': '30D (FROM 45D)',
    'branch_formulary': 'FORMULARY',
    'assortment_qty_base_stock': 'ASSORTMENT / BASE',
    'assortment_by': 'ASSORTMENT BY',
    'item_purchase_type': 'PURCHASE TYPE',
    'category': 'CATEGORY',
    'is_upp': 'IS UPP',
    'upp_thiqa': 'UPP THIQA',
    'upp_basic': 'UPP BASIC',
    'item_minimum_order_unit': 'MIN ORDER UNIT',
  };

  static const List<String> optionalColumns = [
    'sub_category',
    'company',
    'supplier',
    'barcode',
  ];

  static const Map<String, String> optionalTitles = {
    'sub_category': 'SUB CATEGORY',
    'company': 'COMPANY',
    'supplier': 'SUPPLIER',
    'barcode': 'BARCODE',
  };

  @override
  State<OrdersTable> createState() => _OrdersTableState();
}

class _OrdersTableState extends State<OrdersTable> {
  late _OrdersDataSource _source;
  final Map<String, double> _colWidths = {};

  List<String> get _visibleColumns {
    final opt = OrdersTable.optionalColumns
        .where(widget.visibleOptionalColumns.contains)
        .toList();
    return [...OrdersTable.coreColumns, ...opt];
  }

  @override
  void initState() {
    super.initState();
    _source = _OrdersDataSource(
      rows: widget.rows,
      columns: _visibleColumns,
      finalEdits: widget.finalEdits,
    );

    for (final c in [
      ...OrdersTable.coreColumns,
      ...OrdersTable.optionalColumns,
    ]) {
      _colWidths[c] = _defaultWidth(c);
    }
  }

  @override
  void didUpdateWidget(covariant OrdersTable oldWidget) {
    super.didUpdateWidget(oldWidget);

    final colsChanged =
        oldWidget.visibleOptionalColumns.length !=
            widget.visibleOptionalColumns.length ||
        !oldWidget.visibleOptionalColumns.containsAll(
          widget.visibleOptionalColumns,
        );

    final editsChanged =
        oldWidget.finalEdits.length != widget.finalEdits.length;

    if (!identical(oldWidget.rows, widget.rows) ||
        colsChanged ||
        editsChanged) {
      _source.update(
        rows: widget.rows,
        columns: _visibleColumns,
        finalEdits: widget.finalEdits,
      );
      setState(() {});
    }
  }

  double _defaultWidth(String key) {
    if (key == 'item_name') return 420;
    if (key == 'branch') return 170;
    if (key == 'item_code') return 150;

    if (key == 'final_reorder_qty_store_stock_gt_0') return 240;
    if (key == 'max_adjustment_30d') return 220;
    if (key == 'pending_stock_received') return 190;
    if (key == 'extra_qty_more_than_month') return 210;

    if (key == 'category' || key == 'company' || key == 'supplier') return 220;
    if (key == 'barcode') return 180;
    if (key == 'branch_formulary') return 160;

    return 150;
  }

  _ColGroup _groupFor(String key) {
    if (key == 'branch' || key == 'item_code' || key == 'item_name') {
      return _ColGroup.identity;
    }

    if (key == 'branch_stock' ||
        key == 'store_stock' ||
        key == 'mismatch_stock' ||
        key == 'pending_stock_received') {
      return _ColGroup.stock;
    }

    if (key == 'branch_formulary' ||
        key == 'assortment_qty_base_stock' ||
        key == 'assortment_by' ||
        key == 'max_adjustment_30d') {
      return _ColGroup.rules;
    }

    if (key == 'qty_30_days_from_last_45d' || key == 'demand_for_30_days') {
      return _ColGroup.sales;
    }

    if (key == 'final_reorder_qty_store_stock_gt_0') return _ColGroup.ordering;

    return _ColGroup.other;
  }

  String _title(String key) =>
      OrdersTable.titles[key] ?? OrdersTable.optionalTitles[key] ?? key;

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      if (widget.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return const Center(child: Text('No data'));
    }

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SfDataGridTheme(
            data: SfDataGridThemeData(
              headerColor: const Color(0xFFF7F8FC),
              gridLineColor: AppColors.border.withOpacity(.8),
              selectionColor: const Color(0xFFEAF2FF),
            ),
            child: SfDataGrid(
              source: _source,
              allowFiltering: true,
              allowSorting: false,
              gridLinesVisibility: GridLinesVisibility.both,
              headerGridLinesVisibility: GridLinesVisibility.both,
              allowColumnsResizing: true,
              columnWidthMode: ColumnWidthMode.none,
              frozenColumnsCount: 3,
              rowHeight: 50,
              headerRowHeight: 58,
              onColumnResizeUpdate: (d) {
                setState(() => _colWidths[d.column.columnName] = d.width);
                return true;
              },

              // ✅ NEW: click cell => if final reorder column then open side panel
              onCellTap: (details) {
                // rowIndex: 0 is header
                if (details.rowColumnIndex.rowIndex <= 0) return;

                final columnIndex = details.rowColumnIndex.columnIndex;
                final rowIndex = details.rowColumnIndex.rowIndex - 1;

                if (rowIndex < 0 || rowIndex >= widget.rows.length) return;

                final colName = _visibleColumns[columnIndex];
                if (colName == 'final_reorder_qty_store_stock_gt_0') {
                  widget.onTapFinalReorder(widget.rows[rowIndex]);
                }
              },

              columns: _visibleColumns.map((key) {
                final group = _groupFor(key);
                return GridColumn(
                  columnName: key,
                  width: _colWidths[key] ?? _defaultWidth(key),
                  minimumWidth: 110,
                  label: _HeaderCell(
                    title: _title(key),
                    bg: group.headerBg,
                    fg: group.headerFg,
                    maxLines: _title(key).contains('\n') ? 2 : 1,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        if (widget.isLoading)
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.55),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String title;
  final Color bg;
  final Color fg;
  final int maxLines;

  const _HeaderCell({
    required this.title,
    required this.bg,
    required this.fg,
    required this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: title.replaceAll('\n', ' '),
        child: Text(
          title,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          softWrap: true,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w900,
            color: fg,
            height: 1.15,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _OrdersDataSource extends DataGridSource {
  List<DataGridRow> _gridRows = [];
  List<DailyOrderRow> _rows = [];
  List<String> _columns = [];
  Map<String, FinalReorderEdit> _edits = const {};
  final Map<DataGridRow, int> _rowToIndex = {};

  _OrdersDataSource({
    required List<DailyOrderRow> rows,
    required List<String> columns,
    required Map<String, FinalReorderEdit> finalEdits,
  }) {
    update(rows: rows, columns: columns, finalEdits: finalEdits);
  }

  void update({
    required List<DailyOrderRow> rows,
    required List<String> columns,
    required Map<String, FinalReorderEdit> finalEdits,
  }) {
    _rows = rows;
    _columns = columns;
    _edits = finalEdits;

    _gridRows = rows.map((r) {
      return DataGridRow(
        cells: _columns
            .map((c) => DataGridCell(columnName: c, value: _value(r, c)))
            .toList(),
      );
    }).toList();

    _rowToIndex.clear();
    for (var i = 0; i < _gridRows.length; i++) {
      _rowToIndex[_gridRows[i]] = i;
    }

    notifyListeners();
  }

  dynamic _value(DailyOrderRow r, String key) {
    switch (key) {
      case 'branch':
        return r.branch;
      case 'item_code':
        return r.itemCode;
      case 'item_name':
        return r.itemName;

      case 'branch_stock':
        return r.branchStock;
      case 'mismatch_stock':
        return r.mismatchStock;
      case 'store_stock':
        return r.storeStock;
      case 'pending_stock_received':
        return r.pendingStockReceived;

      case 'extra_qty_more_than_month':
        return r.extraQtyMoreThanMonth;
      case 'max_adjustment_30d':
        return r.maxAdjustment30d;
      case 'demand_for_30_days':
        return r.demandFor30Days;

      case 'final_reorder_qty_store_stock_gt_0':
        // ✅ display edited value if exists (for quick view)
        final e = _edits[r.itemCode];
        if (e != null) return e.newQty.toString();
        return r.finalReorderQtyStoreStockGt0;

      case 'qty_30_days_from_last_45d':
        return r.qty30DaysFromLast45d;

      case 'branch_formulary':
        return r.branchFormulary ?? '';

      case 'assortment_qty_base_stock':
        return r.assortmentQtyBaseStock ?? '';
      case 'assortment_by':
        return r.assortmentBy ?? '';
      case 'item_purchase_type':
        return r.itemPurchaseType ?? '';
      case 'category':
        return r.category ?? '';

      case 'sub_category':
        return r.subCategory ?? '';
      case 'company':
        return r.company ?? '';
      case 'supplier':
        return r.supplier ?? '';
      case 'barcode':
        return r.barcode ?? '';

      case 'is_upp':
        return (r.isUpp == true) ? 'YES' : ((r.isUpp == false) ? 'NO' : '');
      case 'upp_thiqa':
        return (r.uppThiqa == true)
            ? 'YES'
            : ((r.uppThiqa == false) ? 'NO' : '');
      case 'upp_basic':
        return (r.uppBasic == true)
            ? 'YES'
            : ((r.uppBasic == false) ? 'NO' : '');

      case 'item_minimum_order_unit':
        return r.minOrderUnit ?? '';

      default:
        return '';
    }
  }

  @override
  List<DataGridRow> get rows => _gridRows;

  bool _isNumKey(String key) {
    return {
      'branch_stock',
      'mismatch_stock',
      'store_stock',
      'pending_stock_received',
      'extra_qty_more_than_month',
      'max_adjustment_30d',
      'demand_for_30_days',
      'final_reorder_qty_store_stock_gt_0',
      'qty_30_days_from_last_45d',
      'item_minimum_order_unit',
    }.contains(key);
  }

  Color _textColorFor(String key, String value) {
    if (key == 'branch_formulary') {
      final t = value.trim().toUpperCase();
      if (t == 'ESSENTIAL') return Colors.green;
      if (t == 'NON') return Colors.red;
    }

    final n = num.tryParse(value) ?? 0;

    if (key == 'mismatch_stock') {
      if (n < 0) return Colors.red;
      if (n > 0) return Colors.orange;
    }

    if (key == 'pending_stock_received') {
      if (n > 0) return AppColors.blueDark;
      return AppColors.subText;
    }

    if (key == 'store_stock') {
      if (n == 0) return AppColors.subText;
    }

    if (key == 'branch_stock') {
      if (n <= 0) return Colors.red;
      if (n < 3) return Colors.orange;
    }

    // ✅ highlight edited final reorder
    if (key == 'final_reorder_qty_store_stock_gt_0') {
      return AppColors.text;
    }

    return AppColors.text;
  }

  Color _badgeBg(String value) {
    final t = value.trim().toUpperCase();
    if (t == 'ESSENTIAL') return const Color(0xFFE9F7EE);
    if (t == 'NON') return const Color(0xFFFDECEC);
    return Colors.transparent;
  }

  static int _extractNumeric(String? v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return 0;
    final direct = num.tryParse(s.replaceAll(',', ''));
    if (direct != null) return direct.round();
    final m = RegExp(r'[-+]?\d*\.?\d+').firstMatch(s);
    if (m == null) return 0;
    return (num.tryParse(m.group(0) ?? '') ?? 0).round();
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final idx = _rowToIndex[row] ?? -1;
    final daily = (idx >= 0 && idx < _rows.length) ? _rows[idx] : null;
    final edited = daily != null && _edits.containsKey(daily.itemCode);

    return DataGridRowAdapter(
      // ✅ highlight entire row if edited (soft)
      color: edited ? const Color(0xFFF7F5FF) : null,
      cells: row.getCells().map((c) {
        final key = c.columnName;
        final raw = c.value;
        final text = (raw ?? '').toString().trim();

        final align = _isNumKey(key)
            ? Alignment.centerRight
            : Alignment.centerLeft;
        final color = _textColorFor(key, text);

        // ✅ Formulary badge
        if (key == 'branch_formulary') {
          return Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: text.isEmpty
                ? const SelectableText('—')
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _badgeBg(text),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SelectableText(
                      text,
                      enableInteractiveSelection: true,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                  ),
          );
        }

        // ✅ FINAL REORDER cell shows Old/New
        if (key == 'final_reorder_qty_store_stock_gt_0' && daily != null) {
          final oldQty = _extractNumeric(daily.finalReorderQtyStoreStockGt0);
          final edit = _edits[daily.itemCode];
          final newQty = edit?.newQty;

          final showNew = (newQty != null);
          final main = showNew
              ? newQty.toString()
              : (text.isEmpty ? '—' : text);

          return Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (showNew)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFE6E8F0)),
                        ),
                        child: const Text(
                          'Edited',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Text(
                      main,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: showNew
                            ? const Color(0xFF3F2AA5)
                            : AppColors.text,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: Color(0xFF6B7280),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  showNew ? 'Auto: $oldQty' : 'Auto: $oldQty',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          alignment: align,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Tooltip(
            message: text,
            child: SelectableText(
              text.isEmpty ? '—' : text,
              enableInteractiveSelection: true,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

enum _ColGroup { identity, stock, sales, rules, ordering, other }

extension _ColGroupStyle on _ColGroup {
  Color get headerBg {
    switch (this) {
      case _ColGroup.identity:
        return const Color(0xFFEFF6FF);
      case _ColGroup.stock:
        return const Color(0xFFEFFAF3);
      case _ColGroup.sales:
        return const Color(0xFFFFF7E6);
      case _ColGroup.rules:
        return const Color(0xFFF3F0FF);
      case _ColGroup.ordering:
        return const Color(0xFFFFEEF2);
      case _ColGroup.other:
        return const Color(0xFFF6F7FB);
    }
  }

  Color get headerFg {
    switch (this) {
      case _ColGroup.identity:
        return const Color(0xFF0B2A4A);
      case _ColGroup.stock:
        return const Color(0xFF0F3D1F);
      case _ColGroup.sales:
        return const Color(0xFF5A3A00);
      case _ColGroup.rules:
        return const Color(0xFF2B1C5A);
      case _ColGroup.ordering:
        return const Color(0xFF5A1025);
      case _ColGroup.other:
        return AppColors.headerText;
    }
  }
}
