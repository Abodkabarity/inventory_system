// lib/presentation/inventory/pages/branches_tracker_page.dart
//
// Matches the exact structure of AdditionalOrderAnalysisPage:
//   • Same top bar, tab bar, date-range picker style
//   • GlassContainer cards throughout
//   • Tab 0 – Overview  (KPIs + Top Branches + Top Items + Type Distribution)
//   • Tab 1 – Timeline  (full change log with filters + pagination)
//
// Data source: branch_change_tracker VIEW (create in Supabase first –
// see branches_tracker_view.sql).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/additional_analysis/glass_container.dart';
import '../widgets/branches_tracker_timeline_tab.dart';
import '../../widgets/app_date_range_picker_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PAGE
// ─────────────────────────────────────────────────────────────────────────────

class BranchesTrackerPage extends StatefulWidget {
  const BranchesTrackerPage({super.key});

  @override
  State<BranchesTrackerPage> createState() => _BranchesTrackerPageState();
}

class _BranchesTrackerPageState extends State<BranchesTrackerPage>
    with SingleTickerProviderStateMixin {
  // ── dates ─────────────────────────────────────────────────────────────────
  late DateTime _from;
  late DateTime _to;
  RealtimeChannel? _trackerChannel;
  Timer? _reloadDebounce;
  // ── data ──────────────────────────────────────────────────────────────────
  bool _loading = true;
  String _error = '';
  List<Map<String, dynamic>> _rows = [];

  // ── tabs ──────────────────────────────────────────────────────────────────
  late final TabController _tabController;
  int _tabIndex = 0;

  static const _tabs = [_TabDef(Icons.timeline_rounded, 'Change Timeline')];

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();

    _from = DateTime(now.year, now.month, now.day);

    _to = DateTime(now.year, now.month, now.day, 23, 59, 59);

    _tabController = TabController(length: _tabs.length, vsync: this)
      ..addListener(() {
        if (_tabController.index != _tabIndex) {
          setState(() => _tabIndex = _tabController.index);
        }
      });

    _load();
    _startRealtime();
  }

  void _startRealtime() {
    final client = Supabase.instance.client;

    _trackerChannel = client
        .channel('branches-tracker-live-page')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_edits',
          callback: (_) => _reloadFromRealtime(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'max_adj',
          callback: (_) => _reloadFromRealtime(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'max_adj_log',
          callback: (_) => _reloadFromRealtime(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'mismatch_log',
          callback: (_) => _reloadFromRealtime(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'stk_mismatch',
          callback: (_) => _reloadFromRealtime(),
        )
        .subscribe();
  }

  void _reloadFromRealtime() {
    _reloadDebounce?.cancel();

    _reloadDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();

    if (_trackerChannel != null) {
      Supabase.instance.client.removeChannel(_trackerChannel!);
    }

    _tabController.dispose();
    super.dispose();
  }

  // ── load ──────────────────────────────────────────────────────────────────

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }

    try {
      final data = await Supabase.instance.client
          .from('branch_change_tracker')
          .select()
          .gte('changed_at', _from.toIso8601String())
          .lte('changed_at', _to.toIso8601String())
          .order('changed_at', ascending: false)
          .limit(5000);

      if (!mounted) return;

      setState(() {
        _rows = List<Map<String, dynamic>>.from(data);
        _loading = false;
        _error = '';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── computed stats ────────────────────────────────────────────────────────

  int get _total => _rows.length;
  int get _orderEdits =>
      _rows.where((r) => r['source_table'] == 'order_edits').length;
  int get _maxAdjTotal => _rows
      .where((r) => (r['source_table'] as String? ?? '').contains('max_adj'))
      .length;
  int get _mismatchTotal => _rows.where((r) {
    final t = (r['source_table'] as String? ?? '');
    return t.contains('mismatch') || t == 'stk_mismatch';
  }).length;

  int get _activeMismatch =>
      _rows.where((r) => r['source_table'] == 'stk_mismatch').length;
  int get _activeMaxAdj =>
      _rows.where((r) => r['source_table'] == 'max_adj').length;

  Set<String> get _uniqueBranches => _rows
      .map((r) => (r['branch_name'] ?? '').toString())
      .where((e) => e.isNotEmpty)
      .toSet();
  Set<String> get _uniqueItems => _rows
      .map((r) => (r['item_code'] ?? '').toString())
      .where((e) => e.isNotEmpty)
      .toSet();

  /// Groups rows by branch → sorted list of {branch_name, count}
  List<Map<String, dynamic>> get _topBranches {
    final map = <String, int>{};
    for (final r in _rows) {
      final b = (r['branch_name'] ?? '').toString();
      if (b.isEmpty) continue;
      map[b] = (map[b] ?? 0) + 1;
    }
    final list = map.entries
        .map((e) => {'branch_name': e.key, 'count': e.value})
        .toList();
    list.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
    return list;
  }

  /// Groups rows by item_code → sorted list of {item_code, item_name, count}
  List<Map<String, dynamic>> get _topItems {
    final map = <String, Map<String, dynamic>>{};
    for (final r in _rows) {
      final code = (r['item_code'] ?? '').toString();
      if (code.isEmpty) continue;
      map.putIfAbsent(
        code,
        () => {
          'item_code': code,
          'item_name': r['item_name'] ?? '',
          'count': 0,
        },
      );
      map[code]!['count'] = (map[code]!['count'] as int) + 1;
    }
    final list = map.values.toList();
    list.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
    return list;
  }

  Map<String, int> get _typeBreakdown {
    final map = <String, int>{};
    for (final r in _rows) {
      final t = (r['source_table'] ?? 'unknown').toString();
      map[t] = (map[t] ?? 0) + 1;
    }
    return map;
  }

  // ── date helpers ──────────────────────────────────────────────────────────

  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDateRange() async {
    final result = await showDialog<DateTimeRange>(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => _DateRangePickerDialog(
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
      });
      _load();
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xffF0F4F8),
      child: Column(
        children: [
          _buildTopBar(),
          //  _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                // _buildOverviewTab(),
                BranchesTrackerTimelineTab(rows: _rows, loading: _loading),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── TOP BAR ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xffE2E8F0))),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_tree_rounded, color: Color(0xff06B6D4)),
          const SizedBox(width: 12),
          const Text(
            'Branches Tracker',
            style: TextStyle(
              color: Color(0xff1E293B),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
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
            onPressed: _load,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: Color(0xff64748B)),
          ),
        ],
      ),
    );
  }

  // ── TAB BAR ───────────────────────────────────────────────────────────────

  /*  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24),
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
  }*/

  // ── OVERVIEW TAB ──────────────────────────────────────────────────────────

  Widget _buildOverviewTab() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xff06B6D4)),
      );
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xffEF4444), size: 48),
            const SizedBox(height: 12),
            const Text(
              'Failed to load data',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              _error,
              style: const TextStyle(color: Color(0xff64748B), fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xff06B6D4),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_tree_outlined,
              color: Color(0xffCBD5E1),
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'No changes in the selected period',
              style: TextStyle(color: Color(0xff94A3B8), fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _load,
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Row 1: KPI cards ───────────────────────────────────────────
          _TrackerKpiCards(
            total: _total,
            orderEdits: _orderEdits,
            maxAdjTotal: _maxAdjTotal,
            mismatchTotal: _mismatchTotal,
            activeMismatch: _activeMismatch,
            activeMaxAdj: _activeMaxAdj,
            uniqueBranches: _uniqueBranches.length,
            uniqueItems: _uniqueItems.length,
          ),
          const SizedBox(height: 24),
          // ── Row 2: Branches + Items ────────────────────────────────────
          SizedBox(
            height: 480,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _TopBranchesCard(branches: _topBranches)),
                const SizedBox(width: 24),
                Expanded(
                  child: _TopItemsCard(items: _topItems.take(50).toList()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // ── Row 3: Change type distribution ───────────────────────────
          _TypeDistributionCard(breakdown: _typeBreakdown, total: _total),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI CARDS  (2 rows × 4)
// ─────────────────────────────────────────────────────────────────────────────

class _TrackerKpiCards extends StatelessWidget {
  final int total, orderEdits, maxAdjTotal, mismatchTotal;
  final int activeMismatch, activeMaxAdj, uniqueBranches, uniqueItems;

  const _TrackerKpiCards({
    required this.total,
    required this.orderEdits,
    required this.maxAdjTotal,
    required this.mismatchTotal,
    required this.activeMismatch,
    required this.activeMaxAdj,
    required this.uniqueBranches,
    required this.uniqueItems,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            _kpi(
              'Total Changes',
              '$total',
              const Color(0xff06B6D4),
              Icons.timeline_rounded,
            ),
            const SizedBox(width: 16),
            _kpi(
              'Order Edits',
              '$orderEdits',
              const Color(0xff3B82F6),
              Icons.edit_rounded,
            ),
            const SizedBox(width: 16),
            _kpi(
              'Max Adj Changes',
              '$maxAdjTotal',
              const Color(0xffF97316),
              Icons.tune_rounded,
            ),
            const SizedBox(width: 16),
            _kpi(
              'Mismatch Changes',
              '$mismatchTotal',
              const Color(0xffEF4444),
              Icons.warning_amber_rounded,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _kpi(
              'Active Mismatches',
              '$activeMismatch',
              const Color(0xffF59E0B),
              Icons.report_problem_outlined,
            ),
            const SizedBox(width: 16),
            _kpi(
              'Active Max Adj',
              '$activeMaxAdj',
              const Color(0xff8B5CF6),
              Icons.adjust_rounded,
            ),
            const SizedBox(width: 16),
            _kpi(
              'Unique Branches',
              '$uniqueBranches',
              const Color(0xff10B981),
              Icons.store_rounded,
            ),
            const SizedBox(width: 16),
            _kpi(
              'Unique Items',
              '$uniqueItems',
              const Color(0xff14B8A6),
              Icons.inventory_2_rounded,
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
                color: color.withValues(alpha: 0.12),
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
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 24,
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
// TOP BRANCHES CARD
// ─────────────────────────────────────────────────────────────────────────────

class _TopBranchesCard extends StatefulWidget {
  final List<Map<String, dynamic>> branches;
  const _TopBranchesCard({required this.branches});

  @override
  State<_TopBranchesCard> createState() => _TopBranchesCardState();
}

class _TopBranchesCardState extends State<_TopBranchesCard> {
  String _search = '';
  bool _asc = false;

  List<Map<String, dynamic>> get _filtered {
    var list = widget.branches
        .where(
          (b) => (b['branch_name'] as String).toLowerCase().contains(
            _search.toLowerCase(),
          ),
        )
        .toList();
    if (_asc) list = list.reversed.toList();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final maxCount = list.isEmpty ? 1 : (list.first['count'] as int);

    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.store_rounded, color: Color(0xff06B6D4)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Top Branches by Changes',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xff1E293B),
                  ),
                ),
              ),
              _sortBtn(
                _asc ? 'Lowest' : 'Highest',
                () => setState(() => _asc = !_asc),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _searchField('Search branch…', (v) => setState(() => _search = v)),
          const SizedBox(height: 12),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text(
                      'No data',
                      style: TextStyle(color: Color(0xff94A3B8)),
                    ),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final row = list[i];
                      final count = row['count'] as int;
                      return _barRow(
                        rank: i + 1,
                        label: row['branch_name'].toString(),
                        count: count,
                        max: maxCount,
                        color: const Color(0xff06B6D4),
                        badge: '$count changes',
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
// TOP ITEMS CARD
// ─────────────────────────────────────────────────────────────────────────────

class _TopItemsCard extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  const _TopItemsCard({required this.items});

  @override
  State<_TopItemsCard> createState() => _TopItemsCardState();
}

class _TopItemsCardState extends State<_TopItemsCard> {
  String _search = '';

  List<Map<String, dynamic>> get _filtered => widget.items.where((it) {
    final q = _search.toLowerCase();
    return (it['item_name'] as String).toLowerCase().contains(q) ||
        (it['item_code'] as String).toLowerCase().contains(q);
  }).toList();

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final maxCount = list.isEmpty ? 1 : (list.first['count'] as int);

    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.medication_rounded, color: Color(0xff8B5CF6)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Most Changed Items',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xff1E293B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _searchField(
            'Search item code or name…',
            (v) => setState(() => _search = v),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: list.isEmpty
                ? const Center(
                    child: Text(
                      'No data',
                      style: TextStyle(color: Color(0xff94A3B8)),
                    ),
                  )
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final row = list[i];
                      final count = row['count'] as int;
                      return _itemBarRow(
                        rank: i + 1,
                        code: row['item_code'].toString(),
                        name: row['item_name'].toString(),
                        count: count,
                        max: maxCount,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

Widget _itemBarRow({
  required int rank,
  required String code,
  required String name,
  required int count,
  required int max,
}) {
  const color = Color(0xff8B5CF6);
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xffF8FAFC),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xffE2E8F0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _rankBadge(rank),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xff1E293B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    code,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xff94A3B8),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: max > 0 ? (count / max).clamp(0.0, 1.0) : 0,
            minHeight: 4,
            backgroundColor: const Color(0xffE2E8F0),
            color: color,
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TYPE DISTRIBUTION CARD
// ─────────────────────────────────────────────────────────────────────────────

class _TypeDistributionCard extends StatelessWidget {
  final Map<String, int> breakdown;
  final int total;

  const _TypeDistributionCard({required this.breakdown, required this.total});

  static const _meta = <String, _TypeMeta>{
    'order_edits': _TypeMeta(
      'Order Edits',
      Color(0xff3B82F6),
      Icons.edit_rounded,
    ),
    'max_adj': _TypeMeta(
      'Max Adj (Active)',
      Color(0xffF97316),
      Icons.tune_rounded,
    ),
    'max_adj_log': _TypeMeta(
      'Max Adj (History)',
      Color(0xffF59E0B),
      Icons.history_rounded,
    ),
    'mismatch_log': _TypeMeta(
      'Mismatch (History)',
      Color(0xffEF4444),
      Icons.warning_amber_rounded,
    ),
    'stk_mismatch': _TypeMeta(
      'Mismatch (Active)',
      Color(0xffDC2626),
      Icons.report_problem_rounded,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final sorted = breakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return GlassContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.donut_large_rounded, color: Color(0xff14B8A6)),
              SizedBox(width: 8),
              Text(
                'Change Type Distribution',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xff1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...sorted.map((e) {
            final meta =
                _meta[e.key] ??
                _TypeMeta(
                  e.key,
                  const Color(0xff94A3B8),
                  Icons.circle_outlined,
                );
            final pct = total > 0 ? (e.value / total * 100) : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: meta.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(meta.icon, color: meta.color, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          meta.label,
                          style: const TextStyle(
                            color: Color(0xff1E293B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        '${e.value}  ·  ${pct.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: Color(0xff64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (pct / 100).clamp(0.0, 1.0),
                      minHeight: 7,
                      backgroundColor: const Color(0xffE2E8F0),
                      color: meta.color,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _TypeMeta {
  final String label;
  final Color color;
  final IconData icon;
  const _TypeMeta(this.label, this.color, this.icon);
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED SMALL HELPERS
// ─────────────────────────────────────────────────────────────────────────────

class _TabDef {
  final IconData icon;
  final String label;
  const _TabDef(this.icon, this.label);
}

Widget _rankBadge(int rank) {
  Color c;
  if (rank == 1) {
    c = const Color(0xffF59E0B);
  } else if (rank == 2) {
    c = const Color(0xff64748B);
  } else if (rank == 3) {
    c = const Color(0xffB45309);
  } else {
    c = const Color(0xff94A3B8);
  }
  return Container(
    width: 28,
    height: 28,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      '#$rank',
      style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold),
    ),
  );
}

Widget _barRow({
  required int rank,
  required String label,
  required int count,
  required int max,
  required Color color,
  required String badge,
}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xffF8FAFC),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xffE2E8F0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _rankBadge(rank),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xff1E293B),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: max > 0 ? (count / max).clamp(0.0, 1.0) : 0,
            minHeight: 4,
            backgroundColor: const Color(0xffE2E8F0),
            color: color,
          ),
        ),
      ],
    ),
  );
}

Widget _sortBtn(String label, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xffF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(color: Color(0xff06B6D4), fontSize: 12),
      ),
    ),
  );
}

Widget _searchField(String hint, ValueChanged<String> onChanged) {
  return TextField(
    onChanged: onChanged,
    style: const TextStyle(color: Color(0xff1E293B)),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xff94A3B8)),
      prefixIcon: const Icon(Icons.search, color: Color(0xff94A3B8)),
      filled: true,
      fillColor: const Color(0xffF1F5F9),
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// DATE RANGE PICKER DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _DateRangePickerDialog extends StatelessWidget {
  final DateTimeRange initialRange;
  const _DateRangePickerDialog({required this.initialRange});

  @override
  Widget build(BuildContext context) => AppDateRangePickerDialog(
    initialRange: initialRange,
    lastDate: DateTime(9999),
    presets: (now) => [
      ('Today', now, now),
      ('Last 7 days', now.subtract(const Duration(days: 6)), now),
      ('Last 30 days', now.subtract(const Duration(days: 29)), now),
      ('This month', DateTime(now.year, now.month, 1), now),
      (
        'Last Month',
        DateTime(now.year, now.month - 1, 1),
        DateTime(now.year, now.month, 0),
      ),
      ('Last 3 months', DateTime(now.year, now.month - 2, 1), now),
    ],
  );
}
