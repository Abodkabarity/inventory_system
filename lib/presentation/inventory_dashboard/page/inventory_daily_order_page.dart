import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../domain/entities/daily_order_row.dart';
import '../../orders/widgets/orders_grid_controller.dart';
import '../../orders/bloc/order_bloc/orders_state.dart' as orders_state;
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';
import '../widgets/inventory_columns_panel.dart';
import '../widgets/inventory_orders_table.dart';

class InventoryDailyOrderPage extends StatefulWidget {
  final String runDate;
  const InventoryDailyOrderPage({super.key, required this.runDate});

  @override
  State<InventoryDailyOrderPage> createState() =>
      _InventoryDailyOrderPageState();
}

class _InventoryDailyOrderPageState extends State<InventoryDailyOrderPage> {
  final OrdersGridController controller = OrdersGridController();
  final TextEditingController searchController = TextEditingController();
  Map<String, List<FilterCondition>> _gridFilters = {};

  static const int _pageSize = 1000;

  @override
  void initState() {
    super.initState();
    context.read<InventoryBloc>().add(LoadInventoryOrders(widget.runDate));
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    searchController.clear();

    context.read<InventoryBloc>().add(SearchInventoryOrders(''));

    setState(() {});
  }

  void _clearAllFilters() {
    searchController.clear();
    controller.resetGridUi();
    _gridFilters = {};

    context.read<InventoryBloc>().add(SearchInventoryOrders(''));

    setState(() {});
  }

