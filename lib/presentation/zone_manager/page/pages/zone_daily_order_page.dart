part of '../zone_manager_page.dart';

extension _ZoneDailyOrderPageView on _ZoneManagerPageState {
  Widget buildZoneDailyOrderPage() {
    if (_dailyLoading && _dailyRows.isEmpty) {
      return const _ReportLoading(label: 'Loading daily order...');
    }
    if (_dailyError != null && _dailyRows.isEmpty) {
      return _DailyOrderError(message: _dailyError!, onRetry: _loadDailyBranch);
    }
    final query = _query.trim().toLowerCase();
    final rows = query.isEmpty
        ? _dailyRows
        : _dailyRows
              .where(
                (row) =>
                    row.itemCode.toLowerCase().contains(query) ||
                    row.itemName.toLowerCase().contains(query) ||
                    (row.barcode ?? '').toLowerCase().contains(query) ||
                    (row.category ?? '').toLowerCase().contains(query),
              )
              .toList(growable: false);
    final exportRows = query.isEmpty
        ? _dailyRawRows
        : _dailyRawRows
              .where(
                (row) => row.values.any(
                  (value) => _text(value).toLowerCase().contains(query),
                ),
              )
              .toList(growable: false);
    const exportColumns = [
      _ColumnDef('item_code', 'Item Code'),
      _ColumnDef('item_name', 'Item Name'),
      _ColumnDef('branch_stock', 'Branch Stock'),
      _ColumnDef('mismatch_stock', 'Mismatch Stock'),
      _ColumnDef('store_stock', 'Store Stock'),
      _ColumnDef('pending_stock_received', 'Pending Received'),
      _ColumnDef('demand_for_30_days', 'Demand 30D'),
      _ColumnDef('reorder_qty_num', 'Reorder Qty'),
      _ColumnDef('final_reorder_qty_store_stock_gt_0', 'Final Order'),
      _ColumnDef('category', 'Category'),
      _ColumnDef('barcode', 'Barcode'),
    ];
    const gridColumns = [
      'row_no',
      'item_code',
      'item_name',
      'branch_stock',
      'mismatch_stock',
      'store_stock',
      'pending_stock_received',
      'demand_for_30_days',
      'reorder_point_min',
      'reorder_max',
      'reorder_qty',
      'final_reorder_qty_store_stock_gt_0',
      'category',
      'barcode',
    ];
    final finalOrder = rows.fold<num>(
      0,
      (sum, row) => sum + (num.tryParse(row.finalReorderQtyStoreStockGt0) ?? 0),
    );
    return Column(
      children: [
        _ModernPageHero(
          icon: Icons.shopping_cart_checkout_rounded,
          eyebrow: 'DAILY OPERATIONS',
          title: _selectedBranch,
          subtitle:
              '${_displayDate(widget.runDate)}  •  ${rows.length} order lines  •  Read-only zone view',
          accent: AppColors.primaryColor,
          metrics: [
            _HeroMetric('Items', '${rows.length}'),
            _HeroMetric('Final Order', finalOrder.toStringAsFixed(0)),
            _HeroMetric(
              'Mismatch',
              '${rows.where((row) => row.mismatchStock != 0).length}',
            ),
          ],
          actions: [
            OutlinedButton.icon(
              onPressed: () => _changePage(8),
              icon: const Icon(Icons.history_rounded),
              label: const Text('Order History'),
            ),
            FilledButton.icon(
              onPressed: exportRows.isEmpty
                  ? null
                  : () => _exportExcel(
                      'Daily_Order_${_safe(_selectedBranch)}',
                      exportRows,
                      exportColumns,
                    ),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Export Excel'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _ZoneTableToolbar(
          controller: _search,
          onChanged: _onSearchChanged,
          accent: AppColors.primaryColor,
          resultCount: rows.length,
          hintText: 'Search item code, item name, barcode, or category…',
          showResizeHint: true,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xff0F2942).withValues(alpha: .06),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: OrdersTable(
              rows: rows,
              isLoading: _dailyLoading,
              orderedColumns: gridColumns,
              columnWidths: _dailyColumnWidths,
              finalEdits: const {},
              onTapFinalReorder: (_) {},
              additionalEdits: const {},
              sentAdditionalQtyByItemCode: const {},
              onTapAdditionalRequest: (_) {},
              isSubmitted: true,
              canEditFinalReorder: false,
              showAdditionalRowActions: false,
              submitStartHour: 0,
              submitEndHour: 23,
              controller: _dailyGridController.controller,
              gridController: _dailyGridController,
              onColumnResized: (key, width) {
                _dailyColumnWidths[key] = width;
              },
            ),
          ),
        ),
      ],
    );
  }
}
