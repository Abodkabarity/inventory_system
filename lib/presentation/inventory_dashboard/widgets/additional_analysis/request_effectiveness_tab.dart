// lib/presentation/inventory/widgets/additional_analysis/request_effectiveness_tab.dart

import 'package:daily_order/presentation/inventory_dashboard/widgets/additional_analysis/product_effectiveness_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/request_effectiveness_row.dart';
import '../../bloc/inventory_bloc.dart';
import '../../bloc/inventory_event.dart';
import '../../bloc/inventory_state.dart';
import 'branch_effectiveness_dialog.dart';
import 'glass_container.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────

class RequestEffectivenessTab extends StatefulWidget {
  final DateTime from;
  final DateTime to;

  const RequestEffectivenessTab({
    super.key,
    required this.from,
    required this.to,
  });

  @override
  State<RequestEffectivenessTab> createState() =>
      _RequestEffectivenessTabState();
}

class _RequestEffectivenessTabState extends State<RequestEffectivenessTab> {
  String? _selectedBranch;
  String _search = '';
  String _statusFilter = 'all';
  String _sortCol = 'request_date';
  bool _sortAsc = false;
  int _page = 0;
  static const int _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RequestEffectivenessTab old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from || old.to != widget.to) {
      _selectedBranch = null;
      _load();
    }
  }

  void _load() {
    context.read<InventoryBloc>().add(
      LoadRequestEffectiveness(
        from: widget.from,
        to: widget.to,
        branch: _selectedBranch,
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static const _statusColor = {
    'sold_within_3d': Color(0xff10B981),
    'sold_after_3d': Color(0xffF59E0B),
    'not_sold': Color(0xffEF4444),
  };

  static const _statusLabel = {
    'sold_within_3d': 'Sold ≤ 3 Days',
    'sold_after_3d': 'Sold > 3 Days',
    'not_sold': 'Not Sold',
  };

  Color _statusChipColor(String s) =>
      _statusColor[s] ?? const Color(0xff94A3B8);
  String _statusChipLabel(String s) => _statusLabel[s] ?? s;

  List<RequestEffectivenessRow> _applyFilters(
    List<RequestEffectivenessRow> rows,
  ) {
    var list = rows;

    // status filter
    if (_statusFilter != 'all') {
      list = list.where((r) => r.effectivenessStatus == _statusFilter).toList();
    }

    // branch filter
    if (_selectedBranch != null) {
      list = list.where((r) => r.branchName == _selectedBranch).toList();
    }

    // text search
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where(
            (r) =>
                r.itemName.toLowerCase().contains(q) ||
                r.itemCode.toLowerCase().contains(q) ||
                r.branchName.toLowerCase().contains(q),
          )
          .toList();
    }

    // sort
    list.sort((a, b) {
      int cmp;
      switch (_sortCol) {
        case 'branch':
          cmp = a.branchName.compareTo(b.branchName);
        case 'item':
          cmp = a.itemName.compareTo(b.itemName);
        case 'request_qty':
          cmp = a.requestQty.compareTo(b.requestQty);
        case 'sold_qty':
          cmp = a.totalSoldQty.compareTo(b.totalSoldQty);
        case 'days_elapsed':
          cmp = a.daysElapsed.compareTo(b.daysElapsed);
        case 'days_to_sale':
          cmp = (a.daysToFirstSale ?? 999).compareTo(b.daysToFirstSale ?? 999);
        case 'sold_pct':
          cmp = a.soldPct.compareTo(b.soldPct);
        default: // request_date
          cmp = a.requestDate.compareTo(b.requestDate);
      }
      return _sortAsc ? cmp : -cmp;
    });

    return list;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      buildWhen: (p, c) =>
          p.requestEffectiveness != c.requestEffectiveness ||
          p.isEffectivenessLoading != c.isEffectivenessLoading,
      builder: (context, state) {
        if (state.isEffectivenessLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xff06B6D4)),
          );
        }

        final data = state.requestEffectiveness;

        if (data.isEmpty) {
          return _EmptyPlaceholder(onReload: _load);
        }

        final summary = Map<String, dynamic>.from(
          data['summary'] as Map? ?? {},
        );
        final rawRows = List<Map<String, dynamic>>.from(
          data['rows'] as List? ?? [],
        );
        final branchEff = List<Map<String, dynamic>>.from(
          data['branch_effectiveness'] as List? ?? [],
        );
        final productEffectiveness = List<Map<String, dynamic>>.from(
          data['product_effectiveness'] as List? ?? [],
        );
        final weeklyTrend = List<Map<String, dynamic>>.from(
          data['weekly_trend'] as List? ?? [],
        );

        final rows = rawRows.map(RequestEffectivenessRow.fromMap).toList();

        final filtered = _applyFilters(rows);
        final pageCount = (filtered.length / _pageSize).ceil().clamp(1, 9999);
        final safePage = _page.clamp(0, pageCount - 1);
        final pageRows = filtered.isEmpty
            ? <RequestEffectivenessRow>[]
            : filtered.sublist(
                safePage * _pageSize,
                (safePage * _pageSize + _pageSize).clamp(0, filtered.length),
              );

        // unique branches for dropdown
        final branches = rows.map((r) => r.branchName).toSet().toList()..sort();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── KPI row ────────────────────────────────────────────────
              _KpiRow(summary: summary),
              const SizedBox(height: 24),

              // ── Trend + Branch leaderboard ─────────────────────────────
              SizedBox(
                height: 600,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: _BranchEffCard(branches: branchEff),
                    ),

                    const SizedBox(width: 20),

                    Expanded(
                      flex: 3,
                      child: ProductEffectivenessCard(
                        products: productEffectiveness,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Main table ─────────────────────────────────────────────
              _TableCard(
                rows: pageRows,
                allRows: filtered,
                branches: branches,
                selectedBranch: _selectedBranch,
                search: _search,
                statusFilter: _statusFilter,
                sortCol: _sortCol,
                sortAsc: _sortAsc,
                page: safePage,
                pageCount: pageCount,
                onBranchChanged: (v) => setState(() {
                  _selectedBranch = v;
                  _page = 0;
                }),
                onSearchChanged: (v) => setState(() {
                  _search = v;
                  _page = 0;
                }),
                onStatusChanged: (v) => setState(() {
                  _statusFilter = v;
                  _page = 0;
                }),
                onSort: (col) => setState(() {
                  if (_sortCol == col) {
                    _sortAsc = !_sortAsc;
                  } else {
                    _sortCol = col;
                    _sortAsc = false;
                  }
                  _page = 0;
                }),
                onPageChanged: (p) => setState(() => _page = p),
                onReload: _load,
              ),

              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI ROW
// ─────────────────────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  final Map<String, dynamic> summary;
  const _KpiRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final total = summary['total_requests'] ?? 0;
    final within3 = summary['sold_within_3d'] ?? 0;
    final after3 = summary['sold_after_3d'] ?? 0;
    final notSold = summary['not_sold'] ?? 0;
    final effRate = (summary['effectiveness_rate'] ?? 0) as num;
    final quickRate = (summary['quick_sell_rate'] ?? 0) as num;
    final avgDays = summary['avg_days_to_first_sale'];
    final avgSold = (summary['avg_sold_pct'] ?? 0) as num;

    return Column(
      children: [
        Row(
          children: [
            _kpi(
              'Total Requests',
              '$total',
              const Color(0xff06B6D4),
              Icons.analytics_outlined,
            ),
            const SizedBox(width: 16),
            _kpi(
              'Sold Within 3 Days',
              '$within3',
              const Color(0xff10B981),
              Icons.bolt,
            ),
            const SizedBox(width: 16),
            _kpi(
              'Sold After 3 Days',
              '$after3',
              const Color(0xffF59E0B),
              Icons.schedule,
            ),
            const SizedBox(width: 16),
            _kpi(
              'Not Sold',
              '$notSold',
              const Color(0xffEF4444),
              Icons.remove_shopping_cart_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _kpi(
              'Sales Success Rate',
              '${effRate.toStringAsFixed(1)}%',
              const Color(0xff8B5CF6),
              Icons.verified_outlined,
            ),
            const SizedBox(width: 16),
            _kpi(
              'Quick-Sell Rate',
              '${quickRate.toStringAsFixed(1)}%',
              const Color(0xff14B8A6),
              Icons.rocket_launch_outlined,
            ),
            const SizedBox(width: 16),
            _kpi(
              'Average Days To Sale',
              avgDays != null
                  ? '${(avgDays as num).toStringAsFixed(1)} d'
                  : '—',
              const Color(0xffF97316),
              Icons.timer_outlined,
            ),
            const SizedBox(width: 16),
            _kpi(
              'Quantity Sold %',
              '${avgSold.toStringAsFixed(1)}%',
              const Color(0xff3B82F6),
              Icons.percent,
            ),
          ],
        ),
      ],
    );
  }

  Widget _kpi(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: GlassContainer(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xff64748B),
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WEEKLY TREND CARD  (simple bar chart drawn with CustomPaint)
// ─────────────────────────────────────────────────────────────────────────────

class _WeeklyTrendCard extends StatelessWidget {
  final List<Map<String, dynamic>> trend;
  const _WeeklyTrendCard({required this.trend});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.show_chart,
            'Weekly Sales Performance',
            const Color(0xff3B82F6),
          ),
          const SizedBox(height: 20),
          if (trend.isEmpty)
            const Expanded(child: _EmptyState())
          else
            Expanded(child: _TrendBars(trend: trend)),
        ],
      ),
    );
  }
}

