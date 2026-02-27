// orders_table.dart (full file)

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/daily_order_row.dart';
import '../bloc/order_bloc/orders_state.dart';
import 'orders_grid_controller.dart';

class OrdersTable extends StatefulWidget {
  final List<DailyOrderRow> rows;
  final bool isLoading;

  final List<String> orderedColumns;

  final Map<String, double> columnWidths;

  final Map<String, FinalReorderEdit> finalEdits;
  final ValueChanged<DailyOrderRow> onTapFinalReorder;

  // Controller for selection/scroll.
  final DataGridController? controller;

  // Controller used to clear filters via source.clearFilters().
  final OrdersGridController gridController;

  // Push resize events upward (BLoC).
  final void Function(String columnKey, double width) onColumnResized;

  const OrdersTable({
    super.key,
    required this.rows,
    required this.isLoading,
    required this.orderedColumns,
    required this.columnWidths,
    required this.finalEdits,
    required this.onTapFinalReorder,
    required this.gridController,
    required this.onColumnResized,
    this.controller,
  });

  static const List<String> allColumns = [
    'row_no',
    'branch',
    'item_code',
    'item_name',
    'goods_received_last_7_days',
    'branch_stock',
    'mismatch_stock',
    'store_stock',
    'pending_stock_received',
    'extra_qty_more_than_month',
    'max_adjustment_30d',
    'reason_for_max_adjustment_30d',
    'demand_for_30_days',
    'reorder_point_min',
    'reorder_max',
    'reorder_qty',
    'final_reorder_qty_store_stock_gt_0',
    'date_of_last_qty_received_in_branch',
    'total_sold_qty_cash_last_90',
    'total_sold_qty_online_last_90',
    'total_sold_qty_insurance_last_90',
    'qty_30_days_from_last_45d',
    'branch_formulary',
    'assortment_qty_base_stock',
    'assortment_by',
    'reason',
    'assortment_start',
    'assortment_end',
    'tma_qty',
    'tma_start',
    'tma_end',
    'item_purchase_type',
    'sales_orientation',
    'category',
    'sub_category',
    'company',
    'supplier',
    'indication',
    'active_ingredient',
    'pack_size',
    'concentration',
    'product_type_form',
    'retail_price',
    'vat',
    'is_upp',
    'upp_thiqa',
    'upp_basic',
    'tier',
    'item_minimum_order_unit',
    'barcode',
    'store_item_classifications',
  ];

  static const Map<String, String> titles = {
    'row_no': '#',
    'branch': 'BRANCH',
    'item_code': 'ITEM CODE',
    'item_name': 'ITEM NAME',
    'goods_received_last_7_days': 'GOODS RECEIVED\n(LAST 7 DAYS)',
    'branch_stock': 'BRANCH STOCK',
    'mismatch_stock': 'MISMATCH STOCK',
    'store_stock': 'STORE STOCK',
    'pending_stock_received': 'PENDING STOCK\nRECEIVED',
    'extra_qty_more_than_month': 'EXTRA QTY\n(MORE THAN MONTH)',
    'max_adjustment_30d': 'MAX ADJUSTMENT\n(30D DEMAND)',
    'reason_for_max_adjustment_30d': 'REASON FOR\nMAX ADJUSTMENT\n(30D DEMAND)',
    'demand_for_30_days': 'DEMAND FOR\n30 DAYS',
    'reorder_point_min': 'REORDER POINT\n(MIN)',
    'reorder_max': 'REORDER MAX',
    'reorder_qty': 'REORDER QTY',
    'final_reorder_qty_store_stock_gt_0':
        'FINAL REORDER QTY\n(STORE STOCK > 0)',
    'date_of_last_qty_received_in_branch':
        'DATE OF LAST QTY\nRECEIVED IN BRANCH',
    'total_sold_qty_cash_last_90': 'TOTAL SOLD QTY\nCASH (LAST 90)',
    'total_sold_qty_online_last_90': 'TOTAL SOLD QTY\nONLINE (LAST 90)',
    'total_sold_qty_insurance_last_90': 'TOTAL SOLD QTY\nINSURANCE (LAST 90)',
    'qty_30_days_from_last_45d': '30 DAYS QTY\n(FROM LAST 45D)',
    'branch_formulary': 'BRANCH\nFORMULARY',
    'assortment_qty_base_stock': 'ASSORTMENT QTY /\nBASE STOCK',
    'assortment_by': 'ASSORTMENT BY',
    'reason': 'REASON',
    'assortment_start': 'ASSORTMENT\nSTART',
    'assortment_end': 'ASSORTMENT\nEND',
    'tma_qty': 'TMA QTY',
    'tma_start': 'TMA START',
    'tma_end': 'TMA END',
    'item_purchase_type': 'ITEM PURCHASE TYPE',
    'sales_orientation': 'SALES\nORIENTATION',
    'category': 'CATEGORY',
    'sub_category': 'SUB-CATEGORY',
    'company': 'COMPANY',
    'supplier': 'SUPPLIER',
    'indication': 'INDICATION',
    'active_ingredient': 'ACTIVE\nINGREDIENT',
    'pack_size': 'PACK SIZE',
    'concentration': 'CONCENTRATION',
    'product_type_form': 'PRODUCT TYPE/\nFORM',
    'retail_price': 'RETAIL PRICE',
    'vat': 'VAT',
    'is_upp': 'IS UPP',
    'upp_thiqa': 'UPP THIQA',
    'upp_basic': 'UPP BASIC',
    'tier': 'TIER',
    'item_minimum_order_unit': 'ITEM MINIMUM\nORDER UNIT',
    'barcode': 'BARCODE',
    'store_item_classifications': 'STORE ITEM\nCLASSIFICATIONS',
  };
  static const Map<String, String> optionalTitles = {};
  @override
  State<OrdersTable> createState() => _OrdersTableState();
}

