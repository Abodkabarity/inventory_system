import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/daily_order_row.dart';

class InventoryOrdersTable extends StatefulWidget {
  final List<DailyOrderRow> rows;

  final bool isLoading;

  final List<String> orderedColumns;

  final Map<String, double> columnWidths;

  final DataGridController? controller;

  final void Function(String columnKey, double width) onColumnResized;

  const InventoryOrdersTable({
    super.key,
    required this.rows,
    required this.isLoading,
    required this.orderedColumns,
    required this.columnWidths,
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
    'demand_for_30_days',
    'reorder_qty',
    'final_reorder_qty_store_stock_gt_0',
    'branch_formulary',
    'category',
    'supplier',
    'barcode',
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
    'pending_stock_received': 'PENDING STOCK',
    'demand_for_30_days': 'DEMAND FOR\n30 DAYS',
    'reorder_qty': 'REORDER QTY',
    'final_reorder_qty_store_stock_gt_0': 'FINAL REORDER',
    'branch_formulary': 'FORMULARY',
    'category': 'CATEGORY',
    'supplier': 'SUPPLIER',
    'barcode': 'BARCODE',
  };

  @override
  State<InventoryOrdersTable> createState() => _InventoryOrdersTableState();
}

class _InventoryOrdersTableState extends State<InventoryOrdersTable> {
  late InventoryOrdersDataSource source;

  @override
  void initState() {
    super.initState();

    source = InventoryOrdersDataSource(
      rows: widget.rows,
      columns: widget.orderedColumns,
    );
  }

  @override
  void didUpdateWidget(covariant InventoryOrdersTable oldWidget) {
    super.didUpdateWidget(oldWidget);

    source.update(rows: widget.rows, columns: widget.orderedColumns);
  }

  double widthFor(String key) {
    return widget.columnWidths[key] ?? 160;
  }

  int frozenCount() {
    int count = 0;

    if (widget.orderedColumns.contains('row_no')) count++;
    if (widget.orderedColumns.contains('branch')) count++;
    if (widget.orderedColumns.contains('item_code')) count++;
    if (widget.orderedColumns.contains('item_name')) count++;

    return count;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty && !widget.isLoading) {
      return const Center(
        child: Text(
          "No Orders Loaded",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      );
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
              source: source,

              controller: widget.controller,

              allowFiltering: true,

              allowSorting: true,

              allowColumnsResizing: true,

              gridLinesVisibility: GridLinesVisibility.both,

              headerGridLinesVisibility: GridLinesVisibility.both,

              columnWidthMode: ColumnWidthMode.none,

              frozenColumnsCount: frozenCount(),

              rowHeight: 64,

              headerRowHeight: 70,

              onColumnResizeUpdate: (details) {
                widget.onColumnResized(
                  details.column.columnName,
                  details.width,
                );

                return true;
              },

              columns: widget.orderedColumns.map((key) {
                return GridColumn(
                  columnName: key,

                  width: widthFor(key),

                  minimumWidth: 120,

                  label: Container(
                    padding: const EdgeInsets.all(10),

                    alignment: Alignment.center,

                    color: const Color(0xFFF7F8FC),

                    child: Text(
                      InventoryOrdersTable.titles[key] ?? key,

                      textAlign: TextAlign.center,

                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        if (widget.isLoading)
          Container(
            color: Colors.white.withOpacity(.6),

            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

class InventoryOrdersDataSource extends DataGridSource {
  List<DailyOrderRow> rowsData = [];

  List<String> columns = [];

  List<DataGridRow> dataGridRows = [];

  InventoryOrdersDataSource({
    required List<DailyOrderRow> rows,
    required List<String> columns,
  }) {
    update(rows: rows, columns: columns);
  }

  void update({
    required List<DailyOrderRow> rows,
    required List<String> columns,
  }) {
    rowsData = rows;

    this.columns = columns;

    dataGridRows = rows.asMap().entries.map((entry) {
      final index = entry.key;

      final row = entry.value;

      return DataGridRow(
        cells: columns.map((column) {
          return DataGridCell(
            columnName: column,
            value: value(row, column, index),
          );
        }).toList(),
      );
    }).toList();

    notifyListeners();
  }

  dynamic value(DailyOrderRow row, String key, int index) {
    switch (key) {
      case 'row_no':
        return index + 1;

      case 'branch':
        return row.branch;

      case 'item_code':
        return row.itemCode;

      case 'item_name':
        return row.itemName;

      case 'goods_received_last_7_days':
        return row.goodsReceivedLast7Days;

      case 'branch_stock':
        return row.branchStock;

      case 'mismatch_stock':
        return row.mismatchStock;

      case 'store_stock':
        return row.storeStock;

      case 'pending_stock_received':
        return row.pendingStockReceived;

      case 'demand_for_30_days':
        return row.demandFor30Days;

      case 'reorder_qty':
        return row.reorderQtyNum;

      case 'final_reorder_qty_store_stock_gt_0':
        return row.finalReorderQtyStoreStockGt0;

      case 'branch_formulary':
        return row.branchFormulary;

      case 'category':
        return row.category;

      case 'supplier':
        return row.supplier;

      case 'barcode':
        return row.barcode;

      default:
        return '';
    }
  }

  @override
  List<DataGridRow> get rows => dataGridRows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    return DataGridRowAdapter(
      cells: row.getCells().map((cell) {
        final text = (cell.value ?? '').toString();

        return Container(
          alignment: Alignment.center,

          padding: const EdgeInsets.symmetric(horizontal: 10),

          child: SelectableText(
            text,

            maxLines: 1,

            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        );
      }).toList(),
    );
  }
}