class _TrendBars extends StatelessWidget {
  final List<Map<String, dynamic>> trend;
  const _TrendBars({required this.trend});

  @override
  Widget build(BuildContext context) {
    final maxTotal = trend.fold<num>(
      1,
      (m, e) => ((e['total'] as num?) ?? 0) > m ? (e['total'] as num) : m,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: trend.map((w) {
        final total = (w['total'] as num?) ?? 0;
        final sold3 = (w['sold_3d'] as num?) ?? 0;
        final notSold = (w['not_sold'] as num?) ?? 0;
        final effRate = (w['effectiveness_rate'] as num?) ?? 0;
        final barH = total == 0
            ? 4.0
            : (total / maxTotal * 200).clamp(4, 200).toDouble();
        final week = (w['week'] as String?)?.substring(5) ?? ''; // MM-DD

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Tooltip(
              message:
                  'Week: $week\nRequests: $total\nSold Fast: $sold3\nNot Sold: $notSold\nSuccess Rate: ${effRate.toStringAsFixed(1)}%',
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${effRate.toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xff64748B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: barH,
                      child: Column(
                        children: [
                          // "sold ≤3d" portion (green)
                          Container(color: const Color(0xff10B981)),

                          Container(color: const Color(0xffF59E0B)),

                          Container(color: const Color(0xffEF4444)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    week,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xff94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BRANCH EFFECTIVENESS LEADERBOARD
// ─────────────────────────────────────────────────────────────────────────────

class _BranchEffCard extends StatelessWidget {
  final List<Map<String, dynamic>> branches;
  const _BranchEffCard({required this.branches});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.leaderboard_outlined,
            'Branch Sales Success',
            const Color(0xff10B981),
          ),
          const SizedBox(height: 12),
          if (branches.isEmpty)
            const Expanded(child: _EmptyState())
          else
            Expanded(
              child: ListView.builder(
                itemCount: branches.length,
                itemBuilder: (_, i) {
                  final b = branches[i];
                  final rate = (b['effectiveness_rate'] as num?) ?? 0;
                  final color = rate >= 70
                      ? const Color(0xff10B981)
                      : rate >= 40
                      ? const Color(0xffF59E0B)
                      : const Color(0xffEF4444);

                  return InkWell(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => BranchEffectivenessDialog(
                          branchName: b['branch_name'] ?? '',

                          products: List<Map<String, dynamic>>.from(
                            b['products'] ?? [],
                          ),
                        ),
                      );
                    },

                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 35,
                            child: Text(
                              '#${i + 1}',
                              style: const TextStyle(
                                color: Color(0xff94A3B8),
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            flex: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),

                              decoration: BoxDecoration(
                                color: Colors.white,

                                borderRadius: BorderRadius.circular(12),

                                border: Border.all(
                                  color: const Color(0xffE2E8F0),
                                  width: 1,
                                ),

                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.03),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    b['branch_name']?.toString() ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xff0F172A),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                    ),
                                  ),

                                  const SizedBox(height: 6),

                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(5),
                                    child: LinearProgressIndicator(
                                      value: (rate / 100).clamp(0.0, 1.0),
                                      minHeight: 8,
                                      backgroundColor: const Color(0xffE2E8F0),
                                      color: color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${rate.toStringAsFixed(1)}%',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WORST ITEMS CARD
// ─────────────────────────────────────────────────────────────────────────────

class _WorstItemsCard extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _WorstItemsCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.warning_amber_rounded,
            'Repeatedly Unrequired Products (≥ 2 Unsold Requests)',
            const Color(0xffEF4444),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: items.map((item) {
              final rate = (item['not_sold_rate'] as num?) ?? 0;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xffFFF5F5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xffFECACA),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.medication,
                      color: Color(0xffEF4444),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['item_name']?.toString() ?? '',
                          style: const TextStyle(
                            color: Color(0xff1E293B),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          item['item_code']?.toString() ?? '',
                          style: const TextStyle(
                            color: Color(0xff94A3B8),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xffEF4444).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${item['not_sold_count']} unsold / ${item['total_requests']} total',
                        style: const TextStyle(
                          color: Color(0xffEF4444),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xffFEF2F2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${rate.toStringAsFixed(0)}% fail',
                        style: const TextStyle(
                          color: Color(0xffB91C1C),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN DATA TABLE
// ─────────────────────────────────────────────────────────────────────────────

class _TableCard extends StatelessWidget {
  final List<RequestEffectivenessRow> rows;
  final List<RequestEffectivenessRow> allRows;
  final List<String> branches;
  final String? selectedBranch;
  final String search;
  final String statusFilter;
  final String sortCol;
  final bool sortAsc;
  final int page;
  final int pageCount;
  final ValueChanged<String?> onBranchChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onSort;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onReload;

  const _TableCard({
    required this.rows,
    required this.allRows,
    required this.branches,
    required this.selectedBranch,
    required this.search,
    required this.statusFilter,
    required this.sortCol,
    required this.sortAsc,
    required this.page,
    required this.pageCount,
    required this.onBranchChanged,
    required this.onSearchChanged,
    required this.onStatusChanged,
    required this.onSort,
    required this.onPageChanged,
    required this.onReload,
  });

  static const _statusColor = {
    'sold_within_3d': Color(0xff10B981),
    'sold_after_3d': Color(0xffF59E0B),
    'not_sold': Color(0xffEF4444),
  };

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header + filters ──────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _sectionHeader(
                  Icons.table_rows_outlined,
                  'Request Sales Details',
                  const Color(0xff06B6D4),
                ),
              ),
              const Spacer(),
              // Status filter chips
              _FilterChip(
                label: 'All',
                selected: statusFilter == 'all',
                color: const Color(0xff64748B),
                onTap: () => onStatusChanged('all'),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Sold ≤ 3d',
                selected: statusFilter == 'sold_within_3d',
                color: const Color(0xff10B981),
                onTap: () => onStatusChanged('sold_within_3d'),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Sold > 3d',
                selected: statusFilter == 'sold_after_3d',
                color: const Color(0xffF59E0B),
                onTap: () => onStatusChanged('sold_after_3d'),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: 'Not Sold',
                selected: statusFilter == 'not_sold',
                color: const Color(0xffEF4444),
                onTap: () => onStatusChanged('not_sold'),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Search + branch filter ────────────────────────────────────
          Row(
            children: [
              // Search
              SizedBox(
                width: 260,
                child: TextField(
                  onChanged: onSearchChanged,
                  style: const TextStyle(
                    color: Color(0xff1E293B),
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search item or branch...',
                    hintStyle: const TextStyle(
                      color: Color(0xff94A3B8),
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Color(0xff94A3B8),
                      size: 18,
                    ),
                    filled: true,
                    fillColor: const Color(0xffF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Branch dropdown
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xffF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xffE2E8F0)),
                ),
                child: DropdownButton<String?>(
                  value: selectedBranch,
                  underline: const SizedBox(),
                  isDense: true,
                  hint: const Text(
                    'All Branches',
                    style: TextStyle(color: Color(0xff64748B), fontSize: 13),
                  ),
                  dropdownColor: Colors.white,
                  style: const TextStyle(
                    color: Color(0xff1E293B),
                    fontSize: 13,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('All Branches'),
                    ),
                    ...branches.map(
                      (b) =>
                          DropdownMenuItem<String?>(value: b, child: Text(b)),
                    ),
                  ],
                  onChanged: onBranchChanged,
                ),
              ),
              const Spacer(),
              Text(
                '${allRows.length} records',
                style: const TextStyle(color: Color(0xff94A3B8), fontSize: 12),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onReload,
                icon: const Icon(
                  Icons.refresh,
                  color: Color(0xff64748B),
                  size: 18,
                ),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Table ─────────────────────────────────────────────────────
          rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'No records match filters.',
                      style: TextStyle(color: Color(0xff94A3B8)),
                    ),
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: const WidgetStatePropertyAll(
                      Color(0xffF1F5F9),
                    ),
                    dataRowColor: const WidgetStatePropertyAll(Colors.white),
                    dividerThickness: 1,
                    horizontalMargin: 12,
                    columnSpacing: 20,
                    headingTextStyle: const TextStyle(
                      color: Color(0xff64748B),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                    columns: [
                      _col('Date', 'request_date', sortCol, sortAsc, onSort),
                      _col('Branch', 'branch', sortCol, sortAsc, onSort),
                      _col(
                        'Item',
                        'item',
                        sortCol,
                        sortAsc,
                        onSort,
                        width: 200,
                      ),
                      _col('Req Qty', 'request_qty', sortCol, sortAsc, onSort),
                      _col('Sold Qty', 'sold_qty', sortCol, sortAsc, onSort),
                      _col('Sold %', 'sold_pct', sortCol, sortAsc, onSort),
                      _col(
                        'Days Elapsed',
                        'days_elapsed',
                        sortCol,
                        sortAsc,
                        onSort,
                      ),
                      _col(
                        'Days to Sale',
                        'days_to_sale',
                        sortCol,
                        sortAsc,
                        onSort,
                      ),
                      const DataColumn(label: Text('Status')),
                    ],
                    rows: rows.map((r) {
                      final sc =
                          _statusColor[r.effectivenessStatus] ??
                          const Color(0xff94A3B8);
                      return DataRow(
                        cells: [
                          DataCell(
                            Text(
                              r.requestDate,
                              style: const TextStyle(
                                color: Color(0xff64748B),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              r.branchName,
                              style: const TextStyle(
                                color: Color(0xff1E293B),
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 200,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    r.itemName,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xff1E293B),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    r.itemCode,
                                    style: const TextStyle(
                                      color: Color(0xff94A3B8),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${r.requestQty}',
                              style: const TextStyle(
                                color: Color(0xff64748B),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${r.totalSoldQty}',
                              style: TextStyle(
                                color: r.totalSoldQty > 0
                                    ? const Color(0xff10B981)
                                    : const Color(0xffEF4444),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          DataCell(_PctBar(pct: r.soldPct)),
                          DataCell(
                            Text(
                              '${r.daysElapsed}d',
                              style: TextStyle(
                                color: r.daysElapsed >= 45
                                    ? const Color(0xffEF4444)
                                    : const Color(0xff64748B),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          DataCell(
                            r.daysToFirstSale != null
                                ? Text(
                                    '${r.daysToFirstSale}d',
                                    style: TextStyle(
                                      color: r.daysToFirstSale! <= 3
                                          ? const Color(0xff10B981)
                                          : const Color(0xffF59E0B),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  )
                                : const Text(
                                    '—',
                                    style: TextStyle(
                                      color: Color(0xffCBD5E1),
                                      fontSize: 12,
                                    ),
                                  ),
                          ),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: sc.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: sc.withOpacity(0.3)),
                              ),
                              child: Text(
                                r.effectivenessLabel,
                                style: TextStyle(
                                  color: sc,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),

          // ── Pagination ────────────────────────────────────────────────
          if (pageCount > 1) ...[
            const SizedBox(height: 12),
            _Pagination(
              page: page,
              pageCount: pageCount,
              onChanged: onPageChanged,
            ),
          ],
        ],
      ),
    );
  }

  DataColumn _col(
    String label,
    String key,
    String sortCol,
    bool sortAsc,
    ValueChanged<String> onSort, {
    double? width,
  }) {
    final active = sortCol == key;
    return DataColumn(
      label: GestureDetector(
        onTap: () => onSort(key),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (width != null)
              SizedBox(width: width, child: Text(label))
            else
              Text(label),
            const SizedBox(width: 4),
            Icon(
              active
                  ? (sortAsc ? Icons.arrow_upward : Icons.arrow_downward)
                  : Icons.unfold_more,
              size: 12,
              color: active ? const Color(0xff06B6D4) : const Color(0xffCBD5E1),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _PctBar extends StatelessWidget {
  final num pct;
  const _PctBar({required this.pct});

  @override
  Widget build(BuildContext context) {
    final v = pct.clamp(0, 100).toDouble() / 100;
    final color = v >= 0.7
        ? const Color(0xff10B981)
        : v >= 0.3
        ? const Color(0xffF59E0B)
        : const Color(0xffEF4444);

    return Row(
      children: [
        SizedBox(
          width: 60,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 8,
              backgroundColor: const Color(0xffE2E8F0),
              color: color,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${pct.toStringAsFixed(0)}%',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : const Color(0xffF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color.withOpacity(0.4) : const Color(0xffE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? color : const Color(0xff64748B),
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  final int page;
  final int pageCount;
  final ValueChanged<int> onChanged;
  const _Pagination({
    required this.page,
    required this.pageCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: page > 0 ? () => onChanged(page - 1) : null,
          icon: const Icon(Icons.chevron_left),
          color: const Color(0xff06B6D4),
        ),
        Text(
          'Page ${page + 1} of $pageCount',
          style: const TextStyle(color: Color(0xff64748B), fontSize: 13),
        ),
        IconButton(
          onPressed: page < pageCount - 1 ? () => onChanged(page + 1) : null,
          icon: const Icon(Icons.chevron_right),
          color: const Color(0xff06B6D4),
        ),
      ],
    );
  }
}

class _EmptyPlaceholder extends StatelessWidget {
  final VoidCallback onReload;
  const _EmptyPlaceholder({required this.onReload});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.analytics_outlined,
            color: Color(0xffCBD5E1),
            size: 64,
          ),
          const SizedBox(height: 16),
          const Text(
            'No effectiveness data for this period.',
            style: TextStyle(color: Color(0xff94A3B8), fontSize: 16),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onReload,
            icon: const Icon(Icons.refresh, color: Color(0xff06B6D4)),
            label: const Text(
              'Reload',
              style: TextStyle(color: Color(0xff06B6D4)),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, color: Color(0xffCBD5E1), size: 36),
          SizedBox(height: 8),
          Text(
            'No data available',
            style: TextStyle(color: Color(0xff94A3B8), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED HELPER
// ─────────────────────────────────────────────────────────────────────────────

Widget _sectionHeader(IconData icon, String title, Color color) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
      const SizedBox(width: 10),
      Text(
        title,
        style: const TextStyle(
          color: Color(0xff1E293B),
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    ],
  );
}
