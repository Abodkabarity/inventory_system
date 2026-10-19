import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/utils/stock_catalog_export.dart';
import '../../../core/utils/stock_item_added_date.dart';
import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../data/datasources/remote/stock_catalog_remote_ds.dart';
import '../../../domain/entities/stock_catalog.dart';
import '../../../domain/entities/stock_management.dart';
import '../widgets/stock_catalog_visuals.dart';
import '../widgets/stock_sales_summary.dart';
import '../widgets/stock_distribution_widgets.dart';

class StockCatalogProductDialog extends StatefulWidget {
  final StockCatalogItem item;
  final StockCatalogDataSource source;
  const StockCatalogProductDialog({
    super.key,
    required this.item,
    required this.source,
  });
  @override
  State<StockCatalogProductDialog> createState() =>
      _StockCatalogProductDialogState();
}

class _StockCatalogProductDialogState extends State<StockCatalogProductDialog> {
  late Future<StockCatalogItem> _future;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _branchScroll = ScrollController();
  String _sort = 'recent_sales';
  bool _descending = true;
  bool _uncoveredOnly = false;
  @override
  void initState() {
    super.initState();
    _future = widget.source.fetchItem(widget.item.code);
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _branchScroll.dispose();
    super.dispose();
  }

  Future<void> _save(List<Map<String, dynamic>> rows, String name) async {
    try {
      final source = widget.source;
      if (rows.any((r) => r.containsKey('branch')) &&
          source is StockCatalogRemoteDs) {
        await StoreBranchIdentityRegistry.load(source.client);
        if (rows.any(
          (r) => !StoreBranchIdentityRegistry.groups.value.containsKey(
            (r['branch']?.toString() ?? '').trim().toUpperCase(),
          ),
        )) {
          throw StateError(
            'Branch labels are still loading. Retry the export shortly.',
          );
        }
      }
      await saveCatalogCsv(rows, name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      Theme(data: catalogControlTheme(context), child: _dialog(context));

  Widget _dialog(BuildContext context) => Dialog(
    insetPadding: EdgeInsets.all(
      MediaQuery.sizeOf(context).width < 700 ? 8 : 26,
    ),
    backgroundColor: const Color(0xFFF3F6FC),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    child: SizedBox(
      width: 1420,
      height: MediaQuery.sizeOf(context).height * .93,
      child: Column(
        children: [
          _header(),
          Expanded(
            child: FutureBuilder<StockCatalogItem>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Could not load product details. ${snapshot.error}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: () => setState(
                            () => _future = widget.source.fetchItem(
                              widget.item.code,
                            ),
                          ),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final item = snapshot.data!.withDistributionRules(
                  widget.item.distributionRules,
                );
                return ValueListenableBuilder<Map<String, String>>(
                  valueListenable: StoreBranchIdentityRegistry.groups,
                  builder: (context, _, _) => Scrollbar(
                    controller: _scroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.all(20),
                      child: LayoutBuilder(
                        builder: (context, size) {
                          final compact = size.maxWidth < 850;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _alerts(item),
                              const SizedBox(height: 16),
                              _metrics(item, size.maxWidth),
                              if (item.distributionStatus.isNew) ...[
                                const SizedBox(height: 18),
                                StockDistributionPanel(item: item),
                              ],
                              const SizedBox(height: 18),
                              if (compact) ...[
                                _monthly(item),
                                const SizedBox(height: 16),
                                _stock(item),
                              ] else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 7, child: _monthly(item)),
                                    const SizedBox(width: 16),
                                    Expanded(flex: 3, child: _stock(item)),
                                  ],
                                ),
                              const SizedBox(height: 18),
                              if (compact) ...[
                                _annual(item),
                                const SizedBox(height: 16),
                                _facts(item),
                              ] else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: _annual(item)),
                                    const SizedBox(width: 16),
                                    Expanded(child: _facts(item)),
                                  ],
                                ),
                              const SizedBox(height: 18),
                              if (compact) ...[
                                _ranking(
                                  item,
                                  'recent_sales',
                                  'Best-selling branches',
                                  '45-day net Qty',
                                  catalogPurple,
                                ),
                                const SizedBox(height: 16),
                                _ranking(
                                  item,
                                  'stock',
                                  'Highest-stock branches',
                                  'Current stock balance',
                                  catalogTeal,
                                ),
                              ] else
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _ranking(
                                        item,
                                        'recent_sales',
                                        'Best-selling branches',
                                        '45-day net Qty',
                                        catalogPurple,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _ranking(
                                        item,
                                        'stock',
                                        'Highest-stock branches',
                                        'Current stock balance',
                                        catalogTeal,
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 18),
                              _branches(item),
                              const SizedBox(height: 18),
                              Text(
                                'Snapshot ${catalogDate(stockMap(item.data['meta'])['refreshed_at'])} • Stock ${catalogDate(stockMap(item.data['meta'])['stock_updated_at'])} • Annual branch totals are loaded live. All quantities are net Qty.',
                                style: const TextStyle(
                                  color: catalogMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(24, 20, 14, 20),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF1A2C50), Color(0xFF343C73), Color(0xFF176370)],
      ),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.analytics_outlined,
            color: Color(0xFF8BE6D9),
            size: 27,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PRODUCT INTELLIGENCE',
                style: TextStyle(
                  color: Color(0xFFB7CBE7),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.7,
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                widget.item.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SelectableText(
                    'SKU ${widget.item.code}  •  ${widget.item.text('company')}',
                    style: const TextStyle(
                      color: Color(0xFFD2DFF2),
                      fontSize: 12,
                    ),
                  ),
                  FutureBuilder<StockCatalogItem>(
                    future: _future,
                    builder: (context, snapshot) {
                      final item = snapshot.data ?? widget.item;
                      return Container(
                        key: const ValueKey('product-created-at'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 13,
                              color: Color(0xFF8BE6D9),
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: SelectableText(
                                'Created date  ${formatStockItemAddedDate(item.data['added_date_time'])}',
                                style: const TextStyle(
                                  color: Color(0xFFD2DFF2),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Close details',
          icon: const Icon(Icons.close_rounded, color: Colors.white),
        ),
      ],
    ),
  );
  Widget _alerts(StockCatalogItem item) {
    final meta = stockMap(item.data['meta']);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        CatalogPill(item.signal, color: catalogSignalColor(item)),
        if (item.salesExceedStock)
          CatalogPill(
            '45-day sales exceed stock by ${catalogQty(item.number('recent_sales') - item.number('total_stock'))} Qty',
            color: catalogRose,
          ),
        if (item.surge)
          CatalogPill(
            '${(item.number('recent_daily') / item.number('baseline_daily')).toStringAsFixed(1)}× daily demand • +${item.growth!.toStringAsFixed(1)}%',
            color: catalogPurple,
          ),
        if (item.newDemand)
          const CatalogPill(
            'Recent demand after a non-positive baseline',
            color: catalogPurple,
          ),
        CatalogPill(
          'Sales through ${catalogDate(meta['demand_through'])}',
          color: catalogBlue,
        ),
        if (stockNumber(meta['baseline_days']) < 42 ||
            stockNumber(meta['recent_days']) < 3)
          const CatalogPill(
            'Partial sales window • see period dates',
            color: catalogOrange,
          ),
      ],
    );
  }

  Widget _metrics(StockCatalogItem item, double width) {
    final meta = stockMap(item.data['meta']);
    final cols = width < 580
        ? 2
        : width < 1100
        ? 3
        : 6;
    final w = (width - (cols - 1) * 12) / cols;
    final data = [
      (
        'LAST 3 DAYS QTY',
        catalogQty(item.number('last_3_sales')),
        '${catalogDate(meta['recent_from'])} – ${catalogDate(meta['demand_through'])}',
        catalogPurple,
        Icons.bolt_rounded,
      ),
      (
        '42-DAY DAILY AVG',
        item.data['baseline_daily'] == null
            ? '—'
            : catalogQty(item.number('baseline_daily')),
        '${catalogQty(item.number('baseline_sales'))} Qty / ${meta['baseline_days'] ?? '—'} calendar days',
        catalogBlue,
        Icons.timeline_rounded,
      ),
      (
        'TOTAL QTY (45D)',
        catalogQty(item.number('recent_sales')),
        '${catalogDate(meta['demand_from'])} – ${catalogDate(meta['demand_through'])}',
        catalogTeal,
        Icons.shopping_bag_outlined,
      ),
      (
        'STOCK COVER',
        catalogCover(item),
        'Total stock / 45-day daily net demand',
        item.days != null && item.days! < 30 ? catalogRose : catalogTeal,
        Icons.hourglass_bottom_rounded,
      ),
      (
        'BRANCHES / STORE',
        item.branchesStorePercent == null
            ? '—'
            : '${item.branchesStorePercent!.toStringAsFixed(1)}%',
        'Ratio of balances; may exceed 100%',
        catalogBlue,
        Icons.compare_arrows_rounded,
      ),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (var i = 0; i < data.length; i++) ...[
          if (i == 2)
            SizedBox(
              width: w,
              child: CatalogGrowthMetric(item: item),
            ),
          SizedBox(
            width: w,
            child: CatalogMetric(
              title: data[i].$1,
              value: data[i].$2,
              caption: data[i].$3,
              color: data[i].$4,
              icon: data[i].$5,
            ),
          ),
        ],
      ],
    );
  }

  Widget _monthly(StockCatalogItem item) => CatalogPanel(
    title: 'Monthly sales & momentum',
    subtitle:
        '2025 to 2026 • All source branches • Hover or tap a month for exact values',
    trailing: IconButton(
      onPressed: () =>
          _save(item.list('monthly_sales'), '${item.code}_monthly_sales.csv'),
      tooltip: 'Export monthly sales',
      icon: const Icon(Icons.download_rounded, size: 19, color: catalogBlue),
    ),
    child: CatalogMonthlyChart(item: item),
  );
  Widget _stock(StockCatalogItem item) => CatalogPanel(
    title: 'Available vs sold',
    subtitle: 'Current stock against 45-day net sales',
    child: Column(
      children: [
        CatalogStockChart(item: item),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            CatalogPill(
              'STORE ${catalogQty(item.number('store_stock'))}',
              color: catalogBlue,
            ),
            CatalogPill(
              'Branches ${catalogQty(item.number('branches_stock'))}',
            ),
            CatalogPill(
              'APG ${catalogQty(item.number('apg_stock'))}',
              color: catalogPurple,
            ),
            CatalogPill(
              '71 ${catalogQty(item.number('stock_71'))}',
              color: catalogOrange,
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Total = STORE + all branches.',
          style: TextStyle(color: catalogMuted, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
  Widget _annual(StockCatalogItem item) => CatalogPanel(
    title: 'Annual sales mix',
    subtitle: 'Cash • Insurance • Online — net Qty',
    child: Column(
      children: [
        for (final year in [2025, 2026])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F8FD),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: Text(
                      '$year',
                      style: TextStyle(
                        color: year == 2025 ? catalogBlue : catalogTeal,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Expanded(
                    child: StockSalesSummary(
                      data: item.year(year),
                      totalColor: year == 2025 ? catalogBlue : catalogTeal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            for (final year in [2025, 2026])
              CatalogPill(
                'Best $year: ${item.year(year)['best_month'] ?? '—'} • ${catalogQty(item.year(year)['best_qty'])} Qty',
                color: year == 2025 ? catalogBlue : catalogTeal,
              ),
          ],
        ),
      ],
    ),
  );
  Widget _facts(StockCatalogItem item) => CatalogPanel(
    title: 'Product profile',
    subtitle: 'Catalog facts from Item Report',
    child: Wrap(
      spacing: 20,
      runSpacing: 16,
      children: [
        for (final entry in [
          ('added_date_time', 'Created date'),
          ('supplier', 'Supplier'),
          ('company', 'Company'),
          ('category', 'Category'),
          ('sub_category', 'Sub-category'),
          ('barcode', 'Barcode'),
          ('is_upp', 'UPP flag'),
          ('insurance_tier', 'Insurance tier'),
          ('retail', 'Retail (AED)'),
          ('tax_percent', 'VAT %'),
          ('main_ingredient', 'Main ingredient'),
          ('indication', 'Indication'),
          ('pack_size_volume', 'Pack size'),
          ('concentration', 'Concentration'),
          ('product_type', 'Product form'),
          ('item_status', 'Purchase type'),
          ('store_classification', 'Store classification'),
          ('min_order_unit', 'Minimum order Qty'),
        ])
          SizedBox(
            width: 190,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.$2.toUpperCase(),
                  style: const TextStyle(
                    color: catalogMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .6,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  entry.$1 == 'added_date_time'
                      ? formatStockItemAddedDate(item.data[entry.$1])
                      : item.text(entry.$1).isEmpty
                      ? '—'
                      : item.text(entry.$1),
                  style: const TextStyle(
                    color: catalogInk,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
  Widget _ranking(
    StockCatalogItem item,
    String key,
    String title,
    String subtitle,
    Color color,
  ) {
    final branches = item.list('branches')
      ..sort((a, b) => stockNumber(b[key]).compareTo(stockNumber(a[key])));
    final top = branches.where((b) => stockNumber(b[key]) > 0).take(5).toList();
    final maxValue = top.isEmpty ? 1.0 : stockNumber(top.first[key]);
    return CatalogPanel(
      title: title,
      subtitle: subtitle,
      child: top.isEmpty
          ? const Text(
              'No positive balances in this period',
              style: TextStyle(color: catalogMuted),
            )
          : Column(
              children: [
                for (var i = 0; i < top.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Text(
                              '${i + 1}'.padLeft(2, '0'),
                              style: TextStyle(
                                color: color,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                StoreBranchIdentityRegistry.displayName(
                                  top[i]['branch']?.toString(),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: catalogInk,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              catalogQty(top[i][key]),
                              style: TextStyle(
                                color: color,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        CatalogMotion(
                          builder: (p) => ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: stockNumber(top[i][key]) / maxValue * p,
                              minHeight: 9,
                              color: color,
                              backgroundColor: color.withValues(alpha: .08),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _branches(StockCatalogItem item) {
    final hasDistribution = stockMap(item.data['distribution']).isNotEmpty;
    final rows =
        catalogBranchRows(item)
            .where(
              (row) =>
                  !_uncoveredOnly ||
                  (row['distribution_eligible'] == true &&
                      stockNumber(row['stock']) <= 0 &&
                      stockNumber(row['final_qty']) <= 0),
            )
            .where(
              (row) => StoreBranchIdentityRegistry.displayName(
                row['branch']?.toString(),
              ).toLowerCase().contains(_search.text.trim().toLowerCase()),
            )
            .toList()
          ..sort((a, b) {
            final order = _sort == 'branch'
                ? StoreBranchIdentityRegistry.displayName(
                    a['branch']?.toString(),
                  ).compareTo(
                    StoreBranchIdentityRegistry.displayName(
                      b['branch']?.toString(),
                    ),
                  )
                : a[_sort] == null
                ? (b[_sort] == null ? 0 : 1)
                : b[_sort] == null
                ? -1
                : stockNumber(a[_sort]).compareTo(stockNumber(b[_sort]));
            if (_sort != 'branch' && (a[_sort] == null || b[_sort] == null)) {
              return order;
            }
            return order == 0
                ? '${a['branch']}'.compareTo('${b['branch']}')
                : _descending
                ? -order
                : order;
          });
    final meta = stockMap(item.data['meta']);
    final recentDays = stockNumber(meta['recent_days']),
        baselineDays = stockNumber(meta['baseline_days']);
    final columns = [
      ('branch', 'Branch'),
      ('stock', 'Stock'),
      if (hasDistribution) ...[
        ('reorder_qty', 'Reorder qty'),
        ('final_qty', 'Final order qty'),
      ],
      ('recent_sales', 'Sales 45D'),
      ('last_3_sales', 'Last 3D'),
      ('baseline_daily', '42D avg/day'),
      ('sales_2025', 'Sales 2025'),
      ('sales_2026', 'Sales 2026'),
      ('cover', 'Cover days'),
    ];
    return CatalogPanel(
      title: 'Branch intelligence',
      subtitle:
          '${rows.length} active branches • Stock and recent demand share one snapshot • Click a column to rank',
      trailing: IconButton(
        onPressed: () => _save([
          for (final r in rows)
            {
              ...r,
              'item_code': item.code,
              'item_name': item.name,
              'baseline_daily': baselineDays > 0
                  ? stockNumber(r['baseline_sales']) / baselineDays
                  : null,
            },
        ], '${item.code}_branches.csv'),
        tooltip: 'Export visible branches',
        icon: const Icon(Icons.download_rounded, color: catalogBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search branch (including 71)',
                    prefixIcon: Icon(Icons.search_rounded),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              for (final entry in [
                ('recent_sales', 'Top sellers (45D)'),
                ('sales_2026', 'Top sellers (2026)'),
                ('stock', 'Highest stock'),
              ])
                ChoiceChip(
                  label: Text(entry.$2),
                  selected: _sort == entry.$1,
                  onSelected: (_) => setState(() {
                    _sort = entry.$1;
                    _descending = true;
                  }),
                ),
              if (hasDistribution)
                FilterChip(
                  label: const Text('Uncovered eligible branches'),
                  selected: _uncoveredOnly,
                  onSelected: (value) => setState(() => _uncoveredOnly = value),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Scrollbar(
            controller: _branchScroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _branchScroll,
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: const WidgetStatePropertyAll(
                  Color(0xFFF0F4FC),
                ),
                headingRowHeight: 48,
                dataRowMinHeight: 48,
                dataRowMaxHeight: 66,
                columnSpacing: 26,
                sortColumnIndex: math.max(
                  0,
                  columns.indexWhere((c) => c.$1 == _sort),
                ),
                sortAscending: !_descending,
                columns: [
                  for (final c in columns)
                    DataColumn(
                      label: Text(
                        c.$2,
                        style: const TextStyle(
                          color: catalogInk,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      numeric: c.$1 != 'branch',
                      onSort: (i, ascending) => setState(() {
                        _sort = c.$1;
                        _descending = !ascending;
                      }),
                    ),
                ],
                rows: [
                  for (final row in rows)
                    _branchRow(row, baselineDays, recentDays, hasDistribution),
                ],
              ),
            ),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No matching branches',
                style: TextStyle(color: catalogMuted),
              ),
            ),
          const SizedBox(height: 10),
          const Text(
            'Red balance: 45-day sales exceed current branch stock. Coverage uses branch stock and branch demand. Negative quantities retain returns.',
            style: TextStyle(color: catalogMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  DataRow _branchRow(
    Map<String, dynamic> row,
    double baselineDays,
    double recentDays,
    bool hasDistribution,
  ) {
    final stock = stockNumber(row['stock']),
        sales = stockNumber(row['recent_sales']);
    final days = baselineDays + recentDays;
    final cover = stock <= 0
        ? 0.0
        : sales > 0 && days > 0
        ? stock / (sales / days)
        : null;
    final values = [
      row['stock'],
      if (hasDistribution) ...[row['reorder_qty'], row['final_qty']],
      row['recent_sales'],
      row['last_3_sales'],
      baselineDays > 0
          ? stockNumber(row['baseline_sales']) / baselineDays
          : null,
      row['sales_2025'],
      row['sales_2026'],
      cover,
    ];
    return DataRow(
      color: WidgetStatePropertyAll(
        sales > stock ? const Color(0xFFFFF4F6) : Colors.white,
      ),
      cells: [
        DataCell(
          Text(
            StoreBranchIdentityRegistry.displayName(row['branch']?.toString()),
            style: const TextStyle(
              color: catalogInk,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        for (var i = 0; i < values.length; i++)
          DataCell(
            Text(
              values[i] == null ? '—' : catalogQty(values[i]),
              style: TextStyle(
                color: i == 0 && sales > stock ? catalogRose : catalogInk,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}
