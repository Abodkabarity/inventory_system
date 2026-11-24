import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/stock_excel_export.dart';
import '../../../core/config/all_branches_trial_config.dart';
import '../../../core/config/online_overview_local_config.dart';
import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../data/datasources/remote/all_branches_trial_remote_ds.dart';
import '../../../domain/entities/stock_management.dart'
    show stockNumber, stockMap;
import '../../widgets/dashboard_theme.dart';
import 'online_overview_page.dart';

/// The reviewed study rollout retains the exact original account gate.
class OnlineOverviewTrialSwitch extends StatefulWidget {
  const OnlineOverviewTrialSwitch({super.key});
  @override
  State<OnlineOverviewTrialSwitch> createState() =>
      _OnlineOverviewTrialSwitchState();
}

class _OnlineOverviewTrialSwitchState extends State<OnlineOverviewTrialSwitch> {
  bool _all = true;
  bool _onlineOpened = false;
  @override
  Widget build(BuildContext context) {
    if (!AllBranchesTrialConfig.enabled) return const OnlineOverviewPage();
    if (!AllBranchesTrialConfig.canAccess(
      OnlineOverviewLocalConfig.currentUserId,
    )) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        Material(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Ranking trial',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      label: Text('All branches'),
                      icon: Icon(Icons.hub_outlined),
                    ),
                    ButtonSegment(
                      value: false,
                      label: Text('Online only'),
                      icon: Icon(Icons.storefront_outlined),
                    ),
                  ],
                  selected: {_all},
                  onSelectionChanged: (value) => setState(() {
                    _all = value.single;
                    if (!_all) _onlineOpened = true;
                  }),
                ),
                const Text(
                  'Online only returns to the saved page.',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _all ? 0 : 1,
            children: [
              const AllBranchesTrialPage(),
              if (_onlineOpened)
                const OnlineOverviewPage()
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}

const _ink = Color(0xFF202D4D);
final _qty = NumberFormat('#,##0.##');
String _number(Object? value) => _qty.format(stockNumber(value));
Color _color(String rank) => switch (rank) {
  'A' => const Color(0xFF008E8A),
  'B' => const Color(0xFF536DFE),
  'C' => const Color(0xFFD34075),
  'N' => const Color(0xFFC87919),
  'T' => const Color(0xFF8554CB),
  'S' => const Color(0xFF187FAD),
  _ => const Color(0xFF738299),
};
String _title(String rank) => switch (rank) {
  'A' => 'High priority',
  'B' => 'Medium sales',
  'C' => 'Low sales',
  'N' => 'New, in STORE',
  'M' => 'No branch stock or sales',
  'T' => 'Stock with no recent sales',
  'S' => 'In-house',
  _ => 'Needs review',
};
Widget _badge(String rank) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
  decoration: BoxDecoration(
    color: _color(rank).withValues(alpha: .12),
    borderRadius: BorderRadius.circular(9),
  ),
  child: Text(
    rank == 'REVIEW' ? 'Review' : rank,
    style: TextStyle(color: _color(rank), fontWeight: FontWeight.w800),
  ),
);

class AllBranchesTrialPage extends StatefulWidget {
  const AllBranchesTrialPage({super.key, this.dataSource, this.export});
  final AllBranchesTrialDataSource? dataSource;
  final Future<void> Function(List<Map<String, dynamic>>, String)? export;
  @override
  State<AllBranchesTrialPage> createState() => _AllBranchesTrialPageState();
}

class _AllBranchesTrialPageState extends State<AllBranchesTrialPage> {
  late final AllBranchesTrialDataSource _source;
  late final _TrialTable _table;
  AllBranchesTrialSnapshot? _data;
  String? _error;
  String _search = '', _rank = '', _purchase = '';
  bool _loading = true, _exporting = false;
  int _loadId = 0, _sort = 6;
  bool _ascending = false;
  @override
  void initState() {
    super.initState();
    _source =
        widget.dataSource ?? AllBranchesTrialRemoteDs(Supabase.instance.client);
    _table = _TrialTable(_open);
    _load();
  }