class _OrdersTableState extends State<OrdersTable> {
  late _OrdersDataSource _source;

  List<String> get _columns => widget.orderedColumns;

  @override
  void initState() {
    super.initState();

    _source = _OrdersDataSource(
      rows: widget.rows,
      columns: _columns,
      finalEdits: widget.finalEdits,
    );

    // Attach the source so parent can clear filters using source.clearFilters().
    widget.gridController.attachSource(_source);
  }

  @override
  void didUpdateWidget(covariant OrdersTable oldWidget) {
    super.didUpdateWidget(oldWidget);

    final colsChanged = !listEquals(
      oldWidget.orderedColumns,
      widget.orderedColumns,
    );
    final editsChanged = !mapEquals(oldWidget.finalEdits, widget.finalEdits);

    if (!identical(oldWidget.rows, widget.rows) ||
        colsChanged ||
        editsChanged) {
      _source.update(
        rows: widget.rows,
        columns: _columns,
        finalEdits: widget.finalEdits,
      );

      // Ensure controller still points to the current source.
      widget.gridController.attachSource(_source);
    }
  }

  String _title(String key) => OrdersTable.titles[key] ?? key;

  double _widthFor(String key) {
    final w = widget.columnWidths[key];
    if (w != null && w > 0) return w;
    return OrdersState.defaultWidthFor(key);
  }

  _ColGroup _groupFor(String key) {
    if (key == 'row_no' ||
        key == 'item_code' ||
        key == 'item_name' ||
        key == 'branch') {
      return _ColGroup.identity;
    }

    if ({
      'goods_received_last_7_days',
      'branch_stock',
      'store_stock',
      'mismatch_stock',
      'pending_stock_received',
    }.contains(key)) {
      return _ColGroup.stock;
    }

    if ({
      'branch_formulary',
      'assortment_qty_base_stock',
      'assortment_by',
      'max_adjustment_30d',
      'reason_for_max_adjustment_30d',
      'tma_qty',
      'tma_start',
      'tma_end',
    }.contains(key)) {
      return _ColGroup.rules;
    }

    if ({
      'qty_30_days_from_last_45d',
      'demand_for_30_days',
      'total_sold_qty_cash_last_90',
      'total_sold_qty_online_last_90',
      'total_sold_qty_insurance_last_90',
    }.contains(key)) {
      return _ColGroup.sales;
    }

    if ({
      'final_reorder_qty_store_stock_gt_0',
      'reorder_qty',
      'reorder_max',
      'reorder_point_min',
    }.contains(key)) {
      return _ColGroup.ordering;
    }

    return _ColGroup.other;
  }

