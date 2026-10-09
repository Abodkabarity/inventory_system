// lib/presentation/inventory/pages/additional_order_analysis_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/additional_analysis_excel_exporter.dart';
import '../../../core/utils/additional_order_history_excel_exporter.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';
import '../widgets/additional_analysis/additional_analysis_header.dart';
import '../widgets/additional_analysis/additional_insights_section.dart';
import '../widgets/additional_analysis/request_effectiveness_tab.dart';
import '../widgets/additional_analysis/top_branches_card.dart';
import '../widgets/additional_analysis/top_products_card.dart';
import '../../widgets/app_date_range_picker_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MAIN PAGE
// ─────────────────────────────────────────────────────────────────────────────

class AdditionalOrderAnalysisPage extends StatefulWidget {
  const AdditionalOrderAnalysisPage({super.key});

  @override
  State<AdditionalOrderAnalysisPage> createState() =>
      _AdditionalOrderAnalysisPageState();
}

class _AdditionalOrderAnalysisPageState
    extends State<AdditionalOrderAnalysisPage>
    with SingleTickerProviderStateMixin {
  // ── Date range ────────────────────────────────────────────────────────────
  late DateTime _from;
  late DateTime _to;

  // ── Loading flags ─────────────────────────────────────────────────────────
  bool _isAnalysisLoading = false;
  final TextEditingController _historySearchController =
      TextEditingController();
  String _historyQuery = '';
  String _historyBranch = 'All Branches';
  final Map<String, Set<String>> _historyColumnFilters = {};

  // ── Tab controller ────────────────────────────────────────────────────────
  late final TabController _tabController;
  int _tabIndex = 0;

  static const _tabs = [
    _TabDef(Icons.bar_chart_rounded, 'Overview'),
    _TabDef(Icons.track_changes_rounded, 'Sales Performance'),
    _TabDef(Icons.history_rounded, 'Additional Order History'),
  ];

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(() {
        if (_tabController.index != _tabIndex) {
          setState(() => _tabIndex = _tabController.index);
          // Lazy-load effectiveness data on first visit to that tab
          if (_tabIndex == 1) _loadEffectiveness();
          if (_tabIndex == 2) _loadHistory();
        }
      });

    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    final bloc = context.read<InventoryBloc>();
    if (bloc.state.additionalAnalysis.isEmpty) {
      _loadOverview();
    }
  }

  @override
  void dispose() {
    _historySearchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ── Loaders ───────────────────────────────────────────────────────────────

  void _loadOverview() {
    setState(() => _isAnalysisLoading = true);
    context.read<InventoryBloc>().add(
      LoadAdditionalOrderAnalysis(from: _from, to: _to),
    );
  }

  void _loadEffectiveness() {
    context.read<InventoryBloc>().add(
      LoadRequestEffectiveness(from: _from, to: _to),
    );
  }

  void _loadHistory() {
    context.read<InventoryBloc>().add(
      LoadAdditionalOrderHistory(from: _from, to: _to),
    );
  }

  void _loadAll() {
    _loadOverview();
    if (_tabIndex == 1) _loadEffectiveness();
    if (_tabIndex == 2) _loadHistory();
  }

  // ── Date picker ───────────────────────────────────────────────────────────

  Future<void> _pickDateRange() async {
    final result = await showDialog<DateTimeRange>(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => AdditionalAnalysisDateRangePickerDialog(
        initialRange: DateTimeRange(start: _from, end: _to),
      ),
    );
    if (result != null) {
      setState(() {
        _from = result.start;
        _to = DateTime(
          result.end.year,
          result.end.month,
          result.end.day,
          23,
          59,
          59,
        );
        _isAnalysisLoading = true;
      });
      _loadAll();
    }
  }

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return BlocListener<InventoryBloc, InventoryState>(
      listenWhen: (p, c) => p.additionalAnalysis != c.additionalAnalysis,
      listener: (_, _) => setState(() => _isAnalysisLoading = false),
      child: Container(
        color: const Color(0xffF0F4F8),
        child: Column(
          children: [
            _buildTopBar(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // ── TAB 0: Overview ──────────────────────────────────────
                  _buildOverviewTab(),

                  // ── TAB 1: Effectiveness ─────────────────────────────────
                  RequestEffectivenessTab(from: _from, to: _to),
                  _buildHistoryTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xffE2E8F0))),
      ),
      child: Row(
        children: [
          const Icon(Icons.analytics, color: Color(0xff06B6D4)),
          const SizedBox(width: 12),
          const Text(
            'Additional Order Analysis',
            style: TextStyle(
              color: Color(0xff1E293B),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // Date badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xffF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xffE2E8F0)),
            ),
            child: Text(
              '${_fmt(_from)}  →  ${_fmt(_to)}',
              style: const TextStyle(color: Color(0xff64748B), fontSize: 13),
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _pickDateRange,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff06B6D4),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.date_range, size: 18),
            label: const Text('Date Range'),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _loadAll,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: Color(0xff64748B)),
          ),
        ],
      ),
    );
  }

  // ── Tab bar ───────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
      child: TabBar(
        controller: _tabController,
        indicatorColor: const Color(0xff06B6D4),
        indicatorWeight: 3,
        labelColor: const Color(0xff06B6D4),
        unselectedLabelColor: const Color(0xff94A3B8),
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        isScrollable: true,
        tabs: _tabs
            .map(
              (t) => Tab(
                child: Row(
                  children: [
                    Icon(t.icon, size: 16),
                    const SizedBox(width: 6),
                    Text(t.label),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // ── Overview tab body ─────────────────────────────────────────────────────

  Widget _buildOverviewTab() {
    return BlocBuilder<InventoryBloc, InventoryState>(
      buildWhen: (p, c) => p.additionalAnalysis != c.additionalAnalysis,
      builder: (context, state) {
        if (_isAnalysisLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xff06B6D4)),
          );
        }

        final data = state.additionalAnalysis;

        if (data.isEmpty) {
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
                  'No data for the selected period',
                  style: TextStyle(color: Color(0xff94A3B8), fontSize: 16),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _loadOverview,
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

        final branches = List<Map<String, dynamic>>.from(
          data['top_branches'] ?? [],
        );
        final products = List<Map<String, dynamic>>.from(
          data['top_products'] ?? [],
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildOverviewExportBar(data),
              const SizedBox(height: 18),
              AdditionalKpiCards(data: data),
              const SizedBox(height: 24),
              SizedBox(
                height: 480,
                child: Row(
                  children: [
                    Expanded(child: TopBranchesCard(branches: branches)),
                    const SizedBox(width: 24),
                    Expanded(child: TopProductsCard(products: products)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              AdditionalInsightsSection(data: data),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverviewExportBar(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xffE0F2FE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.summarize_rounded,
              color: Color(0xff0284C7),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manager Overview Report',
                  style: TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Export a polished Excel report with summary, branch performance, products, reasons, and status distribution.',
                  style: TextStyle(color: Color(0xff64748B), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => AdditionalAnalysisExcelExporter.exportOverview(
              data: data,
              from: _from,
              to: _to,
            ),
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: const Color(0xff0F766E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text(
              'Export Overview',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return BlocBuilder<InventoryBloc, InventoryState>(
      buildWhen: (p, c) =>
          p.additionalOrderHistory != c.additionalOrderHistory ||
          p.isAdditionalHistoryLoading != c.isAdditionalHistoryLoading,
      builder: (context, state) {
        if (state.isAdditionalHistoryLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xff06B6D4)),
          );
        }

        final rows = state.additionalOrderHistory;
        if (rows.isEmpty) {
          return Center(
            child: Container(
              width: 420,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xffE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: const Color(0xffE0F2FE),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      color: Color(0xff0284C7),
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No additional orders found',
                    style: TextStyle(
                      color: Color(0xff1E293B),
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Choose another date range or refresh the current period.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xff64748B), fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _loadHistory,
                    icon: const Icon(Icons.refresh, color: Color(0xff06B6D4)),
                    label: const Text(
                      'Reload History',
                      style: TextStyle(color: Color(0xff06B6D4)),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final branches = _historyBranches(rows);
        if (_historyBranch != 'All Branches' &&
            !branches.contains(_historyBranch)) {
          _historyBranch = 'All Branches';
        }

        final baseRows = _filteredHistoryRows(rows);
        final filteredRows = _applyHistoryColumnFilters(baseRows);

        final pending = filteredRows.where((e) {
          final status = _historyStatus(e);
          return status == 'pending' || status == 'pending_inventory';
        }).length;
        final sent = filteredRows
            .where((e) => _historyStatus(e) == 'sent_to_store')
            .length;
        final done = filteredRows
            .where((e) => _historyStatus(e) == 'done')
            .length;
        final totalQty = filteredRows.fold<num>(
          0,
          (sum, row) => sum + _historyNum(row['request_qty']),
        );

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildHistoryMetric(
                      title: 'Total Requests',
                      value: '${filteredRows.length}',
                      icon: Icons.receipt_long_rounded,
                      color: const Color(0xff06B6D4),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildHistoryMetric(
                      title: 'Pending',
                      value: '$pending',
                      icon: Icons.hourglass_top_rounded,
                      color: const Color(0xffF59E0B),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildHistoryMetric(
                      title: 'Sent To Store',
                      value: '$sent',
                      icon: Icons.local_shipping_rounded,
                      color: const Color(0xff3B82F6),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildHistoryMetric(
                      title: 'Done',
                      value: '$done',
                      icon: Icons.fact_check_rounded,
                      color: const Color(0xff10B981),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildHistoryMetric(
                      title: 'Total Qty',
                      value: _numText(totalQty),
                      icon: Icons.inventory_2_rounded,
                      color: const Color(0xff8B5CF6),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildHistoryToolbar(branches: branches, rows: filteredRows),
              const SizedBox(height: 14),
              Expanded(
                child: _buildHistoryTable(filteredRows, sourceRows: baseRows),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryMetric({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      height: 96,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryToolbar({
    required List<String> branches,
    required List<Map<String, dynamic>> rows,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: TextField(
              controller: _historySearchController,
              onChanged: (value) => setState(() => _historyQuery = value),
              decoration: InputDecoration(
                hintText:
                    'Search branch, item code, item name, status, or notes...',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xff64748B),
                ),
                suffixIcon: _historyQuery.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _historySearchController.clear();
                          setState(() => _historyQuery = '');
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Color(0xff64748B),
                        ),
                      ),
                filled: true,
                fillColor: const Color(0xffF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xffE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xffE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: Color(0xff06B6D4),
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xffF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xffE2E8F0)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _historyBranch,
                  isExpanded: true,
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Color(0xff64748B),
                  ),
                  items: ['All Branches', ...branches]
                      .map(
                        (branch) => DropdownMenuItem<String>(
                          value: branch,
                          child: Text(
                            branch,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xff0F172A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _historyBranch = value);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (_historyHasColumnFilters) ...[
            SizedBox(
              height: 56,
              child: OutlinedButton.icon(
                onPressed: () => setState(_historyColumnFilters.clear),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xffEF4444),
                  side: const BorderSide(color: Color(0xffFECACA)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                label: const Text(
                  'Clear Filters',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: rows.isEmpty
                  ? null
                  : () => AdditionalOrderHistoryExcelExporter.export(
                      rows: rows,
                      from: _from,
                      to: _to,
                      branch: _historyBranch,
                      query: _historyQuery.trim(),
                    ),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: const Color(0xff0F766E),
                disabledBackgroundColor: const Color(0xffCBD5E1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text(
                'Export',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTable(
    List<Map<String, dynamic>> rows, {
    required List<Map<String, dynamic>> sourceRows,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 54,
            color: const Color(0xffF8FAFC),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _historyHeader('#', 1),
                _historyHeader(
                  'Status',
                  2,
                  filterKey: 'status',
                  sourceRows: sourceRows,
                ),
                _historyHeader(
                  'Branch',
                  3,
                  filterKey: 'branch_name',
                  sourceRows: sourceRows,
                ),
                _historyHeader(
                  'Item',
                  5,
                  filterKey: 'item',
                  sourceRows: sourceRows,
                ),
                _historyHeader(
                  'Req',
                  1,
                  filterKey: 'request_qty',
                  sourceRows: sourceRows,
                ),
                _historyHeader(
                  'Inventory',
                  2,
                  filterKey: 'inventory_qty',
                  sourceRows: sourceRows,
                ),
                _historyHeader(
                  'Store',
                  2,
                  filterKey: 'fulfilled_qty',
                  sourceRows: sourceRows,
                ),
                _historyHeader(
                  'Store Note',
                  3,
                  filterKey: 'store_note',
                  sourceRows: sourceRows,
                ),
                _historyHeader(
                  'Date & Time',
                  2,
                  filterKey: 'date_time',
                  sourceRows: sourceRows,
                ),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? const Center(
                    child: Text(
                      'No rows match the current search or filters.',
                      style: TextStyle(
                        color: Color(0xff64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Color(0xffE2E8F0)),
                    itemBuilder: (_, index) =>
                        _buildHistoryRow(rows[index], index),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _historyHeader(
    String text,
    int flex, {
    String? filterKey,
    List<Map<String, dynamic>> sourceRows = const [],
  }) {
    final isFiltered =
        filterKey != null && _isHistoryColumnFilterActive(filterKey);

    return Expanded(
      flex: flex,
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff64748B),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (filterKey != null)
            Tooltip(
              message: 'Filter $text',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () =>
                    _showHistoryColumnFilter(filterKey, text, sourceRows),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    isFiltered
                        ? Icons.filter_alt_rounded
                        : Icons.filter_alt_outlined,
                    size: 16,
                    color: isFiltered
                        ? const Color(0xff06B6D4)
                        : const Color(0xff64748B),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryRow(Map<String, dynamic> row, int index) {
    final status = _historyStatus(row);
    final inventoryNote = _historyText(row, 'inventory_note');
    final storeNote = _historyText(row, 'store_note');

    return Container(
      color: index.isEven ? Colors.white : const Color(0xffF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 1,
            child: Text(
              '${index + 1}',
              style: const TextStyle(color: Color(0xff475569), fontSize: 12),
            ),
          ),
          Expanded(flex: 2, child: _historyStatusChip(status)),
          Expanded(
            flex: 3,
            child: Text(
              _historyText(row, 'branch_name'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff0F172A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _historyText(row, 'item_name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    _historyText(row, 'item_code'),
                    if (inventoryNote.isNotEmpty) inventoryNote,
                  ].join('  -  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          _historyValue(_numText(row['request_qty']), 1),
          _historyValue(_numText(row['inventory_qty']), 2),
          _historyValue(_numText(row['fulfilled_qty']), 2),
          _historyValue(storeNote.isEmpty ? '-' : storeNote, 3),
          _historyValue(_historyDate(row), 2),
        ],
      ),
    );
  }

  Widget _historyValue(String value, int flex) {
    return Expanded(
      flex: flex,
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xff334155),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _historyStatusChip(String status) {
    final color = _historyStatusColor(status);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_historyStatusIcon(status), size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              _historyStatusLabel(status),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _historyHasColumnFilters =>
      _historyColumnFilters.values.any((selected) => selected.isNotEmpty);

  bool _isHistoryColumnFilterActive(String key) {
    return _historyColumnFilters[key]?.isNotEmpty ?? false;
  }

  List<Map<String, dynamic>> _applyHistoryColumnFilters(
    List<Map<String, dynamic>> rows,
  ) {
    if (!_historyHasColumnFilters) return rows;

    return rows.where((row) {
      for (final entry in _historyColumnFilters.entries) {
        if (entry.value.isEmpty) continue;
        if (!entry.value.contains(_historyFilterValue(row, entry.key))) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  String _historyFilterValue(Map<String, dynamic> row, String key) {
    switch (key) {
      case 'status':
        return _historyStatusLabel(_historyStatus(row));
      case 'branch_name':
        return _historyText(row, 'branch_name').isEmpty
            ? '-'
            : _historyText(row, 'branch_name');
      case 'item':
        final code = _historyText(row, 'item_code');
        final name = _historyText(row, 'item_name');
        if (code.isEmpty && name.isEmpty) return '-';
        if (code.isEmpty) return name;
        if (name.isEmpty) return code;
        return '$code - $name';
      case 'request_qty':
      case 'inventory_qty':
      case 'fulfilled_qty':
        return _numText(row[key]);
      case 'store_note':
        final note = _historyText(row, 'store_note');
        return note.isEmpty ? '-' : note;
      case 'date_time':
        return _historyDate(row);
      default:
        final value = _historyText(row, key);
        return value.isEmpty ? '-' : value;
    }
  }

  Future<void> _showHistoryColumnFilter(
    String key,
    String title,
    List<Map<String, dynamic>> sourceRows,
  ) async {
    final allValues =
        sourceRows
            .map((row) => _historyFilterValue(row, key))
            .where((value) => value.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (allValues.isEmpty) return;

    var search = '';
    final selected = Set<String>.from(_historyColumnFilters[key] ?? allValues);

    final result = await showDialog<Set<String>>(
      context: context,
      barrierColor: Colors.black38,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final visibleValues = allValues
                .where(
                  (value) =>
                      search.isEmpty ||
                      value.toLowerCase().contains(search.toLowerCase()),
                )
                .toList();
            final allVisibleSelected =
                visibleValues.isNotEmpty &&
                visibleValues.every(selected.contains);

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: Container(
                width: 430,
                constraints: const BoxConstraints(maxHeight: 620),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 28,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xffE0F2FE),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.filter_alt_rounded,
                              color: Color(0xff0284C7),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Filter $title',
                                  style: const TextStyle(
                                    color: Color(0xff0F172A),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  '${selected.length} of ${allValues.length} selected',
                                  style: const TextStyle(
                                    color: Color(0xff64748B),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, allValues.toSet()),
                            child: const Text('Clear'),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xffE2E8F0)),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: TextField(
                        onChanged: (value) =>
                            setDialogState(() => search = value.trim()),
                        decoration: InputDecoration(
                          hintText: 'Search values...',
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: Color(0xff64748B),
                          ),
                          filled: true,
                          fillColor: const Color(0xffF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xffE2E8F0),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xffE2E8F0),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xff06B6D4),
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                        children: [
                          CheckboxListTile(
                            value: allVisibleSelected,
                            onChanged: (_) {
                              setDialogState(() {
                                if (allVisibleSelected) {
                                  selected.removeAll(visibleValues);
                                } else {
                                  selected.addAll(visibleValues);
                                }
                              });
                            },
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: const Color(0xff06B6D4),
                            title: const Text(
                              'Select All',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          const Divider(height: 1, color: Color(0xffE2E8F0)),
                          if (visibleValues.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(18),
                              child: Text(
                                'No values found.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xff64748B)),
                              ),
                            )
                          else
                            ...visibleValues.map(
                              (value) => CheckboxListTile(
                                value: selected.contains(value),
                                onChanged: (checked) {
                                  setDialogState(() {
                                    if (checked == true) {
                                      selected.add(value);
                                    } else {
                                      selected.remove(value);
                                    }
                                  });
                                },
                                dense: true,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                activeColor: const Color(0xff06B6D4),
                                title: Text(
                                  value,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xff0F172A),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(
                        color: Color(0xffF8FAFC),
                        border: Border(
                          top: BorderSide(color: Color(0xffE2E8F0)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xff64748B),
                                side: const BorderSide(
                                  color: Color(0xffCBD5E1),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: selected.isEmpty
                                  ? null
                                  : () =>
                                        Navigator.pop(dialogContext, selected),
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: const Color(0xff06B6D4),
                                disabledBackgroundColor: const Color(
                                  0xffCBD5E1,
                                ),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Apply',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;
    setState(() {
      if (result.length == allValues.length) {
        _historyColumnFilters.remove(key);
      } else {
        _historyColumnFilters[key] = result;
      }
    });
  }

  String _historyText(Map<String, dynamic> row, String key) {
    return (row[key] ?? '').toString().trim();
  }

  List<String> _historyBranches(List<Map<String, dynamic>> rows) {
    final branches = rows
        .map((row) => _historyText(row, 'branch_name'))
        .where((branch) => branch.isNotEmpty)
        .toSet()
        .toList();

    branches.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return branches;
  }

  List<Map<String, dynamic>> _filteredHistoryRows(
    List<Map<String, dynamic>> rows,
  ) {
    final query = _historyQuery.trim().toLowerCase();

    return rows.where((row) {
      final branch = _historyText(row, 'branch_name');
      if (_historyBranch != 'All Branches' && branch != _historyBranch) {
        return false;
      }

      if (query.isEmpty) return true;

      final searchable = [
        branch,
        _historyText(row, 'item_code'),
        _historyText(row, 'item_name'),
        _historyStatusLabel(_historyStatus(row)),
        _historyText(row, 'inventory_note'),
        _historyText(row, 'store_note'),
        _historyText(row, 'contact_logistic'),
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
  }

  String _historyStatus(Map<String, dynamic> row) {
    return _historyText(row, 'status').toLowerCase();
  }

  num _historyNum(dynamic raw) {
    if (raw is num) return raw;
    return num.tryParse((raw ?? '').toString()) ?? 0;
  }

  String _numText(dynamic raw) {
    if (raw == null || raw.toString().trim().isEmpty) return '-';
    final value = _historyNum(raw);
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }

  String _historyDate(Map<String, dynamic> row) {
    final status = _historyStatus(row);
    final rawDates = <dynamic>[
      if (status == 'done' || status == 'rejected') row['done_at'],
      if (status == 'sent_to_store' || status == 'rejected')
        row['inventory_approved_at'],
      row['created_at'],
    ];

    for (final raw in rawDates) {
      final parsed = DateTime.tryParse((raw ?? '').toString())?.toLocal();
      if (parsed == null) continue;
      return DateFormat('yyyy-MM-dd HH:mm').format(parsed);
    }

    return '-';
  }

  Color _historyStatusColor(String status) {
    switch (status) {
      case 'pending':
      case 'pending_inventory':
        return const Color(0xffF59E0B);
      case 'sent_to_store':
        return const Color(0xff3B82F6);
      case 'done':
        return const Color(0xff10B981);
      case 'rejected':
        return const Color(0xffEF4444);
      default:
        return const Color(0xff64748B);
    }
  }

  IconData _historyStatusIcon(String status) {
    switch (status) {
      case 'pending':
      case 'pending_inventory':
        return Icons.schedule_rounded;
      case 'sent_to_store':
        return Icons.local_shipping_rounded;
      case 'done':
        return Icons.check_circle_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  String _historyStatusLabel(String status) {
    switch (status) {
      case 'pending':
      case 'pending_inventory':
        return 'PENDING';
      case 'sent_to_store':
        return 'SENT';
      case 'done':
        return 'DONE';
      case 'rejected':
        return 'REJECTED';
      default:
        return status.isEmpty ? 'UNKNOWN' : status.toUpperCase();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL DATA CLASS
// ─────────────────────────────────────────────────────────────────────────────

class _TabDef {
  final IconData icon;
  final String label;
  const _TabDef(this.icon, this.label);
}

// ═══════════════════════════════════════════════════════════════════════════════
// DATE RANGE PICKER DIALOG
// ═══════════════════════════════════════════════════════════════════════════════

class AdditionalAnalysisDateRangePickerDialog extends StatelessWidget {
  final DateTimeRange initialRange;

  const AdditionalAnalysisDateRangePickerDialog({
    super.key,
    required this.initialRange,
  });

  @override
  Widget build(BuildContext context) => AppDateRangePickerDialog(
    initialRange: initialRange,
  );
}
