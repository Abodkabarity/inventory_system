import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../orders/widgets/orders_grid_controller.dart';
import '../../orders/widgets/orders_table.dart';
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

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, state) {
        final columns = state.columnOrder.isEmpty
            ? OrdersTable.allColumns
            : state.columnOrder;

        final visible = state.visibleColumns.isEmpty
            ? OrdersTable.allColumns
            : state.visibleColumns;

        final finalColumns = columns
            .where((c) => visible.contains(c) && c != 'additional_request')
            .toList();

        final isSearching = searchController.text.trim().isNotEmpty;
        final allRows = state.allOrders;
        final total = allRows.length;
        final totalCached = state.cachedOrders.length;

        // When searching: show all results without pagination
        // When browsing: paginate cachedOrders
        final int page = isSearching ? 0 : state.currentOrdersPage;
        final int totalPages = isSearching
            ? 1
            : (totalCached == 0 ? 1 : (totalCached / _pageSize).ceil());
        final int safePage = page.clamp(0, totalPages - 1);
        final int fromIdx = isSearching ? 0 : safePage * _pageSize;
        final int toIdx = isSearching
            ? total
            : ((safePage + 1) * _pageSize).clamp(0, total);

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
                  ),

                  const SizedBox(height: 12),

                  // TABLE
                  Expanded(
                    child: InventoryOrdersTable(
                      rows: List.from(allRows),
                      isLoading: state.isOrdersLoading,
                      orderedColumns: finalColumns,
                      columnWidths: {},
                      onColumnResized: (_, __) {},
                    ),
                  ),

                  // PAGINATION — hidden while searching
                  if (!isSearching)
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
                  if (isSearching)
                    _SearchFooter(
                      query: searchController.text.trim(),
                      resultCount: total,
                      onClear: _clearSearch,
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
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── SEARCH FIELD ────────────────────────────────────
        Expanded(
          child: SizedBox(
            height: 42,
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                hintText: 'Search item name / code / branch / barcode…',
                hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
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
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: Color(0xFF1E3A5F),
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
                    context.read<InventoryBloc>().add(
                      ExportInventoryOrders(
                        runDate: runDate,
                        visibleColumns: finalColumns,
                      ),
                    );
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
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1E3A5F),
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (ctx) {
                  final bloc = context.read<InventoryBloc>();
                  return BlocProvider.value(
                    value: bloc,
                    child: const InventoryColumnsPanel(),
                  );
                },
              );
            },
            icon: const Icon(Icons.view_column_outlined, size: 18),
            label: const Text('Columns', style: TextStyle(fontSize: 13)),
          ),
        ),
      ],
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
