import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

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

  static List<String> get visibleColumns =>
      columns.where((c) => c != '_row_index').toList();

  @override
  State<ItemsTable> createState() => _ItemsTableState();
}

class _ItemsTableState extends State<ItemsTable> {
  late ItemsDataSource _source;

  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  final Map<String, double> _colWidths = {};

  @override
  void initState() {
    super.initState();

    _source = ItemsDataSource(
      rows: widget.rows,
      searchText: _searchText,
      onEditQty: widget.onEditQty,
    );

    for (final c in ItemsTable.visibleColumns) {
      _colWidths[c] = _defaultWidthFor(c);
    }
  }

  @override
  void didUpdateWidget(covariant ItemsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.rows, widget.rows)) {
      _source.updateRows(widget.rows, _searchText);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _titleFor(String key) {
    switch (key) {
      case 'branch':
        return 'BRANCH';
      case 'item_code':
        return 'ITEM CODE';
      case 'item_name':
        return 'ITEM NAME';

      case 'branch_stock':
        return 'BRANCH STOCK';
      case 'store_stock':
        return 'STORE STOCK';
      case 'mismatch_stock':
        return 'MISMATCH';
      case 'pending_stock_received':
        return 'PENDING';

      case 'max_adjustment_30d':
        return 'MAX ADJ';
      case 'branch_formulary':
        return 'FORMULARY';

      case 'qty_30_days_from_last_45d':
        return '30D (FROM 45D)';

      case 'final_qty':
        return 'FINAL QTY';

      case 'final_reorder_qty_store_stock_gt_0':
        return 'FINAL REORDER\n(Store > 0)';
      case 'date_of_last_qty_received_in_branch':
        return 'DATE OF LAST\nQTY RECEIVED';

      default:
        return key.replaceAll('_', ' ').toUpperCase();
    }
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
        key == 'max_adjustment_30d' ||
        key == 'assortment_qty_base_stock' ||
        key == 'assortment_by' ||
        key == 'assortment_start' ||
        key == 'assortment_end' ||
        key == 'tma_qty' ||
        key == 'tma_start' ||
        key == 'tma_end') {
      return _ColGroup.rules;
    }

    if (key == 'qty_30_days_from_last_45d' ||
        key == 'total_sold_qty_cash_last_90' ||
        key == 'total_sold_qty_online_last_90' ||
        key == 'total_sold_qty_insurance_last_90' ||
        key == 'demand_for_30_days') {
      return _ColGroup.sales;
    }

    if (key == 'reorder_point_min' ||
        key == 'reorder_max' ||
        key == 'reorder_qty' ||
        key == 'final_reorder_qty_store_stock_gt_0' ||
        key == 'final_qty' ||
        key == 'reason') {
      return _ColGroup.ordering;
    }

    return _ColGroup.other;
  }

  double _defaultWidthFor(String key) {
    double w = 150;

    if (key == 'branch') w = 170;
    if (key == 'item_code') w = 150;
    if (key == 'item_name') w = 420;

    if (key == 'company') w = 240;
    if (key == 'supplier') w = 240;

    if (key == 'branch_stock') w = 140;
    if (key == 'store_stock') w = 140;
    if (key == 'mismatch_stock') w = 130;
    if (key == 'pending_stock_received') w = 140;

    if (key == 'branch_formulary') w = 150;

    if (key == 'final_qty') w = 130;
    if (key == 'reason') w = 260;

    if (key == 'final_reorder_qty_store_stock_gt_0') w = 200;
    if (key == 'date_of_last_qty_received_in_branch') w = 190;

    return w;
  }

  void _applySearch(String v) {
    setState(() {
      _searchText = v.trim().toLowerCase();
      _source.updateRows(widget.rows, _searchText);
    });
  }

  Widget _toolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: _applySearch,
              decoration: InputDecoration(
                hintText: 'Search in all columns...',
                prefixIcon: const Icon(Icons.search, size: 18),
                filled: true,
                fillColor: AppColors.blueSoft,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppColors.border.withOpacity(.8),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppColors.border.withOpacity(.8),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.blue,
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: () {
              _searchController.clear();
              _applySearch('');
            },
            icon: const Icon(Icons.clear_all),
            label: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      if (widget.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _EmptyState(disabled: false, onCreateOrder: widget.onCreateOrder);
    }

    return Column(
      children: [
        _toolbar(),
        const SizedBox(height: 10),
        Expanded(
          child: Stack(
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
                    allowSorting: false,
                    allowFiltering: true,
                    gridLinesVisibility: GridLinesVisibility.both,
                    headerGridLinesVisibility: GridLinesVisibility.both,
                    columnWidthMode: ColumnWidthMode.none,
                    allowColumnsResizing: true,
                    onColumnResizeUpdate: (details) {
                      setState(() {
                        _colWidths[details.column.columnName] = details.width;
                      });
                      return true;
                    },
                    frozenColumnsCount: 3,
                    selectionMode: SelectionMode.single,
                    navigationMode: GridNavigationMode.row,
                    rowHeight: 46,
                    headerRowHeight: 58,

                    // ✅ Double click to edit (without blocking text selection)
                    onCellDoubleTap: (details) {
                      final rowIndex = details.rowColumnIndex.rowIndex;
                      final colIndex = details.rowColumnIndex.columnIndex;

                      if (rowIndex <= 0) return;
                      if (colIndex <= 0) return;

                      _source.handleDoubleTap(rowIndex - 1);
                    },

                    columns: ItemsTable.visibleColumns.map((key) {
                      final group = _groupFor(key);

                      return GridColumn(
                        columnName: key,
                        width: _colWidths[key] ?? _defaultWidthFor(key),
                        minimumWidth: 110,
                        label: _HeaderCell(
                          title: _titleFor(key),
                          bg: group.headerBg,
                          fg: group.headerFg,
                          maxLines: _titleFor(key).contains('\n') ? 2 : 1,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (widget.isLoading)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
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

class ItemsDataSource extends DataGridSource {
  List<Map<String, dynamic>> _allRows = [];
  List<Map<String, dynamic>> _viewRows = [];

  final void Function(int rowIndex, String qty, String reason) onEditQty;

  final List<DataGridRow> _gridRows = [];
  final Map<DataGridRow, int> _rowToIndex = {};

  ItemsDataSource({
    required List<Map<String, dynamic>> rows,
    required String searchText,
    required this.onEditQty,
  }) {
    updateRows(rows, searchText);
  }

  void updateRows(List<Map<String, dynamic>> rows, String searchText) {
    _allRows = rows;

    final q = searchText.trim().toLowerCase();
    if (q.isEmpty) {
      _viewRows = List<Map<String, dynamic>>.from(_allRows);
    } else {
      _viewRows = _allRows.where((r) {
        for (final k in ItemsTable.visibleColumns) {
          final v = (r[k] ?? '').toString().toLowerCase();
          if (v.contains(q)) return true;
        }
        return false;
      }).toList();
    }

    _gridRows.clear();
    _rowToIndex.clear();

    for (var i = 0; i < _viewRows.length; i++) {
      final r = _viewRows[i];
      final row = DataGridRow(
        cells: ItemsTable.visibleColumns
            .map((c) => DataGridCell<dynamic>(columnName: c, value: r[c] ?? ''))
            .toList(),
      );

      _gridRows.add(row);
      _rowToIndex[row] = i;
    }

    notifyListeners();
  }

  // Called from SfDataGrid.onCellDoubleTap
  void handleDoubleTap(int viewRowIndex) async {
    if (viewRowIndex < 0 || viewRowIndex >= _viewRows.length) return;

    final r = _viewRows[viewRowIndex];

    final originalIndex = (r['_row_index'] is int)
        ? r['_row_index'] as int
        : int.tryParse((r['_row_index'] ?? '').toString()) ?? viewRowIndex;

    final itemCode = (r['item_code'] ?? '').toString();
    final itemName = (r['item_name'] ?? '').toString();

    final qty = (r['final_qty'] ?? '').toString();
    final reason = (r['reason'] ?? '').toString();

    final res = await _openEditDialog(
      itemCode: itemCode,
      itemName: itemName,
      initialQty: qty,
      initialReason: reason,
    );

    if (res != null) {
      onEditQty(originalIndex, res.$1, res.$2);
    }
  }

  Future<(String, String)?> _openEditDialog({
    required String itemCode,
    required String itemName,
    required String initialQty,
    required String initialReason,
  }) async {
    final qtyController = TextEditingController(text: initialQty);
    final reasonController = TextEditingController(text: initialReason);

    final ctx = navigatorKey.currentContext;
    if (ctx == null) return null;

    final ok = await showDialog<bool>(
      context: ctx,
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
                    onPressed: () => Navigator.pop(ctx, false),
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
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
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

  @override
  List<DataGridRow> get rows => _gridRows;

  String _formatCell(String key, dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return '';

    const numericKeys = {
      'branch_stock',
      'store_stock',
      'mismatch_stock',
      'pending_stock_received',
      'qty_30_days_from_last_45d',
      'demand_for_30_days',
      'reorder_point_min',
      'reorder_max',
      'reorder_qty',
      'final_qty',
      'item_minimum_order_unit',
    };

    if (numericKeys.contains(key)) {
      final n = num.tryParse(s);
      if (n == null) return s;
      if (n == n.roundToDouble()) return n.toInt().toString();
      return n.toStringAsFixed(2);
    }

    return s;
  }

  bool _isNumberLike(String key) {
    return {
      'final_qty',
      'branch_stock',
      'store_stock',
      'mismatch_stock',
      'pending_stock_received',
      'qty_30_days_from_last_45d',
      'reorder_point_min',
      'reorder_max',
      'reorder_qty',
      'demand_for_30_days',
      'item_minimum_order_unit',
    }.contains(key);
  }

  Color _textColorFor(String key, String value) {
    if (key == 'branch_formulary') {
      final t = value.trim().toUpperCase();
      if (t == 'ESSENTIAL') return Colors.green;
      if (t == 'NON') return Colors.red;
      return AppColors.text;
    }

    final n = num.tryParse(value) ?? 0;

    if (key == 'mismatch_stock') {
      if (n < 0) return Colors.red;
      if (n > 0) return Colors.orange;
      return AppColors.text;
    }

    if (key == 'pending_stock_received') {
      if (n > 0) return AppColors.blueDark;
      return AppColors.subText;
    }

    if (key == 'store_stock') {
      if (n == 0) return AppColors.subText;
      return AppColors.text;
    }

    if (key == 'branch_stock') {
      if (n <= 0) return Colors.red;
      if (n < 3) return Colors.orange;
      return AppColors.text;
    }

    if (key == 'final_qty') {
      if (value.trim().isNotEmpty) return AppColors.blueDark;
      return AppColors.subText;
    }

    return AppColors.text;
  }

  Color _badgeBg(String value) {
    final t = value.trim().toUpperCase();
    if (t == 'ESSENTIAL') return const Color(0xFFE9F7EE);
    if (t == 'NON') return const Color(0xFFFDECEC);
    return Colors.transparent;
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    return DataGridRowAdapter(
      cells: row.getCells().map((cell) {
        final key = cell.columnName;
        final v = _formatCell(key, cell.value);
        final align = _isNumberLike(key)
            ? Alignment.centerRight
            : Alignment.centerLeft;
        final color = _textColorFor(key, v);

        if (key == 'branch_formulary') {
          return Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: v.isEmpty
                ? const SelectableText('—')
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _badgeBg(v),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SelectableText(
                      v,
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

        return Container(
          alignment: align,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Tooltip(
            message: v.isEmpty ? '' : v,
            child: SelectableText(
              v.isEmpty ? '—' : v,
              enableInteractiveSelection: true,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: key == 'final_qty'
                    ? FontWeight.w900
                    : FontWeight.w600,
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

// Provide a global key in your app root (MaterialApp)
// MaterialApp(navigatorKey: navigatorKey, ...)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
