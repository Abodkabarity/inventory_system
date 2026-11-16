import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../domain/entities/daily_order_row.dart';
import '../../orders/widgets/orders_table.dart';

enum _ColGroup {
  identity(Color(0xFFE9F0FB), Color(0xFF244971), Color(0xFF7CA5D5)),
  stock(Color(0xFFE3F5EF), Color(0xFF14594D), Color(0xFF60BBA5)),
  sales(Color(0xFFFFF2DB), Color(0xFF704A18), Color(0xFFDFAD60)),
  rules(Color(0xFFEDF0FA), Color(0xFF424E7B), Color(0xFF9DA8D3)),
  ordering(Color(0xFFF2EAFB), Color(0xFF61388B), Color(0xFFAF89D6)),
  other(Color(0xFFF0F4F8), Color(0xFF3E5268), Color(0xFFB0C2D5));

  const _ColGroup(this.background, this.foreground, this.accent);

  final Color background;
  final Color foreground;
  final Color accent;
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

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.title,
    required this.group,
    required this.sorted,
    required this.ascending,
    required this.filtered,
    this.onSort,
    this.onFilter,
  });

  final String title;
  final _ColGroup group;
  final bool sorted;
  final bool ascending;
  final bool filtered;
  final VoidCallback? onSort;
  final ValueChanged<Rect>? onFilter;

  @override
  Widget build(BuildContext context) {
    final name = title.replaceAll('\n', ' ');
    return Material(
      color: group.background,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: group.accent, width: 2)),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onSort,
                child: Tooltip(
                  message: onSort == null
                      ? name
                      : 'Sort $name ${sorted && ascending ? 'descending' : 'ascending'}',
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 12,
                      right: 4,
                      top: 6,
                      bottom: 6,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: group.foreground,
                              height: 1.15,
                              letterSpacing: .2,
                            ),
                          ),
                        ),
                        if (onSort != null)
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: sorted
                                ? BoxDecoration(
                                    color: group.foreground,
                                    borderRadius: BorderRadius.circular(5),
                                  )
                                : null,
                            child: Icon(
                              sorted
                                  ? (ascending
                                        ? Icons.arrow_upward
                                        : Icons.arrow_downward)
                                  : Icons.unfold_more,
                              size: 13,
                              color: sorted
                                  ? Colors.white
                                  : group.foreground.withValues(alpha: .65),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (onFilter != null)
              IconButton(
                onPressed: () {
                  final header = context.findRenderObject()! as RenderBox;
                  onFilter!(header.localToGlobal(Offset.zero) & header.size);
                },
                tooltip: 'Filter $name',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
                padding: EdgeInsets.zero,
                style: filtered
                    ? IconButton.styleFrom(
                        backgroundColor: group.accent.withValues(alpha: .3),
                      )
                    : null,
                icon: Icon(
                  filtered ? Icons.filter_alt : Icons.filter_alt_outlined,
                  size: 17,
                  color: group.foreground.withValues(alpha: filtered ? 1 : .78),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class InventoryOrdersTable extends StatefulWidget {
  const InventoryOrdersTable({
    super.key,
    required this.rows,
    required this.resultsVersion,
    required this.orderedColumns,
    required this.columnWidths,
    required this.verticalScrollController,
    required this.onColumnResized,
    required this.sortColumn,
    required this.ascending,
    required this.filteredColumns,
    required this.onSort,
    required this.onFilter,
  });

  final List<DailyOrderRow> rows;
  final int resultsVersion;
  final List<String> orderedColumns;
  final Map<String, double> columnWidths;
  final ScrollController verticalScrollController;
  final void Function(String columnKey, double width) onColumnResized;
  final String sortColumn;
  final bool ascending;
  final Set<String> filteredColumns;
  final ValueChanged<String> onSort;
  final void Function(String column, Rect bounds) onFilter;
  static const headerHeight = 54.0;

  @override
  State<InventoryOrdersTable> createState() => _InventoryOrdersTableState();
}

class _InventoryOrdersTableState extends State<InventoryOrdersTable> {
  late final _InventoryOrdersDataSource _source;

  @override
  void initState() {
    super.initState();
    _source = _InventoryOrdersDataSource(
      rows: widget.rows,
      columns: widget.orderedColumns,
    );
  }

  @override
  void didUpdateWidget(covariant InventoryOrdersTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resultsVersion != widget.resultsVersion ||
        !listEquals(oldWidget.orderedColumns, widget.orderedColumns)) {
      _source.replace(widget.rows, widget.orderedColumns);
    } else if (oldWidget.rows.length < widget.rows.length) {
      _source.append(widget.rows, oldWidget.rows.length);
    }
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  double _widthFor(String key, {required bool compact}) {
    if (widget.columnWidths.containsKey(key)) {
      return widget.columnWidths[key]!;
    }

    switch (key) {
      case 'row_no':
        return 60;

      case 'branch':
        return compact ? 116 : 160;

      case 'item_code':
        return compact ? 116 : 160;

      case 'item_name':
        return compact ? 246 : 320;

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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SfDataGridTheme(
        data: SfDataGridThemeData(
          headerColor: const Color(0xFFF0F4F8),
          gridLineColor: const Color(0xFFE7EDF4),
          selectionColor: const Color(0xFFEAF2FF),
        ),
        child: SfDataGrid(
          source: _source,
          verticalScrollController: widget.verticalScrollController,
          allowColumnsResizing: true,
          gridLinesVisibility: GridLinesVisibility.horizontal,
          headerGridLinesVisibility: GridLinesVisibility.both,
          columnWidthMode: ColumnWidthMode.none,
          frozenColumnsCount: constraints.maxWidth >= 940
              ? widget.orderedColumns
                    .takeWhile(
                      const {
                        'row_no',
                        'branch',
                        'item_code',
                        'item_name',
                      }.contains,
                    )
                    .length
              : 0,
          rowHeight: 45,
          headerRowHeight: InventoryOrdersTable.headerHeight,
          onColumnResizeUpdate: (details) {
            setState(() {
              widget.onColumnResized(details.column.columnName, details.width);
            });
            return true;
          },
          columns: [
            for (final key in widget.orderedColumns)
              GridColumn(
                columnName: key,
                width: _widthFor(key, compact: constraints.maxWidth < 600),
                minimumWidth: 90,
                label: _HeaderCell(
                  title:
                      OrdersTable.titles[key] ??
                      OrdersTable.optionalTitles[key] ??
                      key,
                  group: _groupFor(key),
                  sorted: widget.sortColumn == key,
                  ascending: widget.ascending,
                  filtered: widget.filteredColumns.contains(key),
                  onSort: key == 'row_no' ? null : () => widget.onSort(key),
                  onFilter: key == 'row_no'
                      ? null
                      : (bounds) => widget.onFilter(key, bounds),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InventoryGridRow extends DataGridRow {
  const _InventoryGridRow({required super.cells, required this.shaded});

  final bool shaded;
}

class _InventoryOrdersDataSource extends DataGridSource {
  List<String> _columns;
  List<DataGridRow> _gridRows = [];

  _InventoryOrdersDataSource({
    required List<DailyOrderRow> rows,
    required List<String> columns,
  }) : _columns = columns {
    _gridRows = List.generate(
      rows.length,
      (index) => _makeRow(rows[index], index),
    );
  }

  void replace(List<DailyOrderRow> rows, List<String> columns) {
    _columns = columns;
    _gridRows = List.generate(
      rows.length,
      (index) => _makeRow(rows[index], index),
    );
    notifyListeners();
  }

  void append(List<DailyOrderRow> rows, int start) {
    _gridRows.addAll([
      for (var index = start; index < rows.length; index++)
        _makeRow(rows[index], index),
    ]);
    notifyListeners();
  }

  DataGridRow _makeRow(DailyOrderRow row, int index) => _InventoryGridRow(
    shaded: index.isOdd,
    cells: [
      for (final column in _columns)
        DataGridCell(columnName: column, value: _value(row, column, index)),
    ],
  );

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
        return r.hasMaxAdjustment ? r.maxAdjustment30d : null;
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
      color: (row as _InventoryGridRow).shaded
          ? const Color(0xFFF7FAFD)
          : Colors.white,
      cells: row.getCells().map((cell) {
        final key = cell.columnName;
        final raw = cell.value;
        if (key == 'max_adjustment_30d' && raw == null) {
          return const SizedBox.shrink();
        }
        if (key == 'branch') {
          return ValueListenableBuilder<Map<String, String>>(
            valueListenable: StoreBranchIdentityRegistry.groups,
            builder: (context, groups, child) => _valueCell(
              key,
              StoreBranchIdentityRegistry.displayName(raw?.toString(), groups),
            ),
          );
        }
        final text = (raw ?? '').toString().trim();

        // ── ITEM NAME ──────────────────────────────────────────
        if (key == 'item_name') {
          return Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Tooltip(
              message: text,
              child: Text(
                text.isEmpty ? '—' : text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.8,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F3650),
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

        if (key == 'final_reorder_qty_store_stock_gt_0' &&
            (num.tryParse(text) ?? 0) > 0) {
          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1E7FB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                text,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF61388B),
                ),
              ),
            ),
          );
        }

        return _valueCell(key, text);
      }).toList(),
    );
  }

  Widget _valueCell(String column, String text) => Container(
    alignment: column == 'branch' || column == 'item_code'
        ? Alignment.centerLeft
        : Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Tooltip(
      message: text,
      child: SelectableText(
        text.isEmpty ? '—' : text,
        maxLines: 1,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: _textColorFor(column, text),
        ),
      ),
    ),
  );
}
