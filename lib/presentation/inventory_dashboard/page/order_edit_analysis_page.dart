import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/order_edit_analysis_excel_exporter.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';
import '../widgets/additional_analysis/request_effectiveness_tab.dart';
import '../widgets/additional_analysis/top_branches_card.dart';
import '../widgets/additional_analysis/top_products_card.dart';

class OrderEditAnalysisPage extends StatefulWidget {
  const OrderEditAnalysisPage({super.key});

  @override
  State<OrderEditAnalysisPage> createState() => _OrderEditAnalysisPageState();
}

class _OrderEditAnalysisPageState extends State<OrderEditAnalysisPage>
    with SingleTickerProviderStateMixin {
  late DateTime _from;
  late DateTime _to;
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _branch = 'All Branches';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    _tabController = TabController(length: 3, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _load() {
    context.read<InventoryBloc>().add(
      LoadOrderEditAnalysis(from: _from, to: _to),
    );
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(DateTime.now().year + 2),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xff06B6D4),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xff0F172A),
            ),
          ),
          child: child!,
        );
      },
    );

    if (range == null) return;
    setState(() {
      _from = DateTime(range.start.year, range.start.month, range.start.day);
      _to = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
        23,
        59,
        59,
      );
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xffF0F4F8),
      child: Column(
        children: [
          _topBar(),
          _tabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _overviewTab(),
                RequestEffectivenessTab(
                  from: _from,
                  to: _to,
                  orderEditMode: true,
                ),
                _historyTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xffE2E8F0))),
      ),
      child: Row(
        children: [
          const Icon(Icons.add_chart_rounded, color: Color(0xff06B6D4)),
          const SizedBox(width: 12),
          const Text(
            'Order Edit Analysis',
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
              '${_fmt(_from)}  ->  ${_fmt(_to)}',
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

  Widget _tabBar() {
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
        tabs: const [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bar_chart_rounded, size: 16),
                SizedBox(width: 6),
                Text('Overview'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.track_changes_rounded, size: 16),
                SizedBox(width: 6),
                Text('Sales Performance'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history_rounded, size: 16),
                SizedBox(width: 6),
                Text('Edit History'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _overviewTab() {
    return BlocBuilder<InventoryBloc, InventoryState>(
      buildWhen: (p, c) =>
          p.orderEditAnalysis != c.orderEditAnalysis ||
          p.isOrderEditAnalysisLoading != c.isOrderEditAnalysisLoading,
      builder: (context, state) {
        if (state.isOrderEditAnalysisLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xff06B6D4)),
          );
        }

        final data = state.orderEditAnalysis;
        if (data.isEmpty) {
          return _empty(
            icon: Icons.add_chart_outlined,
            title: 'No positive edits found',
            subtitle: 'No order_edits rows with diff greater than zero.',
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
            children: [
              _exportBar(data),
              const SizedBox(height: 18),
              _OrderEditKpiCards(data: data),
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
              _OrderEditInsights(data: data),
            ],
          ),
        );
      },
    );
  }

  Widget _historyTab() {
    return BlocBuilder<InventoryBloc, InventoryState>(
      buildWhen: (p, c) =>
          p.orderEditAnalysis != c.orderEditAnalysis ||
          p.isOrderEditAnalysisLoading != c.isOrderEditAnalysisLoading,
      builder: (context, state) {
        if (state.isOrderEditAnalysisLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xff06B6D4)),
          );
        }

        final data = state.orderEditAnalysis;
        final allRows = List<Map<String, dynamic>>.from(data['rows'] ?? []);
        final branches = _branches(allRows);
        if (_branch != 'All Branches' && !branches.contains(_branch)) {
          _branch = 'All Branches';
        }
        final rows = _filteredRows(allRows);

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              _historyToolbar(data, rows, branches),
              const SizedBox(height: 14),
              Expanded(child: _historyTable(rows)),
            ],
          ),
        );
      },
    );
  }

  Widget _exportBar(Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          _iconBox(Icons.summarize_rounded, const Color(0xff0284C7)),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Positive Order Edit Report',
                  style: TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Export added quantity analysis by branch, product, reason, and edit details.',
                  style: TextStyle(color: Color(0xff64748B), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => OrderEditAnalysisExcelExporter.export(
              data: data,
              from: _from,
              to: _to,
              branch: _branch,
              search: _query,
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

  Widget _historyToolbar(
    Map<String, dynamic> data,
    List<Map<String, dynamic>> rows,
    List<String> branches,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText:
                    'Search branch, item code, item name, reason, or date...',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xff64748B),
                ),
                suffixIcon: _query.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Color(0xff64748B),
                        ),
                      ),
                filled: true,
                fillColor: const Color(0xffF8FAFC),
                border: _inputBorder(const Color(0xffE2E8F0)),
                enabledBorder: _inputBorder(const Color(0xffE2E8F0)),
                focusedBorder: _inputBorder(const Color(0xff06B6D4), 1.4),
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
                  value: _branch,
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
                    setState(() => _branch = value);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xffEFF6FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xffBFDBFE)),
            ),
            alignment: Alignment.center,
            child: Text(
              '${rows.length} edits',
              style: const TextStyle(
                color: Color(0xff1D4ED8),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: rows.isEmpty
                  ? null
                  : () => OrderEditAnalysisExcelExporter.export(
                      data: {...data, 'rows': rows},
                      from: _from,
                      to: _to,
                      branch: _branch,
                      search: _query,
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

  Widget _historyTable(List<Map<String, dynamic>> rows) {
    return Container(
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 54,
            color: const Color(0xffF8FAFC),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Row(
              children: [
                _HeaderCell('#', 1),
                _HeaderCell('Branch', 3),
                _HeaderCell('Item', 5),
                _HeaderCell('Old', 1),
                _HeaderCell('New', 1),
                _HeaderCell('Added', 1),
                _HeaderCell('Reason', 3),
                _HeaderCell('Run Date', 2),
                _HeaderCell('Date & Time', 2),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? const Center(
                    child: Text(
                      'No positive edits match the current filters.',
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
                    itemBuilder: (_, index) => _historyRow(rows[index], index),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _historyRow(Map<String, dynamic> row, int index) {
    return Container(
      color: index.isEven ? Colors.white : const Color(0xffF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _value('${index + 1}', 1),
          _value(_text(row['branch_name']), 3, bold: true),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _text(row['item_name']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _text(row['item_code']),
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
          _value(_numText(row['old_qty']), 1),
          _value(_numText(row['new_qty']), 1),
          Expanded(
            flex: 1,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xffDCFCE7),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xffBBF7D0)),
                ),
                child: Text(
                  '+${_numText(row['diff'])}',
                  style: const TextStyle(
                    color: Color(0xff16A34A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
          _value(_text(row['reason']).isEmpty ? '-' : _text(row['reason']), 3),
          _value(_text(row['run_date']), 2),
          _value(_date(row['changed_at']), 2),
        ],
      ),
    );
  }

  Widget _value(String value, int flex, {bool bold = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: const Color(0xff334155),
          fontSize: 13,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w700,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filteredRows(List<Map<String, dynamic>> rows) {
    final q = _query.trim().toLowerCase();
    return rows.where((row) {
      final branch = _text(row['branch_name']);
      if (_branch != 'All Branches' && branch != _branch) return false;
      if (q.isEmpty) return true;

      return [
        branch,
        _text(row['item_code']),
        _text(row['item_name']),
        _text(row['reason']),
        _text(row['run_date']),
        _date(row['changed_at']),
      ].join(' ').toLowerCase().contains(q);
    }).toList();
  }

  List<String> _branches(List<Map<String, dynamic>> rows) {
    final branches = rows
        .map((row) => _text(row['branch_name']))
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    branches.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return branches;
  }

  Widget _empty({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Container(
        width: 430,
        padding: const EdgeInsets.all(28),
        decoration: _cardDecoration(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _iconBox(icon, const Color(0xff0284C7), size: 62),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xff1E293B),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xff64748B), fontSize: 13),
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
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
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
    );
  }

  Widget _iconBox(IconData icon, Color color, {double size = 42}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size > 50 ? 18 : 12),
      ),
      child: Icon(icon, color: color, size: size > 50 ? 30 : 22),
    );
  }

  OutlineInputBorder _inputBorder(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  String _fmt(DateTime value) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  String _date(dynamic value) {
    final parsed = DateTime.tryParse((value ?? '').toString())?.toLocal();
    if (parsed == null) return '-';
    return DateFormat('yyyy-MM-dd HH:mm').format(parsed);
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  num _num(dynamic value) {
    if (value is num) return value;
    return num.tryParse((value ?? '').toString()) ?? 0;
  }

  String _numText(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return '-';
    final numValue = _num(value);
    if (numValue == numValue.roundToDouble()) {
      return numValue.toInt().toString();
    }
    return numValue.toStringAsFixed(2);
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  final int flex;

  const _HeaderCell(this.text, this.flex);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xff64748B),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _OrderEditKpiCards extends StatelessWidget {
  final Map<String, dynamic> data;

  const _OrderEditKpiCards({required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            _card(
              'Positive Edits',
              '${data['total_edits'] ?? data['total_requests'] ?? 0}',
              const Color(0xff06B6D4),
              Icons.edit_note_rounded,
            ),
            const SizedBox(width: 16),
            _card(
              'Added Quantity',
              _numText(data['total_qty']),
              const Color(0xff14B8A6),
              Icons.add_shopping_cart_rounded,
            ),
            const SizedBox(width: 16),
            _card(
              'Unique Products',
              '${data['unique_products'] ?? 0}',
              const Color(0xff8B5CF6),
              Icons.medication_rounded,
            ),
            const SizedBox(width: 16),
            _card(
              'Unique Branches',
              '${data['unique_branches'] ?? 0}',
              const Color(0xffF59E0B),
              Icons.store_rounded,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _card(
              'Branch Edit Rate',
              '${_num(data['active_branch_rate']).toStringAsFixed(1)}%',
              const Color(0xff10B981),
              Icons.store_mall_directory_outlined,
            ),
            const SizedBox(width: 16),
            _card(
              'Average Added Qty',
              _num(data['avg_qty']).toStringAsFixed(1),
              const Color(0xff3B82F6),
              Icons.analytics_rounded,
            ),
            const SizedBox(width: 16),
            _card(
              'Largest Addition',
              _numText(data['max_addition']),
              const Color(0xffEF4444),
              Icons.trending_up_rounded,
            ),
          ],
        ),
      ],
    );
  }

  Widget _card(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        height: 98,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
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
                mainAxisAlignment: MainAxisAlignment.center,
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
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static num _num(dynamic value) {
    if (value is num) return value;
    return num.tryParse((value ?? '').toString()) ?? 0;
  }

  static String _numText(dynamic value) {
    final number = _num(value);
    if (number == number.roundToDouble()) return number.toInt().toString();
    return number.toStringAsFixed(2);
  }
}

class _OrderEditInsights extends StatelessWidget {
  final Map<String, dynamic> data;

  const _OrderEditInsights({required this.data});

  @override
  Widget build(BuildContext context) {
    final reasons = List<Map<String, dynamic>>.from(data['reasons'] ?? []);
    final trend = List<Map<String, dynamic>>.from(data['daily_trend'] ?? []);
    final zones = List<Map<String, dynamic>>.from(data['zone_analysis'] ?? []);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _InsightCard(
            title: 'Top Reasons',
            icon: Icons.info_outline_rounded,
            color: const Color(0xffF59E0B),
            rows: reasons.take(8).map((row) {
              return _InsightRow(
                title: (row['reason'] ?? 'No reason').toString(),
                value: '${row['count'] ?? 0} edits',
                subValue: 'Qty ${_numText(row['qty'])}',
              );
            }).toList(),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: _InsightCard(
            title: 'Daily Trend',
            icon: Icons.calendar_month_rounded,
            color: const Color(0xff3B82F6),
            rows: trend.take(8).map((row) {
              return _InsightRow(
                title: (row['date'] ?? '-').toString(),
                value: '${row['requests'] ?? 0} edits',
                subValue: 'Qty ${_numText(row['qty'])}',
              );
            }).toList(),
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: _InsightCard(
            title: 'Zone Analysis',
            icon: Icons.map_outlined,
            color: const Color(0xff14B8A6),
            rows: zones.take(8).map((row) {
              return _InsightRow(
                title: (row['zone'] ?? 'Unknown').toString(),
                value: '${row['requests'] ?? 0} edits',
                subValue: 'Qty ${_numText(row['qty'])}',
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  static String _numText(dynamic value) {
    final number = value is num
        ? value
        : num.tryParse((value ?? '').toString()) ?? 0;
    if (number == number.roundToDouble()) return number.toInt().toString();
    return number.toStringAsFixed(2);
  }
}

class _InsightCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<_InsightRow> rows;

  const _InsightCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
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
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No data available',
                  style: TextStyle(color: Color(0xff94A3B8)),
                ),
              ),
            )
          else
            ...rows.map(
              (row) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xffF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xffE2E8F0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff1E293B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          row.value,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          row.subValue,
                          style: const TextStyle(
                            color: Color(0xff64748B),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InsightRow {
  final String title;
  final String value;
  final String subValue;

  const _InsightRow({
    required this.title,
    required this.value,
    required this.subValue,
  });
}