  @override
  void dispose() {
    _loadId++;
    _table.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _source.load();
      if (!mounted || id != _loadId) return;
      _data = data;
      _filter();
      setState(() => _loading = false);
    } catch (e) {
      if (mounted && id == _loadId) {
        setState(() {
          _error = e is PostgrestException && e.code == 'PT409'
              ? 'The branch list changed after this trial was prepared. Prepare the trial again, or choose Online only to return to the saved page.'
              : '$e';
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _visible => _table.values;
  void _filter() {
    _table.replace([
      for (final r in _data?.rows ?? <Map<String, dynamic>>[])
        if ((_rank.isEmpty || r['rank'] == _rank) &&
            (_purchase.isEmpty || r['purchase_status'] == _purchase) &&
            ('${r['code']} ${r['name']} ${r['supplier']}'
                .toLowerCase()
                .contains(_search.toLowerCase())))
          r,
    ]);
    _table.sort(_sort, _ascending);
  }

  void _changed(VoidCallback update) {
    setState(() {
      update();
      _filter();
    });
  }

  Future<void> _export() async {
    final rows = [
      for (final r in _visible)
        <String, dynamic>{
          'Priority': r['rank'],
          'Product': r['name'],
          'Code': r['code'],
          'Branch stock': r['stock_complete'] == true ? r['stock'] : null,
          'Known branch stock': r['stock'],
          'Store stock': r['store_stock'],
          'Online sales (Qty)': r['online_sales'],
          'Cash + Insurance sales (Qty)': r['other_sales'],
          'All sales (Qty)': r['total_sales'],
          'Sales value at current Retail (AED)': r['actual_value'],
          'Retail (AED)': r['retail'],
          'Branches with sales': r['selling_branches'],
          'Months with sales': r['selling_months'],
          'Online rank (same snapshot)': r['online_rank'],
          'Purchase status': r['purchase_status'],
          'Why this rank?': r['reason'],
          'Sales from': _data!.meta['sales_from'],
          'Sales through': _data!.meta['sales_through'],
        },
    ];
    setState(() => _exporting = true);
    try {
      await (widget.export ?? saveStockExcel)(rows, 'all_branches_trial');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: StoreBranchIdentityRegistry.groups,
    builder: (context, _, _) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      if (_error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        );
      }
      final meta = _data!.meta;
      final purchases =
          _data!.rows.map((r) => '${r['purchase_status']}').toSet().toList()
            ..sort();
      return LayoutBuilder(
        builder: (context, size) => ColoredBox(
          color: DashboardPalette.indigo.surface,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DashboardWaveHeader(
                  palette: DashboardPalette.indigo,
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Wrap(
                      spacing: 18,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Icon(
                          Icons.hub_outlined,
                          color: Colors.white,
                          size: 34,
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Online Overview · All branches trial',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${(meta['branches'] as List).length} selling branches · ${meta['sales_from']} to ${meta['sales_through']}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'Ranks use Online + Cash + Insurance sales. STORE stock is shown separately.',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _metrics(size.maxWidth),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: DashboardPalette.indigo.border,
                          ),
                        ),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: 270,
                              child: TextField(
                                onChanged: (v) => _changed(() => _search = v),
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.search),
                                  hintText: 'Search products',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 220,
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _purchase,
                                decoration: const InputDecoration(
                                  labelText: 'Purchase status',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: '',
                                    child: Text('All purchase statuses'),
                                  ),
                                  for (final p in purchases)
                                    DropdownMenuItem(
                                      value: p,
                                      child: Text(
                                        p,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (v) =>
                                    _changed(() => _purchase = v ?? ''),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reload'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _availability,
                              icon: const Icon(Icons.storefront_outlined),
                              label: const Text('Branch availability'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _guide,
                              icon: const Icon(Icons.menu_book_outlined),
                              label: const Text('Rank guide'),
                            ),
                            FilledButton.icon(
                              onPressed: _exporting ? null : _export,
                              icon: const Icon(Icons.download),
                              label: Text(
                                _exporting ? 'Exporting…' : 'Export Excel',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${_visible.length} products · Stock as of ${meta['stock_day']} · Online rank uses the same trial snapshot.',
                        style: const TextStyle(color: _ink, fontSize: 14),
                      ),
                      if ((meta['missing_stock_branches'] as List).isNotEmpty)
                        Text(
                          'Missing stock reports: ${(meta['missing_stock_branches'] as List).map(_branch).join(', ')}. Known stock is marked *.',
                          style: const TextStyle(color: Color(0xFFA66618)),
                        ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: size.maxWidth - 32,
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            cardTheme: const CardThemeData(
                              color: Colors.white,
                              surfaceTintColor: Colors.white,
                            ),
                          ),
                          child: PaginatedDataTable(
                            key: ValueKey(
                              'all-branches-table-$_rank-$_purchase-$_search',
                            ),
                            source: _table,
                            rowsPerPage: 25,
                            showCheckboxColumn: false,
                            showFirstLastButtons: true,
                            columnSpacing: 18,
                            horizontalMargin: 14,
                            dataRowMinHeight: 72,
                            dataRowMaxHeight: 72,
                            headingRowHeight: 62,
                            headingRowColor: const WidgetStatePropertyAll(
                              Color(0xFF42347E),
                            ),
                            sortColumnIndex: _sort,
                            sortAscending: _ascending,
                            columns: [
                              for (
                                var i = 0;
                                i < _TrialTable.columns.length;
                                i++
                              )
                                DataColumn(
                                  label: SizedBox(
                                    width: i == 1 ? 260 : 145,
                                    child: Text(
                                      _TrialTable.columns[i].$2,
                                      textAlign: i == 1
                                          ? TextAlign.start
                                          : TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  onSort: (column, ascending) => _changed(() {
                                    _sort = column;
                                    _ascending = ascending;
                                  }),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  Widget _metrics(double width) {
    final counts = stockMap(_data!.meta['counts']);
    final cols = width < 650
        ? 2
        : width < 1150
        ? 3
        : 5;
    return LayoutBuilder(
      builder: (context, box) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final rank in ['', 'A', 'B', 'C', 'N', 'M', 'T', 'S', 'REVIEW'])
            SizedBox(
              width: (box.maxWidth - (cols - 1) * 10) / cols,
              height: 88,
              child: DashboardMetricCard(
                id: rank.isEmpty ? 'all' : rank,
                title: rank.isEmpty
                    ? 'All products'
                    : '${rank == 'REVIEW' ? 'Review' : rank} · ${_title(rank)}',
                count: rank.isEmpty
                    ? _data!.rows.length
                    : stockNumber(counts[rank]).toInt(),
                icon: rank.isEmpty
                    ? Icons.inventory_2_outlined
                    : Icons.sell_outlined,
                color: _color(rank),
                background: [Colors.white, _color(rank).withValues(alpha: .08)],
                small: true,
                selected: _rank == rank,
                onTap: () => _changed(() => _rank = _rank == rank ? '' : rank),
              ),
            ),
          SizedBox(
            width: (box.maxWidth - (cols - 1) * 10) / cols,
            height: 88,
            child: DashboardMetricCard(
              id: 'changed',
              title: 'Different from Online rank',
              count: stockNumber(_data!.meta['changed']).toInt(),
              icon: Icons.swap_horiz,
              color: DashboardPalette.indigo.accent,
              background: const [Colors.white, Color(0xFFEEEBFC)],
              small: true,
              selected: false,
              onTap: _changes,
            ),
          ),
        ],
      ),
    );
  }

  String _branch(Object? raw) => StoreBranchIdentityRegistry.displayName(
    '$raw',
    {..._data!.groups, ...StoreBranchIdentityRegistry.groups.value},
  );
  Future<void> _modal(
    String title,
    Widget body, {
    String? rank,
  }) => showDialog<void>(
    context: context,
    builder: (context) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
      child: Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        insetPadding: const EdgeInsets.all(18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1028, maxHeight: 800),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DashboardWaveHeader(
                  modal: true,
                  palette: DashboardPalette.indigo,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (rank != null) _badge(rank),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Close',
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: DefaultTextStyle(
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 17,
                        height: 1.5,
                      ),
                      child: body,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Future<void> _open(Map<String, dynamic> row) async {
    final future = _source.details(_data!.generation, '${row['code']}');
    await _modal(
      '${row['name']} · ${row['code']}',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _title('${row['rank']}'),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _color('${row['rank']}'),
            ),
          ),
          const SizedBox(height: 8),
          Text('${row['reason']}'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 20,
            runSpacing: 12,
            children: [
              Text(
                'Branch stock: ${row['stock_complete'] == true ? '' : 'Known '}${_number(row['stock'])} Qty',
              ),
              Text(
                'STORE stock: ${row['store_stock'] == null ? 'Not reported' : _number(row['store_stock'])} Qty',
              ),
              Text('Online: ${_number(row['online_sales'])} Qty'),
              Text('Cash + Insurance: ${_number(row['other_sales'])} Qty'),
            ],
          ),
          const SizedBox(height: 12),
          Text('Purchase status: ${row['purchase_status']}'),
          const SizedBox(height: 18),
          FutureBuilder<Map<String, dynamic>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Column(
                  children: [
                    Text('Details could not load: ${snapshot.error}'),
                    TextButton(
                      onPressed: () => _retryDetails(row),
                      child: const Text('Retry'),
                    ),
                  ],
                );
              }
              if (!snapshot.hasData) return const LinearProgressIndicator();
              return _detailFacts(snapshot.data!);
            },
          ),
        ],
      ),
      rank: '${row['rank']}',
    );
  }

  void _retryDetails(Map<String, dynamic> row) {
    Navigator.pop(context);
    _open(row);
  }

  Widget _detailFacts(Map<String, dynamic> data) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Sales by month · Same 6 full months',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
      ),
      const SizedBox(height: 10),
      for (final raw in data['monthly'] as List)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(width: 100, child: Text('${raw['month']}')),
              Expanded(
                child: Text(
                  'Online ${_number(raw['online'])}   ·   Cash + Insurance ${_number(raw['other'])} Qty',
                ),
              ),
            ],
          ),
        ),
      const Divider(height: 30),
      const Text(
        'Stock and sales by branch',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
      ),
      const Text(
        'Branch · Stock · Online sales · Cash + Insurance sales',
        style: TextStyle(fontSize: 14),
      ),
      for (final raw in data['branches'] as List)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              SizedBox(
                width: 250,
                child: Text(
                  _branch(raw['name']),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                'Stock ${raw['stock'] == null ? 'Not reported' : _number(raw['stock'])}',
              ),
              Text('Online ${_number(raw['online'])}'),
              Text('Cash + Insurance ${_number(raw['other'])}'),
            ],
          ),
        ),
    ],
  );
  void _availability() => _modal(
    'Branch availability · A / B / C',
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Products with stock in each branch ÷ all products in that rank. These results do not change with page filters.',
        ),
        const Text(
          'Zero and negative stock are not available. Missing reports stay in the total and are shown separately.',
        ),
        const SizedBox(height: 18),
        for (final raw in (_data!.meta['availability'] as List? ?? []))
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F7FD),
              border: Border.all(color: DashboardPalette.indigo.border),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Wrap(
              spacing: 18,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 230,
                  child: Text(
                    _branch(raw['name']),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                for (final rank in ['A', 'B', 'C'])
                  SizedBox(
                    width: 180,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$rank · ${raw['ranks'][rank]['percent'] == null ? 'No products' : '${stockNumber(raw['ranks'][rank]['percent']).toStringAsFixed(1)}%'}',
                          style: TextStyle(
                            color: _color(rank),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${raw['ranks'][rank]['available']} of ${raw['ranks'][rank]['total']} · Missing ${raw['ranks'][rank]['missing']}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        LinearProgressIndicator(
                          value:
                              stockNumber(raw['ranks'][rank]['percent']) / 100,
                          color: _color(rank),
                          backgroundColor: _color(rank).withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );

  void _guide() {
    final c = stockMap(_data!.meta['thresholds']);
    _modal(
      'How this trial ranks products',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'All channels, all selling branches',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const Text(
            'We add Online, Cash and Insurance Qty after returns for the last 6 full months. The two sales columns use this same period. STORE is not a selling branch.',
          ),
          const SizedBox(height: 18),
          Text(
            'A · High priority',
            style: TextStyle(
              color: _color('A'),
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'One rule is enough: sales in 70% of branches (${c['minimum_A_branches']} branches), the top 35 out of 100 products by Qty, or the top 15 out of 100 by sales value. These paths need sales in 3 different months. Strong Qty can get A even if fewer branches sell it.',
          ),
          const Text(
            'A product priced AED 1,000 or more can also get A if it sells in at least 3 of the last 4 groups of 3 months, including the latest group. Price alone does not give A.',
          ),
          const SizedBox(height: 16),
          Text(
            'B · Medium sales',
            style: TextStyle(
              color: _color('B'),
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Text(
            'After checking A, B needs sales in 2 different months and must be in the top 60 out of 100 by Qty or the top 30 out of 100 by value.',
          ),
          const SizedBox(height: 16),
          Text(
            'C · Low sales',
            style: TextStyle(
              color: _color('C'),
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Text(
            'The remaining products with sales history. Qty or value is lower, or sales happened in too few months for B.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Fair treatment for new products',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          const Text(
            'New means less than 6 calendar months since the first approved positive MRN. We compare its daily sales rate over the same 6-month length, using at least 30 days. This is a fair comparison, not extra recorded sales. A needs at least 2 selling months when only 2 months are available; B can use the first available month. Earlier recorded sales are kept.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Other groups are checked first',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          const Text(
            'S: INHOUSE. N: new by MRN, every selling branch reports exactly 0 Qty, and STORE has positive stock. M: every branch has 0 Qty and there were no sales in either year. T: branch stock exists but no sales in the last 6 full months or the current month. Review: no sales and stock is missing or below 0. The order is S, N, M, T, then the sales rules.',
          ),
          const SizedBox(height: 16),
          const Text(
            'The percentages compare products, not the share of total sales. Equal results stay together. Value is Qty × current Retail, not the invoice amount. All branches use their own cutoffs; Online rank is calculated separately from this same snapshot.',
          ),
        ],
      ),
    );
  }

  void _changes() => _modal(
    'Online rank → All branches rank',
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Both use the same trial snapshot and rules. Only the selling network and sales channels differ.',
        ),
        const SizedBox(height: 16),
        for (final raw in _data!.meta['transitions'] as List)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '${raw['before']} → ${raw['after']}: ${raw['count']} products',
            ),
          ),
      ],
    ),
  );
}

class _TrialTable extends DataTableSource {
  _TrialTable(this.open);
  final ValueChanged<Map<String, dynamic>> open;
  List<Map<String, dynamic>> values = [];
  static const columns = <(String, String)>[
    ('rank', 'Priority'),
    ('name', 'Product'),
    ('stock', 'Branch stock'),
    ('store_stock', 'STORE stock'),
    ('online_sales', 'Online sales\n6 months (Qty)'),
    ('other_sales', 'Cash + Insurance sales\n6 months (Qty)'),
    ('total_sales', 'All sales\n6 months (Qty)'),
    ('actual_value', 'Sales value at Retail\n6 months (AED)'),
    ('selling_branches', 'Branches with sales'),
    ('selling_months', 'Months with sales'),
    ('retail', 'Retail (AED)'),
    ('purchase_status', 'Purchase status'),
    ('online_rank', 'Online rank\nSame snapshot'),
  ];
  void replace(List<Map<String, dynamic>> next) {
    values = next;
    notifyListeners();
  }

  void sort(int column, bool ascending) {
    final key = columns[column].$1;
    values.sort((a, b) {
      final x = a[key], y = b[key];
      final c = x is num && y is num ? x.compareTo(y) : '$x'.compareTo('$y');
      return (ascending ? c : -c) != 0
          ? (ascending ? c : -c)
          : '${a['code']}'.compareTo('${b['code']}');
    });
    notifyListeners();
  }

  @override
  DataRow? getRow(int index) {
    if (index >= values.length) return null;
    final r = values[index];
    return DataRow.byIndex(
      index: index,
      onSelectChanged: (_) => open(r),
      color: WidgetStatePropertyAll(
        index.isEven ? Colors.white : const Color(0xFFF7F6FC),
      ),
      cells: [
        for (var j = 0; j < columns.length; j++)
          DataCell(
            Container(
              width: j == 1 ? 260 : 145,
              alignment: j == 1 ? Alignment.centerLeft : Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: DashboardPalette.indigo.border),
                ),
              ),
              padding: const EdgeInsets.only(right: 10),
              child: j == 0
                  ? _badge('${r['rank']}')
                  : j == 1
                  ? Text(
                      '${r['name']}\n${r['code']}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _ink,
                      ),
                    )
                  : Text(
                      switch (columns[j].$1) {
                        'selling_branches' =>
                          '${r['selling_branches']} of ${r['total_branches']}',
                        'stock' =>
                          '${_number(r['stock'])}${r['stock_complete'] == true ? '' : ' *'}',
                        'store_stock' =>
                          r['store_stock'] == null
                              ? 'Not reported'
                              : _number(r['store_stock']),
                        'online_rank' ||
                        'purchase_status' => '${r[columns[j].$1]}',
                        _ => _number(r[columns[j].$1]),
                      },
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: j == 4
                            ? const Color(0xFF007F90)
                            : j == 5
                            ? DashboardPalette.indigo.accent
                            : _ink,
                      ),
                    ),
            ),
          ),
      ],
    );
  }

  @override
  int get rowCount => values.length;
  @override
  bool get isRowCountApproximate => false;
  @override
  int get selectedRowCount => 0;
}