  bool get _hasGridFilters => _gridFilters.values.any((e) => e.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      buildWhen: (previous, current) {
        return previous.allOrders != current.allOrders ||
            previous.cachedOrders != current.cachedOrders ||
            previous.currentOrdersPage != current.currentOrdersPage ||
            previous.isOrdersLoading != current.isOrdersLoading ||
            previous.isBackgroundLoading != current.isBackgroundLoading ||
            previous.loadedCount != current.loadedCount ||
            previous.allDataLoaded != current.allDataLoaded ||
            previous.visibleColumns != current.visibleColumns ||
            previous.columnOrder != current.columnOrder ||
            previous.isExporting != current.isExporting ||
            previous.exportMessage != current.exportMessage;
      },
      builder: (context, state) {
        final columns = state.columnOrder.isEmpty
            ? orders_state.OrdersState.defaultColumnOrder
            : state.columnOrder;

        final visible = state.visibleColumns.isEmpty
            ? orders_state.OrdersState.defaultVisibleInTable
            : state.visibleColumns;

        final finalColumns = columns
            .where((c) => visible.contains(c) && c != 'additional_request')
            .toList();
        finalColumns.remove('branch');
        final itemCodeIndex = finalColumns.indexOf('item_code');
        finalColumns.insert(itemCodeIndex < 0 ? 0 : itemCodeIndex, 'branch');

        final isSearching = searchController.text.trim().isNotEmpty;
        final isGridFiltering = _hasGridFilters;
        final sourceRows = isSearching ? state.allOrders : state.cachedOrders;
        final allRows = isGridFiltering
            ? _applyGridFilters(sourceRows, _gridFilters)
            : sourceRows;
        final total = allRows.length;
        final totalCached = state.cachedOrders.length;

        // The grid receives every cached row so column filters work on the
        // whole Hive cache, not just the visible 1000-row page.
        final int page = isSearching || isGridFiltering
            ? 0
            : state.currentOrdersPage;
        final int totalPages = isSearching || isGridFiltering
            ? 1
            : (totalCached == 0 ? 1 : (totalCached / _pageSize).ceil());
        final int safePage = page.clamp(0, totalPages - 1);
        final int fromIdx = isSearching ? 0 : safePage * _pageSize;
        final int toIdx = isSearching
            ? total
            : ((safePage + 1) * _pageSize).clamp(0, total);
        final displayRows = isSearching || isGridFiltering
            ? allRows
            : allRows.sublist(fromIdx, toIdx);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Stack(
            children: [
              Column(
                children: [
                  // TOP BAR
                  _TopBar(
                    runDate: widget.runDate,
                    total: total,
                    totalCached: totalCached,
                    isLoading: state.isOrdersLoading,
                    isBackgroundLoad: state.isBackgroundLoading,
                    isSearchActive: isSearching,
                    searchQuery: searchController.text.trim(),
                    finalColumns: finalColumns,
                    searchController: searchController,
                    state: state,
                    onClearSearch: _clearSearch,
                    onClearFilters: _clearAllFilters,
                  ),

                  const SizedBox(height: 12),

                  // TABLE
                  Expanded(
                    child: InventoryOrdersTable(
                      rows: displayRows,
                      isLoading: state.isOrdersLoading,
                      orderedColumns: finalColumns,
                      columnWidths: {},
                      gridController: controller,
                      controller: controller.controller,
                      onColumnResized: (_, __) {},
                      onFilterChanged: (filters) {
                        setState(() {
                          _gridFilters = filters;
                        });
                      },
                    ),
                  ),

                  // PAGINATION — hidden while searching
                  if (!isSearching && !isGridFiltering)
                    _PaginationBar(
                      page: safePage,
                      totalPages: totalPages,
                      total: totalCached,
                      fromIdx: fromIdx,
                      toIdx: toIdx.clamp(0, totalCached),
                      isLoading: state.isOrdersLoading,
                      onGo: (p) {
                        context.read<InventoryBloc>().add(
                          LoadOrdersPage(runDate: widget.runDate, page: p),
                        );
                      },
                    ),

                  // SEARCH RESULT FOOTER
                  if (isSearching || isGridFiltering)
                    _SearchFooter(
                      query: isSearching
                          ? searchController.text.trim()
                          : 'table filters',
                      resultCount: total,
                      onClear: _clearAllFilters,
                    ),
                ],
              ),

              if (state.isExporting)
                Positioned.fill(child: _ExportOverlay(state: state)),
            ],
          ),
        );
      },
    );
  }

  List<DailyOrderRow> _applyGridFilters(
    List<DailyOrderRow> rows,
    Map<String, List<FilterCondition>> filters,
  ) {
    final active = Map<String, List<FilterCondition>>.fromEntries(
      filters.entries.where((e) => e.value.isNotEmpty),
    );
    if (active.isEmpty) return rows;

    return rows.where((row) {
      for (final entry in active.entries) {
        if (!_matchesConditions(_filterValue(row, entry.key), entry.value)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Object? _filterValue(DailyOrderRow r, String key) {
    switch (key) {
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
      case 'reason':
        return r.reason ?? '';
      case 'demand_for_30_days':
        return r.demandFor30Days;
      case 'reorder_point_min':
        return r.reorderPointMin ?? 0;
      case 'reorder_max':
        return r.reorderMax ?? 0;
      case 'reorder_qty':
        return r.reorderQtyNum;
      case 'final_reorder_qty_store_stock_gt_0':
        return r.finalReorderQtyStoreStockGt0;
      case 'date_of_last_qty_received_in_branch':
        return r.dateOfLastQtyReceivedInBranch ?? '';
      case 'total_sold_qty_cash_last_90':
        return r.totalSoldQtyCashLast90 ?? 0;
      case 'total_sold_qty_online_last_90':
        return r.totalSoldQtyOnlineLast90 ?? 0;
      case 'total_sold_qty_insurance_last_90':
        return r.totalSoldQtyInsuranceLast90 ?? 0;
      case 'total_sales_last_90_days':
        return r.totalSalesLast90Days ?? 0;
      case 'qty_30_days_from_last_45d':
        return r.qty30DaysFromLast45d;
      case 'branch_formulary':
        return r.branchFormulary ?? '';
      case 'assortment_qty_base_stock':
        return r.assortmentQtyBaseStock ?? '';
      case 'assortment_by':
        return r.assortmentBy ?? '';
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
        return r.retailPrice ?? 0;
      case 'vat':
        return r.vat ?? 0;
      case 'is_upp':
        return r.isUpp == true ? 'YES' : 'NO';
      case 'upp_thiqa':
        return r.uppThiqa == true ? 'YES' : 'NO';
      case 'upp_basic':
        return r.uppBasic == true ? 'YES' : 'NO';
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

  bool _matchesConditions(Object? value, List<FilterCondition> conditions) {
    if (conditions.isEmpty) return true;

    bool? result;
    for (final condition in conditions) {
      final matched = _matchesCondition(value, condition);
      result = result == null
          ? matched
          : condition.filterOperator == FilterOperator.and
          ? result && matched
          : result || matched;
    }
    return result ?? true;
  }

  bool _matchesCondition(Object? value, FilterCondition condition) {
    final rawNum = num.tryParse((value ?? '').toString());
    final compareNum = num.tryParse((condition.value ?? '').toString());

    if (rawNum != null && compareNum != null) {
      switch (condition.type) {
        case FilterType.equals:
          return rawNum == compareNum;
        case FilterType.notEqual:
          return rawNum != compareNum;
        case FilterType.greaterThan:
          return rawNum > compareNum;
        case FilterType.greaterThanOrEqual:
          return rawNum >= compareNum;
        case FilterType.lessThan:
          return rawNum < compareNum;
        case FilterType.lessThanOrEqual:
          return rawNum <= compareNum;
        default:
          break;
      }
    }

    final left = condition.isCaseSensitive
        ? (value ?? '').toString()
        : (value ?? '').toString().toLowerCase();
    final right = condition.isCaseSensitive
        ? (condition.value ?? '').toString()
        : (condition.value ?? '').toString().toLowerCase();

    switch (condition.type) {
      case FilterType.contains:
        return left.contains(right);
      case FilterType.doesNotContain:
        return !left.contains(right);
      case FilterType.beginsWith:
        return left.startsWith(right);
      case FilterType.doesNotBeginWith:
        return !left.startsWith(right);
      case FilterType.endsWith:
        return left.endsWith(right);
      case FilterType.doesNotEndsWith:
        return !left.endsWith(right);
      case FilterType.equals:
        return left == right;
      case FilterType.notEqual:
        return left != right;
      case FilterType.greaterThan:
        return left.compareTo(right) > 0;
      case FilterType.greaterThanOrEqual:
        return left.compareTo(right) >= 0;
      case FilterType.lessThan:
        return left.compareTo(right) < 0;
      case FilterType.lessThanOrEqual:
        return left.compareTo(right) <= 0;
    }
  }
}

// ─────────────────────────────────────────────
// TOP BAR
// ─────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final String runDate;
  final int total;
  final int totalCached;
  final bool isLoading;
  final bool isBackgroundLoad;
  final bool isSearchActive;
  final String searchQuery;
  final List<String> finalColumns;
  final TextEditingController searchController;
  final InventoryState state;
  final VoidCallback onClearSearch;
  final VoidCallback onClearFilters;

  const _TopBar({
    required this.runDate,
    required this.total,
    required this.totalCached,
    required this.isLoading,
    required this.isBackgroundLoad,
    required this.isSearchActive,
    required this.searchQuery,
    required this.finalColumns,
    required this.searchController,
    required this.state,
    required this.onClearSearch,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4EAF2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── SEARCH FIELD ────────────────────────────────────
          Expanded(
            child: SizedBox(
              height: 42,
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: 'Search item name / code / branch / barcode…',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 13,
                  ),
                  prefixIcon: IconButton(
                    icon: const Icon(Icons.search, size: 18),
                    onPressed: () {
                      context.read<InventoryBloc>().add(
                        SearchInventoryOrders(searchController.text.trim()),
                      );
                    },
                  ),
                  suffixIcon: searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          color: Colors.grey.shade500,
                          tooltip: 'Clear search',
                          onPressed: onClearSearch,
                          splashRadius: 16,
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFD),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFDCE6F2)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFDCE6F2)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Color(0xFF0EA5C6),
                      width: 1.5,
                    ),
                  ),
                ),
                onSubmitted: (_) {
                  context.read<InventoryBloc>().add(
                    SearchInventoryOrders(searchController.text.trim()),
                  );
                },
              ),
            ),
          ),

          const SizedBox(width: 10),

          // ── STATUS BADGE ────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _buildBadge(),
          ),

          const SizedBox(width: 8),

          SizedBox(
            height: 42,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF4D57),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              onPressed: onClearFilters,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: const Text(
                'Clear Filters',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // ── EXPORT ──────────────────────────────────────────
          SizedBox(
            height: 42,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D7377),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              onPressed: state.isExporting
                  ? null
                  : () {
                      _openDailyOrderExportDialog(context);
                    },
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Export', style: TextStyle(fontSize: 13)),
            ),
          ),

          const SizedBox(width: 8),

          // ── COLUMNS ─────────────────────────────────────────
          SizedBox(
            height: 42,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                elevation: 0,
              ),
              onPressed: () {
                showGeneralDialog(
                  context: context,
                  barrierDismissible: true,
                  barrierLabel: 'Columns',
                  barrierColor: Colors.black.withValues(alpha: .35),
                  transitionDuration: const Duration(milliseconds: 220),
                  pageBuilder: (dialogContext, animation, secondaryAnimation) {
                    final bloc = context.read<InventoryBloc>();
                    return Align(
                      alignment: Alignment.centerRight,
                      child: BlocProvider.value(
                        value: bloc,
                        child: const Material(
                          color: Colors.transparent,
                          child: InventoryColumnsPanel(),
                        ),
                      ),
                    );
                  },
                  transitionBuilder:
                      (context, animation, secondaryAnimation, child) {
                        final offset =
                            Tween<Offset>(
                              begin: const Offset(1, 0),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutCubic,
                              ),
                            );

                        return SlideTransition(position: offset, child: child);
                      },
                );
              },
              icon: const Icon(Icons.view_column_outlined, size: 18),
              label: const Text(
                'Add Columns',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDailyOrderExportDialog(BuildContext context) async {
    final bloc = context.read<InventoryBloc>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        backgroundColor: Colors.white,
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text('Loading export dates...'),
          ],
        ),
      ),
    );

    List<String> dates = [];
    Object? loadError;

    try {
      dates = await bloc.repo.fetchDailyOrderExportDates();
    } catch (e) {
      loadError = e;
    }

    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    if (!context.mounted) return;

    if (loadError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load export dates: $loadError')),
      );
      return;
    }

    String? downloadingDate;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              title: Row(
                children: [
                  const Icon(Icons.download_rounded, color: Color(0xFF0D7377)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Daily Order Exports'),
                        Text(
                          '${dates.length} available files',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
              content: SizedBox(
                width: 460,
                height: 520,
                child: dates.isEmpty
                    ? const Center(child: Text('No exported files found'))
                    : ListView.separated(
                        itemCount: dates.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final date = dates[i];
                          final isLoading = downloadingDate == date;

                          return Card(
                            margin: const EdgeInsets.only(top: 12),
                            color: Colors.white,
                            elevation: 6,
                            shadowColor: const Color(
                              0xFF0D7377,
                            ).withOpacity(0.18),
                            shape: RoundedRectangleBorder(
                              side: BorderSide(color: Colors.grey.shade200),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ListTile(
                              leading: const Icon(
                                Icons.calendar_month_rounded,
                                color: Color(0xFF0D7377),
                              ),
                              title: Text(
                                date,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: const Text('Daily order export file'),
                              trailing: isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.file_download_outlined),
                              onTap: downloadingDate != null
                                  ? null
                                  : () async {
                                      setState(() {
                                        downloadingDate = date;
                                      });

                                      try {
                                        final url = await bloc.repo
                                            .fetchDailyOrderExportFileUrl(
                                              runDate: date,
                                            );

                                        if (url == null || url.isEmpty) {
                                          throw Exception(
                                            'Export file not found',
                                          );
                                        }

                                        html.AnchorElement(href: url)
                                          ..setAttribute(
                                            'download',
                                            'daily_order_$date.xlsx',
                                          )
                                          ..click();

                                        if (dialogContext.mounted) {
                                          Navigator.pop(dialogContext);
                                        }
                                      } catch (e) {
                                        if (dialogContext.mounted) {
                                          ScaffoldMessenger.of(
                                            dialogContext,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(e.toString()),
                                            ),
                                          );
                                        }

                                        setState(() {
                                          downloadingDate = null;
                                        });
                                      }
                                    },
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.close),
                  label: const Text('Close'),
                  onPressed: () => Navigator.pop(dialogContext),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBadge() {
    // Initial loading spinner
    if (isLoading) {
      return _Badge(
        key: const ValueKey('initial-load'),
        color: Colors.orange.shade50,
        borderColor: Colors.orange.shade200,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.orange.shade600,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Loading…',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.orange.shade700,
              ),
            ),
          ],
        ),
      );
    }

    // Search result badge
    if (isSearchActive) {
      return _Badge(
        key: ValueKey('search-$total'),
        color: const Color(0xFFF0F7FF),
        borderColor: const Color(0xFF1E3A5F).withOpacity(0.3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search, size: 14, color: Color(0xFF1E3A5F)),
            const SizedBox(width: 6),
            Text(
              '$total result${total == 1 ? '' : 's'}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF1E3A5F),
              ),
            ),
          ],
        ),
      );
    }

    // Background loading — show progress
    if (isBackgroundLoad) {
      return _Badge(
        key: ValueKey('bg-$totalCached'),
        color: const Color(0xFFF0FFF4),
        borderColor: const Color(0xFF22C55E).withOpacity(0.4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.green.shade500,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_fmt(totalCached)} rows',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.green.shade700,
              ),
            ),
          ],
        ),
      );
    }

    // All loaded
    return _Badge(
      key: ValueKey('loaded-$totalCached'),
      color: const Color(0xFF1E3A5F).withOpacity(0.08),
      borderColor: const Color(0xFF1E3A5F).withOpacity(0.2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 16,
            color: Color(0xFF1E3A5F),
          ),
          const SizedBox(width: 6),
          Text(
            '${_fmt(totalCached)} rows',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Color(0xFF1E3A5F),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return '$n';
  }
}

