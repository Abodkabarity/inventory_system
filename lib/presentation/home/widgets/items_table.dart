import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';

import '../../../core/theme/app_colors.dart';

class ItemsTable extends StatefulWidget {
  final List<Map<String, dynamic>> rows;
  final bool isLoading;
  final VoidCallback onCreateOrder;

  final void Function(int rowIndex, String qty, String reason) onEditQty;

  const ItemsTable({
    super.key,
    required this.rows,
    required this.isLoading,
    required this.onCreateOrder,
    required this.onEditQty,
  });

  static const List<String> columns = [
    '_row_index',
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
    'item_status',
    'sales_orientation',
    'category',
    'sub_category',
    'company',
    'supplier',
    'indication',
    'main_ingredient',
    'pack_size_volume',
    'concentration',
    'product_type',
    'retail',
    'vat',
    'is_upp',
    'tier',
    'item_minimum_order_unit',
    'barcode',
    'store_classification',
    'final_qty',
  ];

  @override
  State<ItemsTable> createState() => _ItemsTableState();
}

class _ItemsTableState extends State<ItemsTable> {
  PlutoGridStateManager? _manager;

  @override
  void didUpdateWidget(covariant ItemsTable oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_manager != null) {
      if (!identical(oldWidget.rows, widget.rows)) {
        _rebuildRows();
      }
      if (oldWidget.isLoading != widget.isLoading) {
        _manager!.setShowLoading(widget.isLoading);
      }
    }
  }

  void _rebuildRows() {
    final m = _manager!;
    m.removeAllRows();
    if (widget.rows.isNotEmpty) {
      m.appendRows(_toPlutoRows(widget.rows));
    }
  }

  List<PlutoColumn> _buildColumns() {
    return ItemsTable.columns.map((key) {
      if (key == '_row_index') {
        return PlutoColumn(
          title: '',
          field: key,
          type: PlutoColumnType.number(),
          width: 0,
          minWidth: 0,
          enableSorting: false,
          enableFilterMenuItem: false,
          enableContextMenu: false,
          enableColumnDrag: false,
          hide: true,
          enableEditingMode: false,
          renderer: (_) => const SizedBox.shrink(),
        );
      }

      final title = key.replaceAll('_', ' ').toUpperCase();

      double width = 150;
      if (key == 'branch') width = 170;
      if (key == 'item_code') width = 130;
      if (key == 'item_name') width = 320;
      if (key == 'final_qty') width = 110;

      return PlutoColumn(
        title: title,
        field: key,
        type: PlutoColumnType.text(),
        width: width,
        minWidth: 110,
        enableColumnDrag: true,
        enableSorting: true,
        enableFilterMenuItem: true,
        enableContextMenu: true,
        enableEditingMode: false,
        renderer: (ctx) {
          final v = (ctx.cell.value ?? '').toString();
          return Text(
            v.isEmpty ? '—' : v,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.text),
          );
        },
      );
    }).toList();
  }

  List<PlutoRow> _toPlutoRows(List<Map<String, dynamic>> data) {
    return List.generate(data.length, (i) {
      final r = data[i];
      final cells = <String, PlutoCell>{};

      for (final c in ItemsTable.columns) {
        if (c == '_row_index') {
          cells[c] = PlutoCell(value: i);
        } else {
          cells[c] = PlutoCell(value: r[c] ?? '');
        }
      }

      return PlutoRow(cells: cells);
    });
  }

  @override
  Widget build(BuildContext context) {
    // ✅ إذا لا يوجد rows لكن isLoading true -> لا تعرض Create Order
    if (widget.rows.isEmpty) {
      if (widget.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _EmptyState(disabled: false, onCreateOrder: widget.onCreateOrder);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: PlutoGrid(
        columns: _buildColumns(),
        rows: _toPlutoRows(widget.rows),
        onLoaded: (event) {
          _manager = event.stateManager;
          _manager!.setShowLoading(widget.isLoading);
          _manager!.setSelectingMode(PlutoGridSelectingMode.row);
          _manager!.setShowColumnFilter(false);
          _manager!.setPageSize(999999);
        },
        onRowDoubleTap: (event) async {
          final idx = (event.row.cells['_row_index']?.value ?? -1) as int;
          if (idx < 0 || idx >= widget.rows.length) return;

          final r = widget.rows[idx];
          final res = await _openEditDialog(
            context,
            itemCode: (r['item_code'] ?? '').toString(),
            itemName: (r['item_name'] ?? '').toString(),
            initialQty: (r['final_qty'] ?? '').toString(),
            initialReason: (r['reason'] ?? '').toString(),
          );
          if (res != null) {
            widget.onEditQty(idx, res.$1, res.$2);
          }
        },
        configuration: PlutoGridConfiguration(
          style: PlutoGridStyleConfig(
            gridBorderColor: AppColors.border,
            borderColor: AppColors.border,
            activatedBorderColor: AppColors.blue,
            rowColor: AppColors.white,
            oddRowColor: AppColors.white,
            columnTextStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.headerText,
            ),
            cellTextStyle: const TextStyle(
              fontSize: 12.5,
              color: AppColors.text,
            ),
            columnHeight: 48,
            rowHeight: 46,
          ),
          scrollbar: const PlutoGridScrollbarConfig(
            isAlwaysShown: true,
            scrollbarThickness: 10,
            scrollbarThicknessWhileDragging: 12,
          ),
        ),
      ),
    );
  }

  Future<(String, String)?> _openEditDialog(
    BuildContext context, {
    required String itemCode,
    required String itemName,
    required String initialQty,
    required String initialReason,
  }) async {
    final qtyController = TextEditingController(text: initialQty);
    final reasonController = TextEditingController(text: initialReason);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Container(
          width: 560,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_note, color: AppColors.blueDark),
                  const SizedBox(width: 8),
                  const Text(
                    'Edit Quantity',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$itemName  •  $itemCode',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: qtyController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Final Qty',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: reasonController,
                      decoration: InputDecoration(
                        labelText: 'Reason',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (ok == true) {
      return (qtyController.text.trim(), reasonController.text.trim());
    }
    return null;
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreateOrder;
  final bool disabled;

  const _EmptyState({required this.onCreateOrder, required this.disabled});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 420,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.blueSoft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inbox_outlined,
              size: 40,
              color: AppColors.blueDark,
            ),
            const SizedBox(height: 10),
            const Text(
              'Table is empty',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'Create today order to start adding products.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.subText),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: disabled ? null : onCreateOrder,
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Create Order'),
            ),
          ],
        ),
      ),
    );
  }
}
