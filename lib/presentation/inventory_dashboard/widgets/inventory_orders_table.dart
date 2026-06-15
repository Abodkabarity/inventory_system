import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/daily_order_row.dart';
import '../../orders/widgets/orders_grid_controller.dart';
import '../../orders/widgets/orders_table.dart';

// ─────────────────────────────────────────────
// COLUMN GROUPS  — identical palette to OrdersTable
// ─────────────────────────────────────────────
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

_ColGroup _groupFor(String key) {
  if (const {'row_no', 'branch', 'item_code', 'item_name'}.contains(key)) {
    return _ColGroup.identity;
  }
  if (const {
    'goods_received_last_7_days',
    'branch_stock',
    'mismatch_stock',
    'store_stock',
    'pending_stock_received',
  }.contains(key)) {
    return _ColGroup.stock;
  }
  if (const {
    'demand_for_30_days',
    'qty_30_days_from_last_45d',
    'total_sold_qty_cash_last_90',
    'total_sold_qty_online_last_90',
    'total_sold_qty_insurance_last_90',
    'total_sales_last_90_days',
  }.contains(key)) {
    return _ColGroup.sales;
  }
  if (const {
    'branch_formulary',
    'assortment_qty_base_stock',
    'assortment_by',
    'reason',
    'assortment_start',
    'assortment_end',
    'tma_qty',
    'tma_start',
    'tma_end',
    'max_adjustment_30d',
    'reason_for_max_adjustment_30d',
  }.contains(key)) {
    return _ColGroup.rules;
  }
  if (const {
    'reorder_qty',
    'reorder_point_min',
    'reorder_max',
    'final_reorder_qty_store_stock_gt_0',
  }.contains(key)) {
    return _ColGroup.ordering;
  }
  return _ColGroup.other;
}

// ─────────────────────────────────────────────
// HEADER CELL  — matches OrdersTable._HeaderCell
// ─────────────────────────────────────────────
class _HeaderCell extends StatelessWidget {
  final String title;
  final Color bg;
  final Color fg;
  final bool alignCenter;