class _Badge extends StatelessWidget {
  final Color color;
  final Color borderColor;
  final Widget child;

  const _Badge({
    super.key,
    required this.color,
    required this.borderColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────
// SEARCH FOOTER
// ─────────────────────────────────────────────
class _SearchFooter extends StatelessWidget {
  final String query;
  final int resultCount;
  final VoidCallback onClear;

  const _SearchFooter({
    required this.query,
    required this.resultCount,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7FF),
        border: Border(top: BorderSide(color: Colors.blue.shade100)),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: Colors.blue.shade400),
          const SizedBox(width: 8),
          Text(
            resultCount == 0
                ? 'No results for "$query"'
                : '$resultCount result${resultCount == 1 ? '' : 's'} for "$query"',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.blue.shade700,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.close, size: 14),
            label: const Text('Clear search'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.blue.shade600,
              textStyle: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// PAGINATION BAR
// ─────────────────────────────────────────────
class _PaginationBar extends StatelessWidget {
  final int page;
  final int totalPages;
  final int total;
  final int fromIdx;
  final int toIdx;
  final bool isLoading;
  final void Function(int page) onGo;

  const _PaginationBar({
    required this.page,
    required this.totalPages,
    required this.total,
    required this.fromIdx,
    required this.toIdx,
    required this.isLoading,
    required this.onGo,
  });

  List<int?> _pageNumbers() {
    if (totalPages <= 7) return List.generate(totalPages, (i) => i);
    if (page <= 3) {
      return [0, 1, 2, 3, 4, null, totalPages - 1];
    } else if (page >= totalPages - 4) {
      return [
        0,
        null,
        totalPages - 5,
        totalPages - 4,
        totalPages - 3,
        totalPages - 2,
        totalPages - 1,
      ];
    } else {
      return [0, null, page - 1, page, page + 1, null, totalPages - 1];
    }
  }

  @override
  Widget build(BuildContext context) {
    final numbers = _pageNumbers();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            total == 0 ? 'No data' : 'Showing ${fromIdx + 1}–$toIdx of $total',
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),

          const Spacer(),

          _NavBtn(
            icon: Icons.first_page,
            tooltip: 'First page',
            disabled: page == 0,
            onTap: () => onGo(0),
          ),
          const SizedBox(width: 4),
          _NavBtn(
            icon: Icons.chevron_left,
            tooltip: 'Previous',
            disabled: page == 0,
            onTap: () => onGo(page - 1),
          ),
          const SizedBox(width: 8),

          ...numbers.map((n) {
            if (n == null) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '…',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              );
            }
            final isActive = n == page;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                onTap: isActive ? null : () => onGo(n),
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFF1E3A5F)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: isActive
                        ? null
                        : Border.all(color: Colors.grey.shade200),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${n + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isActive ? Colors.white : Colors.grey.shade700,
                    ),
                  ),
                ),
              ),
            );
          }),

          const SizedBox(width: 8),
          _NavBtn(
            icon: Icons.chevron_right,
            tooltip: 'Next',
            disabled: page >= totalPages - 1,
            onTap: () => onGo(page + 1),
          ),
          const SizedBox(width: 4),
          _NavBtn(
            icon: Icons.last_page,
            tooltip: 'Last page',
            disabled: page >= totalPages - 1,
            onTap: () => onGo(totalPages - 1),
          ),

          const Spacer(),

          Text(
            'Page ${page + 1} of $totalPages',
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool disabled;
  final VoidCallback onTap;

  const _NavBtn({
    required this.icon,
    required this.tooltip,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 18,
            color: disabled ? Colors.grey.shade300 : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// EXPORT OVERLAY
// ─────────────────────────────────────────────
class _ExportOverlay extends StatelessWidget {
  final InventoryState state;
  const _ExportOverlay({required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.3),
      child: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 30),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      strokeWidth: 5,
                      value:
                          (state.importProgress > 0 && state.importProgress < 1)
                          ? state.importProgress
                          : null,
                      color: const Color(0xFF0D7377),
                    ),
                    if (state.importProgress > 0 && state.importProgress < 1)
                      Text(
                        '${(state.importProgress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                state.exportMessage ?? 'Exporting…',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
