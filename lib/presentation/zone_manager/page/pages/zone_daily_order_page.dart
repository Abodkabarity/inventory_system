part of '../zone_manager_page.dart';

extension _ZoneDailyOrderPageView on _ZoneManagerPageState {
  Widget buildZoneDailyOrderPage() {
    if (_dailyLoading && _dailyRows.isEmpty) {
      return _DailyOrderProgressLoading(
        branchName: _selectedBranch,
        runDate: _displayDate(widget.runDate),
        progress: _dailyLoadProgress,
        stage: _dailyLoadStage,
        loadedRows: _dailyLoadedRows,
        totalRows: _dailyTotalRows,
      );
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
              usePrimaryFilterTheme: true,
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

class _DailyOrderProgressLoading extends StatelessWidget {
  const _DailyOrderProgressLoading({
    required this.branchName,
    required this.runDate,
    required this.progress,
    required this.stage,
    required this.loadedRows,
    required this.totalRows,
  });

  final String branchName;
  final String runDate;
  final double progress;
  final String stage;
  final int loadedRows;
  final int? totalRows;

  @override
  Widget build(BuildContext context) {
    final safeProgress = progress.clamp(0.0, 1.0);
    final percent = (safeProgress * 100).round();
    final hasTotal = totalRows != null && totalRows! > 0;
    final countLabel = hasTotal
        ? '${_formatCount(loadedRows)} of ${_formatCount(totalRows!)} items'
        : loadedRows > 0
        ? '${_formatCount(loadedRows)} items received'
        : 'Getting the order ready';

    return ColoredBox(
      color: const Color(0xFFF5F9FD),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryColor.withValues(alpha: .10),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor.withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.shopping_cart_checkout_rounded,
                        color: AppColors.primaryColor,
                        size: 27,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Opening daily order',
                            style: TextStyle(
                              color: AppColors.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$branchName  |  $runDate',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.subText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: safeProgress),
                      duration: const Duration(milliseconds: 260),
                      builder: (context, value, _) => Text(
                        '${(value * 100).round()}%',
                        style: const TextStyle(
                          color: AppColors.primaryColor,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: safeProgress),
                    duration: const Duration(milliseconds: 260),
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 10,
                      color: AppColors.primaryColor,
                      backgroundColor: AppColors.primaryColor.withValues(
                        alpha: .12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        stage,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      countLabel,
                      style: const TextStyle(
                        color: AppColors.subText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F8FC),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    percent < 100
                        ? 'The order is being loaded securely. Keep this page open.'
                        : 'Everything is ready. Opening the order now.',
                    style: const TextStyle(
                      color: AppColors.subText,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatCount(int value) {
    final digits = value.toString();
    return digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  }
}