  const _HeaderCell({
    required this.title,
    required this.bg,
    required this.fg,
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
          maxLines: 3,
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

// ─────────────────────────────────────────────
// WIDGET
// ─────────────────────────────────────────────
class InventoryOrdersTable extends StatefulWidget {
  final List<DailyOrderRow> rows;
  final bool isLoading;
  final List<String> orderedColumns;
  final Map<String, double> columnWidths;
  final OrdersGridController gridController;
  final DataGridController? controller;
  final void Function(String columnKey, double width) onColumnResized;
  final ValueChanged<Map<String, List<FilterCondition>>>? onFilterChanged;

  const InventoryOrdersTable({
    super.key,
    required this.rows,
    required this.isLoading,
    required this.orderedColumns,
    required this.columnWidths,
    required this.gridController,
    required this.onColumnResized,
    this.onFilterChanged,
    this.controller,
  });

  static List<String> get allColumns => OrdersTable.allColumns;

  static Map<String, String> get titles => OrdersTable.titles;

  @override
  State<InventoryOrdersTable> createState() => _InventoryOrdersTableState();
}

class _InventoryOrdersTableState extends State<InventoryOrdersTable> {
  late _InventoryOrdersDataSource _source;

  @override
  void initState() {
    super.initState();
    _source = _InventoryOrdersDataSource(
      rows: widget.rows,
      columns: widget.orderedColumns,
    );
    widget.gridController.attachSource(_source);
  }

  @override
  void didUpdateWidget(covariant InventoryOrdersTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _source.update(rows: widget.rows, columns: widget.orderedColumns);
  }

  double _widthFor(String key) {
    if (widget.columnWidths.containsKey(key)) {
      return widget.columnWidths[key]!;
    }

    switch (key) {
      case 'row_no':
        return 60;

      case 'branch':
        return 160;

      case 'item_code':
        return 160;

      case 'item_name':
        return 320;

      case 'goods_received_last_7_days':
        return 190;

      case 'branch_stock':
        return 150;

      case 'mismatch_stock':
        return 150;

      case 'store_stock':
        return 150;

      case 'pending_stock_received':
        return 190;

      case 'demand_for_30_days':
        return 180;

      case 'qty_30_days_from_last_45d':
        return 200;

      case 'extra_qty_more_than_month':
        return 220;

      case 'max_adjustment_30d':
        return 190;

      case 'reorder_point_min':
        return 170;

      case 'reorder_max':
        return 170;

      case 'reorder_qty':
        return 170;

      case 'final_reorder_qty_store_stock_gt_0':
        return 260;

      case 'branch_formulary':
        return 180;

      case 'supplier':
        return 220;

      case 'category':
        return 180;

      case 'barcode':
        return 220;

      default:
        return 160;
    }
  }

  int _frozenCount() {
    int n = 0;
    if (widget.orderedColumns.contains('row_no')) n++;
    if (widget.orderedColumns.contains('branch')) n++;
    if (widget.orderedColumns.contains('item_code')) n++;
    if (widget.orderedColumns.contains('item_name')) n++;
    return n;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty && !widget.isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 60, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            Text(
              'No orders loaded',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SfDataGridTheme(
            data: SfDataGridThemeData(
              headerColor: const Color(0xFFF6F7FB),
              gridLineColor: AppColors.border.withValues(alpha: .8),
              selectionColor: const Color(0xFFEAF2FF),
            ),
            child: SfDataGrid(
              source: _source,
              controller: widget.controller,
              allowFiltering: true,
              allowSorting: true,
              allowColumnsResizing: true,
              gridLinesVisibility: GridLinesVisibility.both,
              headerGridLinesVisibility: GridLinesVisibility.both,
              columnWidthMode: ColumnWidthMode.none,
              frozenColumnsCount: _frozenCount(),
              rowHeight: 52,
              headerRowHeight: 72,
              onColumnResizeUpdate: (details) {
                widget.onColumnResized(
                  details.column.columnName,
                  details.width,
                );
                return true;
              },
              onFilterChanged: (_) {
                widget.onFilterChanged?.call(
                  Map<String, List<FilterCondition>>.from(
                    _source.filterConditions,
                  ),
                );
              },
              columns: widget.orderedColumns.map((key) {
                final group = _groupFor(key);
                final title = OrdersTable.titles[key] ?? key;
                return GridColumn(
                  columnName: key,
                  width: _widthFor(key),
                  minimumWidth: 80,
                  label: _HeaderCell(
                    title: title,
                    bg: group.headerBg,
                    fg: group.headerFg,
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
              color: Colors.white.withOpacity(0.65),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(
                    color: AppColors.primaryColor,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Loading orders…',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// DATA SOURCE
// ─────────────────────────────────────────────
class _InventoryOrdersDataSource extends DataGridSource {
  List<String> _columns = [];
  List<DataGridRow> _gridRows = [];

  _InventoryOrdersDataSource({
    required List<DailyOrderRow> rows,
    required List<String> columns,
  }) {
    update(rows: rows, columns: columns);
  }

  void update({
    required List<DailyOrderRow> rows,
    required List<String> columns,
  }) {
    _columns = columns;
    _gridRows = rows.asMap().entries.map((entry) {
      final idx = entry.key;
      final row = entry.value;
      return DataGridRow(
        cells: _columns.map((c) {
          return DataGridCell(columnName: c, value: _value(row, c, idx));
        }).toList(),
      );
    }).toList();

    notifyListeners();
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
      case 'reason_for_max_adjustment_30d':
        return r.reason ?? '';
      case 'demand_for_30_days':
        return _fmt(r.demandFor30Days);
      case 'reorder_point_min':
        return r.reorderPointMin ?? '';
      case 'reorder_max':
        return r.reorderMax ?? '';
      case 'reorder_qty':
        return r.reorderQtyNum;
      case 'final_reorder_qty_store_stock_gt_0':
        return r.finalReorderQtyStoreStockGt0;
      case 'date_of_last_qty_received_in_branch':
        return r.dateOfLastQtyReceivedInBranch ?? '';
      case 'total_sold_qty_cash_last_90':
        return r.totalSoldQtyCashLast90 ?? '';
      case 'total_sold_qty_online_last_90':
        return r.totalSoldQtyOnlineLast90 ?? '';
      case 'total_sold_qty_insurance_last_90':
        return r.totalSoldQtyInsuranceLast90 ?? '';
      case 'total_sales_last_90_days':
        return r.totalSalesLast90Days ?? '';
      case 'qty_30_days_from_last_45d':
        return _fmtFixed2(r.qty30DaysFromLast45d);
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
        return r.tmaQty ?? 0;
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

  String _fmt(dynamic v) {
    if (v == null) return '';
    final n = num.tryParse(v.toString());
    if (n == null) return v.toString();
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(2);
  }

  String _fmtFixed2(dynamic v) {
    if (v == null) return '';
    final n = num.tryParse(v.toString());
    if (n == null) return v.toString();
    return n.toStringAsFixed(2);
  }

  // ── Text color logic matching OrdersTable._textColorFor ──
  Color _textColorFor(String key, String text) {
    if (key == 'branch_formulary') {
      final t = text.trim().toUpperCase();
      if (t == 'ESSENTIAL') return Colors.green;
      if (t == 'TMA') return AppColors.secondaryColor;
      if (t == 'SALES') return Colors.purple;
      if (t == 'NEW ITEM') return Colors.deepOrange;
      if (t == 'NON') return Colors.red;
    }

    final n = num.tryParse(text.replaceAll(',', '')) ?? 0;

    if (key == 'mismatch_stock') {
      if (n < 0) return Colors.red;
      if (n > 0) return Colors.orange;
    }
    if (key == 'pending_stock_received') {
      return n > 0 ? AppColors.primaryColor : AppColors.subText;
    }
    if (key == 'store_stock' && n == 0) return AppColors.subText;
    if (key == 'branch_stock') {
      if (n <= 0) return Colors.red;
      if (n < 3) return Colors.orange;
    }

    return AppColors.text;
  }

  Color _formularyBadgeBg(String text) {
    final t = text.trim().toUpperCase();
    if (t == 'ESSENTIAL') return const Color(0xFFE9F7EE);
    if (t == 'NON') return const Color(0xFFFDECEC);
    return Colors.transparent;
  }

  @override
  List<DataGridRow> get rows => _gridRows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    return DataGridRowAdapter(
      cells: row.getCells().map((cell) {
        final key = cell.columnName;
        final raw = cell.value;
        final text = (raw ?? '').toString().trim();

        final align = key == 'item_name'
            ? Alignment.centerLeft
            : Alignment.center;

        // ── ITEM NAME ──────────────────────────────────────────
        if (key == 'item_name') {
          return Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Tooltip(
              message: text,
              child: Text(
                text.isEmpty ? '—' : text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.8,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ),
          );
        }

        // ── FORMULARY BADGE ────────────────────────────────────
        if (key == 'branch_formulary') {
          final color = _textColorFor(key, text);
          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: text.isEmpty
                ? const SelectableText('—')
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _formularyBadgeBg(text),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SelectableText(
                      text,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                  ),
          );
        }

        // ── DEFAULT CELL ───────────────────────────────────────
        final color = _textColorFor(key, text);

        return Container(
          alignment: align,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Tooltip(
            message: text,
            child: SelectableText(
              text.isEmpty ? '—' : text,
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
