// lib/presentation/inventory/widgets/additional_analysis/request_effectiveness_tab.dart

import 'package:daily_order/presentation/inventory_dashboard/widgets/additional_analysis/product_effectiveness_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/additional_analysis_excel_exporter.dart';
import '../../../../core/utils/order_edit_analysis_excel_exporter.dart';
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
  final bool orderEditMode;

  const RequestEffectivenessTab({
    super.key,
    required this.from,
    required this.to,
    this.orderEditMode = false,
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
    final bloc = context.read<InventoryBloc>();
    if (widget.orderEditMode) {
      bloc.add(
        LoadOrderEditSalesPerformance(
          from: widget.from,
          to: widget.to,
          branch: _selectedBranch,
        ),
      );
      return;
    }

    bloc.add(
      LoadRequestEffectiveness(
        from: widget.from,
        to: widget.to,
        branch: _selectedBranch,
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

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
        case 'remaining_qty':
          cmp = a.remainingAddedQty.compareTo(b.remainingAddedQty);
        case 'sale_count':
          cmp = a.saleCount.compareTo(b.saleCount);
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
      buildWhen: (p, c) {
        if (widget.orderEditMode) {
          return p.orderEditSalesPerformance != c.orderEditSalesPerformance ||
              p.isOrderEditSalesLoading != c.isOrderEditSalesLoading;
        }

        return p.requestEffectiveness != c.requestEffectiveness ||
            p.isEffectivenessLoading != c.isEffectivenessLoading;
      },
      builder: (context, state) {
        final isLoading = widget.orderEditMode
            ? state.isOrderEditSalesLoading
            : state.isEffectivenessLoading;
        final data = widget.orderEditMode
            ? state.orderEditSalesPerformance
            : state.requestEffectiveness;

        if (isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xff06B6D4)),
          );
        }

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
        final worstItems = productEffectiveness
            .where((p) {
              final notSold =
                  (p['not_sold_count'] as num?) ?? (p['not_sold'] as num?) ?? 0;
              return notSold >= 2;
            })
            .take(12)
            .toList();

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
              _SalesExportBar(
                data: data,
                from: widget.from,
                to: widget.to,
                branch: _selectedBranch,
                search: _search,
                statusFilter: _statusFilter,
                orderEditMode: widget.orderEditMode,
              ),
              const SizedBox(height: 18),
              _KpiRow(summary: summary, orderEditMode: widget.orderEditMode),
              const SizedBox(height: 24),

              // ── Trend + Branch leaderboard ─────────────────────────────
              SizedBox(
                height: widget.orderEditMode ? 660 : 600,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 4,
                      child: widget.orderEditMode
                          ? _OrderEditBranchMonitorCard(branches: branchEff)
                          : _BranchEffCard(branches: branchEff),
                    ),

                    const SizedBox(width: 20),

                    Expanded(
                      flex: 3,
                      child: widget.orderEditMode
                          ? _OrderEditProductMonitorCard(
                              products: productEffectiveness,
                            )
                          : ProductEffectivenessCard(
                              products: productEffectiveness,
                            ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Main table ─────────────────────────────────────────────
              if (!widget.orderEditMode) ...[
                SizedBox(
                  height: 320,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _WeeklyTrendCard(trend: weeklyTrend)),
                      const SizedBox(width: 20),
                      Expanded(child: _WorstItemsCard(items: worstItems)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

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
                orderEditMode: widget.orderEditMode,
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

class _SalesExportBar extends StatelessWidget {
  final Map<String, dynamic> data;
  final DateTime from;
  final DateTime to;
  final String? branch;
  final String search;
  final String statusFilter;
  final bool orderEditMode;

  const _SalesExportBar({
    required this.data,
    required this.from,
    required this.to,
    required this.branch,
    required this.search,
    required this.statusFilter,
    required this.orderEditMode,
  });

  @override
  Widget build(BuildContext context) {
    final title = orderEditMode
        ? 'Order Edit Sales Monitoring Report'
        : 'Manager Sales Performance Report';
    final subtitle = orderEditMode
        ? 'Export branches, added products, added qty, sold qty, remaining qty, first and last sales.'
        : 'Export branch-level sales success, product performance, weekly trend, and request-level sell-through details.';

    return GlassContainer(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xffDCFCE7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.mark_email_read_rounded,
              color: Color(0xff16A34A),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () {
              if (orderEditMode) {
                OrderEditAnalysisExcelExporter.exportSalesPerformance(
                  data: data,
                  from: from,
                  to: to,
                  branch: branch,
                  search: search,
                  statusFilter: statusFilter,
                );
                return;
              }

              AdditionalAnalysisExcelExporter.exportSalesPerformance(
                data: data,
                from: from,
                to: to,
                branch: branch,
                search: search,
                statusFilter: statusFilter,
              );
            },
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: const Color(0xff166534),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text(
              'Export Sales Report',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiRow extends StatelessWidget {
  final Map<String, dynamic> summary;
  final bool orderEditMode;
  const _KpiRow({required this.summary, this.orderEditMode = false});

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
              orderEditMode ? 'Positive Edits' : 'Total Requests',
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
              orderEditMode ? 'Added Qty Sold %' : 'Quantity Sold %',
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
        final soldAfter = (w['sold_after_3d'] as num?) ?? 0;
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
                          if (sold3 > 0)
                            Expanded(
                              flex: sold3.toInt(),
                              child: Container(color: const Color(0xff10B981)),
                            ),
                          if (soldAfter > 0)
                            Expanded(
                              flex: soldAfter.toInt(),
                              child: Container(color: const Color(0xffF59E0B)),
                            ),
                          if (notSold > 0)
                            Expanded(
                              flex: notSold.toInt(),
                              child: Container(color: const Color(0xffEF4444)),
                            ),
                          if (sold3 == 0 && soldAfter == 0 && notSold == 0)
                            Expanded(
                              child: Container(color: const Color(0xffCBD5E1)),
                            ),
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

class _OrderEditBranchMonitorCard extends StatelessWidget {
  final List<Map<String, dynamic>> branches;
  const _OrderEditBranchMonitorCard({required this.branches});

  @override
  Widget build(BuildContext context) {
    final rows = [...branches]
      ..sort(
        (a, b) =>
            _asNum(b['total_requests']).compareTo(_asNum(a['total_requests'])),
      );

    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.storefront_outlined,
            'Branch Edit Sales Monitor',
            const Color(0xff0EA5E9),
          ),
          const SizedBox(height: 8),
          const Text(
            'Positive final reorder edits by branch, with sold and remaining added quantity.',
            style: TextStyle(color: Color(0xff64748B), fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            const Expanded(child: _EmptyState())
          else
            Expanded(
              child: ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final row = rows[index];
                  final rate = _asNum(row['effectiveness_rate']);
                  final remaining = _asNum(row['remaining_added_qty']);
                  final color = remaining > 0
                      ? const Color(0xffF97316)
                      : const Color(0xff10B981);

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xffE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.035),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                row['branch_name']?.toString() ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xff0F172A),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            _smallPill(
                              '${rate.toStringAsFixed(1)}% sold',
                              const Color(0xff10B981),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _miniMetric(
                              'Edits',
                              _fmtQty(row['total_requests']),
                              const Color(0xff3B82F6),
                            ),
                            _miniMetric(
                              'Products',
                              _fmtQty(row['products_count']),
                              const Color(0xff8B5CF6),
                            ),
                            _miniMetric(
                              'Added',
                              _fmtQty(row['total_request_qty']),
                              const Color(0xff0EA5E9),
                            ),
                            _miniMetric(
                              'Sold',
                              _fmtQty(row['total_sold_qty']),
                              const Color(0xff10B981),
                            ),
                            _miniMetric('Remaining', _fmtQty(remaining), color),
                          ],
                        ),
                        if ((row['last_sale_date']?.toString() ?? '')
                            .isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Last sale: ${row['last_sale_date']}',
                            style: const TextStyle(
                              color: Color(0xff64748B),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
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

class _OrderEditProductMonitorCard extends StatelessWidget {
  final List<Map<String, dynamic>> products;
  const _OrderEditProductMonitorCard({required this.products});

  @override
  Widget build(BuildContext context) {
    final rows = [...products]
      ..sort(
        (a, b) => _asNum(
          b['remaining_added_qty'],
        ).compareTo(_asNum(a['remaining_added_qty'])),
      );

    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.inventory_2_outlined,
            'Product Follow Up',
            const Color(0xffF97316),
          ),
          const SizedBox(height: 8),
          const Text(
            'Products with added quantity, sold quantity, and remaining quantity to watch.',
            style: TextStyle(color: Color(0xff64748B), fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (rows.isEmpty)
            const Expanded(child: _EmptyState())
          else
            Expanded(
              child: ListView.separated(
                itemCount: rows.length.clamp(0, 40),
                separatorBuilder: (_, __) => const Divider(height: 18),
                itemBuilder: (_, index) {
                  final row = rows[index];
                  final added = _asNum(row['total_request_qty']);
                  final sold = _asNum(row['total_sold_qty']);
                  final remaining = _asNum(row['remaining_added_qty']);
                  final pct = added <= 0
                      ? 0
                      : (sold / added * 100).clamp(0, 100);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row['item_name']?.toString() ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff0F172A),
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        row['item_code']?.toString() ?? '',
                        style: const TextStyle(
                          color: Color(0xff64748B),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 9),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: (pct / 100).toDouble(),
                          minHeight: 7,
                          backgroundColor: const Color(0xffE2E8F0),
                          color: remaining > 0
                              ? const Color(0xffF97316)
                              : const Color(0xff10B981),
                        ),
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _smallPill(
                            'Added ${_fmtQty(added)}',
                            const Color(0xff0EA5E9),
                          ),
                          _smallPill(
                            'Sold ${_fmtQty(sold)}',
                            const Color(0xff10B981),
                          ),
                          _smallPill(
                            'Remaining ${_fmtQty(remaining)}',
                            remaining > 0
                                ? const Color(0xffF97316)
                                : const Color(0xff10B981),
                          ),
                          _smallPill(
                            '${_fmtQty(row['sale_count'])} sales',
                            const Color(0xff8B5CF6),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

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
            'Repeated Unsold Products (>= 2 records)',
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
                        '${item['not_sold_count'] ?? item['not_sold'] ?? 0} unsold / ${item['total_requests'] ?? item['requests'] ?? 0} total',
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
  final bool orderEditMode;

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
    this.orderEditMode = false,
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
                  orderEditMode
                      ? 'Added Quantity Sales Details'
                      : 'Request Sales Details',
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
                      _col(
                        orderEditMode ? 'Added Date' : 'Date',
                        'request_date',
                        sortCol,
                        sortAsc,
                        onSort,
                      ),
                      _col('Branch', 'branch', sortCol, sortAsc, onSort),
                      _col(
                        'Item',
                        'item',
                        sortCol,
                        sortAsc,
                        onSort,
                        width: 200,
                      ),
                      _col(
                        orderEditMode ? 'Added Qty' : 'Req Qty',
                        'request_qty',
                        sortCol,
                        sortAsc,
                        onSort,
                      ),
                      _col('Sold Qty', 'sold_qty', sortCol, sortAsc, onSort),
                      if (orderEditMode)
                        _col(
                          'Remaining',
                          'remaining_qty',
                          sortCol,
                          sortAsc,
                          onSort,
                        ),
                      if (orderEditMode)
                        _col(
                          'Sale Count',
                          'sale_count',
                          sortCol,
                          sortAsc,
                          onSort,
                        ),
                      _col('Sold %', 'sold_pct', sortCol, sortAsc, onSort),
                      _col(
                        orderEditMode ? 'Days Since Added' : 'Days Elapsed',
                        'days_elapsed',
                        sortCol,
                        sortAsc,
                        onSort,
                      ),
                      _col(
                        orderEditMode ? 'First Sale After' : 'Days to Sale',
                        'days_to_sale',
                        sortCol,
                        sortAsc,
                        onSort,
                      ),
                      DataColumn(
                        label: Text(orderEditMode ? 'Sales Status' : 'Status'),
                      ),
                    ],
                    rows: rows.map((r) {
                      final statusText = orderEditMode
                          ? r.monitoringLabel
                          : r.effectivenessLabel;
                      final sc = orderEditMode
                          ? _monitoringColor(r.monitoringStatus)
                          : (_statusColor[r.effectivenessStatus] ??
                                const Color(0xff94A3B8));
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
                          if (orderEditMode)
                            DataCell(
                              Text(
                                '${r.remainingAddedQty}',
                                style: TextStyle(
                                  color: r.remainingAddedQty > 0
                                      ? const Color(0xffF97316)
                                      : const Color(0xff10B981),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (orderEditMode)
                            DataCell(
                              Text(
                                '${r.saleCount}',
                                style: const TextStyle(
                                  color: Color(0xff334155),
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
                                statusText,
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

  Color _monitoringColor(String value) {
    switch (value) {
      case 'sold':
        return const Color(0xff10B981);
      case 'partially_sold':
        return const Color(0xffF59E0B);
      case 'not_sold':
        return const Color(0xffEF4444);
      default:
        return const Color(0xff94A3B8);
    }
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

Widget _miniMetric(String label, String value, Color color) {
  return Expanded(
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xff0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _smallPill(String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11),
    ),
  );
}

num _asNum(dynamic value) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

String _fmtQty(dynamic value) {
  final n = _asNum(value);
  if (n % 1 == 0) return n.toInt().toString();
  return n.toStringAsFixed(2);
}