  int _frozenCount() {
    var count = 0;
    if (_columns.contains('row_no')) count++;
    if (_columns.contains('item_code')) count++;
    if (_columns.contains('item_name')) count++;
    if (_columns.contains('branch')) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      if (widget.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return const Center(child: Text('No data'));
    }

    final frozenCount = _frozenCount();

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
              controller: widget.controller,
              source: _source,
              allowFiltering: true,
              allowSorting: false,
              gridLinesVisibility: GridLinesVisibility.both,
              headerGridLinesVisibility: GridLinesVisibility.both,
              allowColumnsResizing: true,
              columnWidthMode: ColumnWidthMode.none,
              frozenColumnsCount: frozenCount,
              rowHeight: 50,
              headerRowHeight: 72,
              onColumnResizeUpdate: (d) {
                widget.onColumnResized(d.column.columnName, d.width);
                return true;
              },
              onCellTap: (details) {
                if (details.rowColumnIndex.rowIndex <= 0) return;

                final columnIndex = details.rowColumnIndex.columnIndex;
                final effectiveRowIndex = details.rowColumnIndex.rowIndex - 1;

                if (columnIndex < 0 || columnIndex >= _columns.length) return;

                final colName = _columns[columnIndex];
                if (colName != 'final_reorder_qty_store_stock_gt_0') return;

                final daily = _source.rowAtEffectiveIndex(effectiveRowIndex);
                if (daily == null) return;

                widget.onTapFinalReorder(daily);
              },
              columns: _columns.map((key) {
                final group = _groupFor(key);
                final t = _title(key);

                return GridColumn(
                  columnName: key,
                  width: _widthFor(key),
                  minimumWidth: OrdersState.defaultMinWidth,
                  label: _HeaderCell(
                    title: t,
                    bg: group.headerBg,
                    fg: group.headerFg,
                    maxLines: t.contains('\n') ? 3 : 2,
                    alignCenter: key != 'item_name',
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
  final bool alignCenter;

  const _HeaderCell({
    required this.title,
    required this.bg,
    required this.fg,
    required this.maxLines,
    required this.alignCenter,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      alignment: alignCenter ? Alignment.center : Alignment.centerLeft,
      child: Tooltip(
        message: title.replaceAll('\n', ' '),
        child: Text(
          title,
          maxLines: maxLines,
          overflow: TextOverflow.visible,
          softWrap: true,
          textAlign: alignCenter ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            fontSize: 12.8,
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

    _gridRows = rows.asMap().entries.map((entry) {
      final idx = entry.key;
      final r = entry.value;
      return DataGridRow(
        cells: _columns.map((c) {
          return DataGridCell(columnName: c, value: _value(r, c, idx));
        }).toList(),
      );
    }).toList();

    _rowToIndex.clear();
    for (var i = 0; i < _gridRows.length; i++) {
      _rowToIndex[_gridRows[i]] = i;
    }

    notifyListeners();
  }

  DailyOrderRow? rowAtEffectiveIndex(int effectiveIndex) {
    final er = effectiveRows;
    if (effectiveIndex < 0 || effectiveIndex >= er.length) return null;

    final gridRow = er[effectiveIndex];
    final originalIndex = _rowToIndex[gridRow];
    if (originalIndex == null) return null;

    if (originalIndex < 0 || originalIndex >= _rows.length) return null;
    return _rows[originalIndex];
  }

  dynamic _value(DailyOrderRow r, String key, int index) {
    switch (key) {
      case 'row_no':
        return (index + 1).toString();

      case 'branch':
        return r.branch;
      case 'item_code':
        return r.itemCode;
      case 'item_name':
        return r.itemName;

      case 'goods_received_last_7_days':
        return r.goodsReceivedLast7Days ?? '';

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

      case 'reorder_point_min':
        return r.reorderPointMin ?? '';
      case 'reorder_max':
        return r.reorderMax ?? '';
      case 'reorder_qty':
        return r.reorderQtyNum;

      case 'final_reorder_qty_store_stock_gt_0':
        final e = _edits[r.itemCode];
        if (e != null) return e.newQty.toString();
        return r.finalReorderQtyStoreStockGt0;

      case 'date_of_last_qty_received_in_branch':
        return r.dateOfLastQtyReceivedInBranch ?? '';

      case 'total_sold_qty_cash_last_90':
        return r.totalSoldQtyCashLast90 ?? '';
      case 'total_sold_qty_online_last_90':
        return r.totalSoldQtyOnlineLast90 ?? '';
      case 'total_sold_qty_insurance_last_90':
        return r.totalSoldQtyInsuranceLast90 ?? '';

      case 'qty_30_days_from_last_45d':
        return r.qty30DaysFromLast45d;

      case 'branch_formulary':
        return r.branchFormulary ?? '';

      case 'assortment_qty_base_stock':
        return r.assortmentQtyBaseStock ?? '';
      case 'assortment_by':
        return r.assortmentBy ?? '';

      case 'reason':
        return r.reason ?? '';
      case 'assortment_start':
        return r.assortmentStart ?? '';
      case 'assortment_end':
        return r.assortmentEnd ?? '';

      case 'tma_qty':
        return r.tmaQty ?? '';
      case 'tma_start':
        return r.tmaStart ?? '';
      case 'tma_end':
        return r.tmaEnd ?? '';

      case 'item_purchase_type':
        return r.itemPurchaseType ?? '';
      case 'sales_orientation':
        return r.salesOrientation ?? '';
      case 'category':
        return r.category ?? '';
      case 'sub_category':
        return r.subCategory ?? '';
      case 'company':
        return r.company ?? '';
      case 'supplier':
        return r.supplier ?? '';
      case 'indication':
        return r.indication ?? '';
      case 'active_ingredient':
        return r.activeIngredient ?? '';
      case 'pack_size':
        return r.packSize ?? '';
      case 'concentration':
        return r.concentration ?? '';
      case 'product_type_form':
        return r.productTypeForm ?? '';

      case 'retail_price':
        return r.retailPrice ?? '';
      case 'vat':
        return r.vat ?? '';

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
      case 'tier':
        return r.tier ?? '';

      case 'item_minimum_order_unit':
        return r.minOrderUnit ?? '';

      case 'barcode':
        return r.barcode ?? '';

      case 'store_item_classifications':
        return r.storeItemClassifications ?? '';

      default:
        return '';
    }
  }

  @override
  List<DataGridRow> get rows => _gridRows;

  Color _textColorFor(String key, String value) {
    if (key == 'branch_formulary') {
      final t = value.trim().toUpperCase();
      if (t == 'ESSENTIAL') return Colors.green;
      if (t == 'NON') return Colors.red;
    }

    final n = num.tryParse(value.replaceAll(',', '')) ?? 0;

    if (key == 'mismatch_stock') {
      if (n < 0) return Colors.red;
      if (n > 0) return Colors.orange;
    }

    if (key == 'pending_stock_received') {
      if (n > 0) return AppColors.primaryColor;
      return AppColors.subText;
    }

    if (key == 'store_stock') {
      if (n == 0) return AppColors.subText;
    }

    if (key == 'branch_stock') {
      if (n <= 0) return Colors.red;
      if (n < 3) return Colors.orange;
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
      color: edited ? const Color(0xFFF7F5FF) : null,
      cells: row.getCells().map((c) {
        final key = c.columnName;
        final raw = c.value;
        final text = (raw ?? '').toString().trim();

        final align = (key == 'item_name')
            ? Alignment.centerLeft
            : Alignment.center;

        final color = _textColorFor(key, text);

        if (key == 'branch_formulary') {
          return Container(
            alignment: Alignment.center,
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

        if (key == 'final_reorder_qty_store_stock_gt_0' && daily != null) {
          final oldQty = _extractNumeric(daily.finalReorderQtyStoreStockGt0);
          final edit = _edits[daily.itemCode];
          final newQty = edit?.newQty;

          final showNew = (newQty != null);
          final main = showNew
              ? newQty.toString()
              : (text.isEmpty ? '—' : text);

          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                  'Auto: $oldQty',
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
