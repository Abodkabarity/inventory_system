import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/config/stock_product_image_config.dart';
import '../../../data/datasources/remote/stock_product_image_service.dart';
import '../../../domain/entities/stock_catalog.dart';
import '../../../core/utils/online_overview_export.dart';
import '../../../core/utils/stock_excel_export.dart';
import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../data/datasources/remote/online_overview_remote_ds.dart';
import '../../../domain/entities/online_overview.dart';
import '../../../domain/entities/stock_management.dart'
    show stockMap, stockNumber;
import '../../widgets/inventory_dropdown.dart';
import '../widgets/online_overview_grid.dart';
import '../widgets/stock_catalog_visuals.dart';
import '../widgets/online_product_insights.dart';
import '../widgets/online_availability_dialog.dart';
import 'stock_catalog_product_dialog.dart';

class OnlineOverviewPage extends StatefulWidget {
  final OnlineOverviewDataSource? dataSource;
  final Future<void> Function(List<Map<String, dynamic>>, String)? export;
  const OnlineOverviewPage({super.key, this.dataSource, this.export});
  @override
  State<OnlineOverviewPage> createState() => _OnlineOverviewPageState();
}

class _OnlineOverviewPageState extends State<OnlineOverviewPage> {
  late final OnlineOverviewDataSource _source;
  late final OnlineOverviewGridSource _grid;
  final _search = TextEditingController();
  final _audits = <String, OnlineProductAudit>{};
  OnlineOverviewSnapshot? _snapshot;
  List<OnlineOverviewRow> _ranked = [];
  String _branch = '', _purchase = '', _rank = '';
  bool _showMobileFilters = false;
  String? _error, _auditError;
  String _progress = 'Loading products…';
  bool _loading = true, _checking = false, _exporting = false;
  bool _refreshing = false;
  bool _preparationFailed = false;
  Timer? _poll;
  int _request = 0, _auditRequest = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _source =
        widget.dataSource ?? OnlineOverviewRemoteDs(Supabase.instance.client);
    _grid = OnlineOverviewGridSource(
      onOpen: _open,
      onAudit: (row) => _check([row]),
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    _request++;
    _auditRequest++;
    _search.dispose();
    _debounce?.cancel();
    _poll?.cancel();
    _grid.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    _auditRequest++;
    setState(() {
      _loading = true;
      _checking = false;
      _error = null;
      _auditError = null;
      _progress = 'Loading products…';
    });
    try {
      final snapshot = await _source.load(
        branch: _branch,
        isCancelled: () => !mounted || request != _request,
        onProgress: (message) {
          if (mounted && request == _request) {
            setState(() => _progress = message);
          }
        },
      );
      if (!mounted || request != _request) return;
      _snapshot = snapshot;
      _audits.clear();
      if (!snapshot.branches.any((branch) => branch.name == _branch)) {
        _branch = '';
      }
      setState(() => _loading = false);
      _rebuild();
      if (snapshot.refreshStatus == 'queued') _watchRefresh();
    } on OnlineSnapshotNotReady catch (error) {
      if (!mounted || request != _request) return;
      if (error.status == 'failed') {
        setState(() {
          _preparationFailed = true;
          _loading = false;
          _error = 'Could not load the first update. Tap Retry.';
        });
      } else {
        await _prepare();
      }
    } catch (error) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          debugPrint('Online Overview load failed: $error');
          _error = 'Could not load products. Tap Retry.';
        });
      }
    }
  }

  void _rebuild() {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    _ranked = [...?snapshot.preparedRows]
      ..sort((a, b) {
        final rankOrder = a.rank.index.compareTo(b.rank.index);
        if (rankOrder != 0) return rankOrder;
        final recent = b.recentQty.compareTo(a.recentQty);
        return recent != 0 ? recent : a.item.code.compareTo(b.item.code);
      });
    if (_purchase.isNotEmpty &&
        !_ranked.any((row) => row.purchaseStatus == _purchase)) {
      _purchase = '';
    }
    _filter();
  }

  Future<void> _prepare() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _preparationFailed = false;
      _error = null;
      if (_snapshot == null) _loading = true;
      _auditError = null;
      _progress = 'Updating sales and stock…';
    });
    try {
      await _source.requestRefresh();
      if (mounted) _watchRefresh();
    } catch (error) {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _loading = false;
          _error = _snapshot == null
              ? 'Could not update products. Tap Retry.'
              : null;
          _auditError =
              'Could not start the update. Showing the last saved data.';
        });
      }
    }
  }

  void _watchRefresh() {
    _poll?.cancel();
    _refreshing = true;
    var checking = false;
    Future<void> poll() async {
      if (checking || !mounted) return;
      checking = true;
      try {
        final state = await _source.refreshState();
        if (!mounted) return;
        if (state['status'] == 'complete') {
          _poll?.cancel();
          setState(() => _refreshing = false);
          await _load();
        } else if (state['status'] == 'failed') {
          _poll?.cancel();
          setState(() {
            _refreshing = false;
            _auditError = 'The update failed. Showing the last saved data.';
            if (_snapshot == null) {
              _loading = false;
              _error = _auditError;
            }
          });
        }
      } catch (_) {
        if (mounted) {
          setState(
            () => _auditError = 'Connection lost. Reload to check the update.',
          );
        }
      } finally {
        checking = false;
      }
    }

    _poll = Timer.periodic(const Duration(seconds: 3), (_) => poll());
    unawaited(poll());
  }

  void _filter() {
    final search = _search.text.trim().toLowerCase();
    _grid.replace(
      _ranked
          .where(
            (row) =>
                (_rank.isEmpty || row.rank.name == _rank) &&
                (_purchase.isEmpty || row.purchaseStatus == _purchase) &&
                (search.isEmpty ||
                    '${row.item.code} ${row.item.name} ${row.purchaseStatus} '
                            '${row.item.text('supplier')} ${row.reason} ${row.action}'
                        .toLowerCase()
                        .contains(search)),
          )
          .toList(),
    );
    setState(() {});
    _viewChanged();
  }

  void _viewChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _check(List<OnlineOverviewRow> rows) async {
    if (_checking || rows.isEmpty) return;
    final request = ++_auditRequest;
    final codes = rows.map((row) => row.item.code).toSet().toList();
    setState(() {
      _checking = true;
      _auditError = null;
    });
    var failed = 0;
    // Sequential, cancellable product metadata requests, not a raw movement dump.
    for (final code in codes) {
      if (!mounted || request != _auditRequest) return;
      try {
        final audit = await _source.audit(
          code,
          generation: _snapshot!.generation,
        );
        if (!mounted || request != _auditRequest) return;
        _audits[code] = audit;
      } catch (_) {
        if (!mounted || request != _auditRequest) return;
        _audits.remove(code);
        failed++;
      }
      _rebuild();
    }
    if (!mounted || request != _auditRequest) return;
    setState(() {
      _checking = false;
      _auditError = failed == 0
          ? null
          : '$failed products could not be checked. '
                'Their history remains unknown; retry the check.';
    });
  }

  Future<void> _export() async {
    final snapshot = _snapshot;
    if (snapshot == null || _exporting || _grid.displayedRows.isEmpty) return;
    final selectedRows = List<OnlineOverviewRow>.of(_grid.displayedRows);
    final selectedAudits = Map<String, OnlineProductAudit>.of(_audits);
    setState(() => _exporting = true);
    try {
      final rows = onlineOverviewExportRows(
        selectedRows,
        snapshot: snapshot,
        scope: OnlineSalesScope.onlineOnly,
        audits: selectedAudits,
      );
      await (widget.export ?? saveStockExcel)(rows, 'online_overview.xlsx');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not export. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _clear() async {
    _debounce?.cancel();
    _search.clear();
    _rank = _purchase = '';
    _grid.clearFilters();
    _grid.sortedColumns.clear();
    await _grid.sort();
    if (!mounted) return;
    _filter();
  }

  Future<void> _open(OnlineOverviewRow row) async {
    final generation = _snapshot!.generation;
    final branch = _branch;
    final remote = _source is OnlineOverviewRemoteDs ? _source : null;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => StockCatalogProductDialog(
          item: row.item,
          loadItem: () async {
            final (branches, months, recent, forecast) = await (
              _source.stockBreakdown(row.item.code, generation: generation),
              _source.monthlyOnlineSales(
                row.item.code,
                generation: generation,
                branch: branch,
              ),
              _source.recentOnlineSales(
                row.item.code,
                generation: generation,
                branch: branch,
              ),
              row.hasSalesForecast
                  ? _source.forecastDetails(
                      row.item.code,
                      generation: generation,
                    )
                  : Future.value(<String, dynamic>{}),
            ).wait;
            return StockCatalogItem({
              ...row.item.data,
              'branches': [
                for (final entry in branches)
                  if (row.branchNames.contains(entry['branch_name']))
                    {
                      'branch': entry['branch_name'],
                      'stock': entry['stock'],
                      'sales_2025': entry['sales_2025'],
                      'sales_2026': entry['sales_2026'],
                      'recent_sales': entry['recent_sales'],
                    },
              ],
              'online_recent_sales': recent,
              'online_forecast_details': forecast,
              'purchase_status_items': row.purchaseStatus,
              'online_monthly_sales': months,
            });
          },
          resolveImage: remote != null && StockProductImageConfig.enabled
              ? StockProductImageService.forClient(remote.client).resolve
              : null,
          detailsSection: (item) => Column(
            children: [
              OnlineProductInsights(row: row),
              if (row.hasSalesForecast) ...[
                const SizedBox(height: 14),
                OnlineProductForecast(
                  row: row,
                  details: stockMap(item.data['online_forecast_details']),
                  branchStock: item.list('branches'),
                ),
              ],
            ],
          ),
          salesPanels: (item) {
            final months = item.list('online_monthly_sales');
            final recent = stockMap(item.data['online_recent_sales']);
            return (
              summary: OnlineProductSummary(row: row, sales45: recent['qty']),
              monthly: OnlineProductSales(months: months, branch: branch),
              annual: OnlineProductSales(
                months: months,
                branch: branch,
                annual: true,
              ),
              stock: OnlineProductStock(
                row: row,
                recent: recent,
                branches: item.list('branches'),
                audit: _audits[row.item.code],
                checking: _checking,
                error: _auditError,
                onCheck: () async {
                  final future = _check([row]);
                  updateDialog(() {});
                  await future;
                  if (dialogContext.mounted) updateDialog(() {});
                },
              ),
            );
          },
        ),
      ),
    );
  }

  void _availability() {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => OnlineAvailabilityDialog(
        snapshot: snapshot,
        load: () => _source.branchAvailability(generation: snapshot.generation),
      ),
    );
  }

  void _rules() {
    final thresholds = stockMap(_snapshot?.serverMeta['thresholds']);
    final examples = <OnlineRank, OnlineOverviewRow>{};
    OnlineOverviewRow? quantityExample;
    OnlineOverviewRow? highPriceExample;
    for (final row in _ranked) {
      examples.putIfAbsent(row.rank, () => row);
      if (row.rank == OnlineRank.a &&
          row.classification['priority_route'] == 'forecast_quantity') {
        quantityExample ??= row;
      }
      if (row.rank == OnlineRank.c &&
          row.hasSalesForecast &&
          thresholds['premium_retail_aed'] != null &&
          row.retail >= stockNumber(thresholds['premium_retail_aed'])) {
        highPriceExample ??= row;
      }
    }
    if (quantityExample != null) examples[OnlineRank.a] = quantityExample;
    if (highPriceExample != null) examples[OnlineRank.c] = highPriceExample;
    showDialog<void>(
      context: context,
      builder: (context) => OnlineRankGuide(
        premiumRetail: thresholds['premium_retail_aed'],
        forecastMeta: stockMap(_snapshot?.serverMeta['forecast']),
        examples: examples,
      ),
    );
  }

  Widget _selector<T>({
    required String label,
    required T value,
    required List<(T, String)> choices,
    required ValueChanged<T?> changed,
    double width = 210,
    bool branches = false,
  }) => SizedBox(
    width: width,
    child: InventoryDropdown<T>(
      label: label,
      value: value,
      searchable: true,
      branchNames: branches,
      isExpanded: true,
      items: [
        for (final choice in choices)
          DropdownMenuItem(value: choice.$1, child: Text(choice.$2)),
      ],
      onChanged: changed,
    ),
  );

  @override
  Widget build(BuildContext context) => Theme(
    data: catalogControlTheme(context),
    child: ValueListenableBuilder<Map<String, String>>(
      valueListenable: StoreBranchIdentityRegistry.groups,
      builder: (context, _, _) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF0F5FE), Color(0xFFF5F2FA), Color(0xFFEEF8F7)],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, size) {
            final compact = size.maxWidth < 750;
            return Padding(
              padding: EdgeInsets.all(compact ? 10 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _banner(compact),
                  const SizedBox(height: 10),
                  if (!_loading && _error == null) ...[
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: (size.maxHeight * .4).clamp(145.0, 330.0),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            _metrics(size.maxWidth - (compact ? 20 : 32)),
                            const SizedBox(height: 8),
                            _filters(),
                          ],
                        ),
                      ),
                    ),
                    if (_checking || _refreshing)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                    if (_auditError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _auditError!,
                          style: const TextStyle(
                            color: catalogRose,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                  ],
                  Expanded(
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFDFE7F3)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x09192D4B),
                            blurRadius: 22,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: _loading
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 12),
                                  Text(
                                    _progress,
                                    style: const TextStyle(
                                      color: catalogMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : _error != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_error!, textAlign: TextAlign.center),
                                    const SizedBox(height: 12),
                                    FilledButton.icon(
                                      onPressed: _preparationFailed
                                          ? _prepare
                                          : _load,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : OnlineOverviewGrid(
                              source: _grid,
                              onFiltersChanged: _viewChanged,
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget _banner(bool compact) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF1A2C50), Color(0xFF30386D), Color(0xFF155F6B)],
      ),
      borderRadius: BorderRadius.circular(22),
      boxShadow: const [
        BoxShadow(
          color: Color(0x29192D4B),
          blurRadius: 22,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      children: [
        if (!compact)
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.shopping_bag_outlined,
              color: Color(0xFF82E4CF),
              size: 24,
            ),
          ),
        if (!compact) const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                compact &&
                        stockMap(_snapshot?.serverMeta['forecast'])['status'] ==
                            'ready'
                    ? '6-month forecast trial'
                    : 'Stock Management',
                style: const TextStyle(
                  color: Color(0xFFB6C9E6),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Online Overview',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.7,
                ),
              ),
            ],
          ),
        ),
        if (!compact) ...[
          OutlinedButton.icon(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.sync_rounded),
            label: const Text('Reload'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF7083A7)),
            ),
          ),
          const SizedBox(width: 10),
        ],
        if (compact)
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'Reload source data',
            icon: const Icon(Icons.sync_rounded, color: Colors.white),
          ),
        if (compact)
          IconButton(
            onPressed: _loading || _snapshot == null ? null : _availability,
            tooltip: 'Branch availability',
            icon: const Icon(Icons.bar_chart_rounded, color: Color(0xFF82E4CF)),
          )
        else ...[
          Tooltip(
            message: 'Branch availability',
            child: OutlinedButton.icon(
              onPressed: _loading || _snapshot == null ? null : _availability,
              icon: const Icon(Icons.bar_chart_rounded),
              label: const Text('Availability'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF82E4CF),
                side: const BorderSide(color: Color(0xFF7083A7)),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        IconButton(
          onPressed: _rules,
          tooltip: 'What the letters mean',
          icon: const Icon(
            Icons.help_outline_rounded,
            color: Color(0xFF82E4CF),
          ),
        ),
      ],
    ),
  );

  Widget _metrics(double width) {
    final rows = _grid.displayedRows;
    const gap = 8.0;
    const minimumWidth = 800.0;
    final cards = [
      _summaryCard(
        'Products shown',
        catalogQty(rows.length),
        catalogBlue,
        _clear,
      ),
      for (final rank in OnlineRank.values)
        _summaryCard(
          onlineRankTitle(rank),
          catalogQty(rows.where((row) => row.rank == rank).length),
          onlineRankColor(rank),
          () {
            _rank = _rank == rank.name ? '' : rank.name;
            _filter();
          },
          selected: _rank == rank.name,
        ),
      _summaryCard(
        'Estimated sales (AED)',
        catalogQty(
          rows.fold<double>(0, (sum, row) => sum + (row.estimatedValue ?? 0)),
        ),
        catalogTeal,
        null,
      ),
    ];
    Widget cardRow(Iterable<Widget> row) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, card) in row.indexed) ...[
            if (index > 0) const SizedBox(width: gap),
            Expanded(child: card),
          ],
        ],
      ),
    );

    final content = Column(
      children: [
        cardRow(cards.take(5)),
        const SizedBox(height: gap),
        cardRow(cards.skip(5)),
      ],
    );
    if (width >= minimumWidth) return content;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(width: minimumWidth, child: content),
    );
  }

  Widget _summaryCard(
    String title,
    String value,
    Color color,
    VoidCallback? onTap, {
    bool selected = false,
  }) => Material(
    color: Color.alphaBlend(
      color.withValues(alpha: selected ? .16 : .06),
      Colors.white,
    ),
    shape: RoundedRectangleBorder(
      side: BorderSide(color: color.withValues(alpha: selected ? .85 : .24)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(
                color: catalogInk,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _filters() => LayoutBuilder(
    builder: (context, size) {
      final snapshot = _snapshot!;
      final visible = _grid.displayedRows;
      final statuses = _ranked.map((row) => row.purchaseStatus).toSet().toList()
        ..sort();
      final compact = size.maxWidth < 620;
      final fieldWidth = compact ? size.maxWidth - 22 : 205.0;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: AppColors.primaryColor.withValues(alpha: .18),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryColor.withValues(alpha: .035),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: size.maxWidth >= 1320 ? 280 : size.maxWidth - 20,
                  height: 46,
                  child: TextField(
                    controller: _search,
                    cursorColor: AppColors.primaryColor,
                    decoration: InputDecoration(
                      hintText: 'Search products',
                      hintStyle: const TextStyle(fontSize: 15),
                      prefixIcon: const Icon(Icons.search_rounded, size: 21),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppColors.primaryColor.withValues(alpha: .18),
                        ),
                      ),
                    ),
                    onChanged: (_) {
                      _debounce?.cancel();
                      _debounce = Timer(
                        const Duration(milliseconds: 200),
                        _filter,
                      );
                    },
                  ),
                ),
                if (compact)
                  TextButton.icon(
                    onPressed: () => setState(
                      () => _showMobileFilters = !_showMobileFilters,
                    ),
                    icon: const Icon(Icons.tune, size: 18),
                    label: Text(
                      _showMobileFilters ? 'Hide filters' : 'Filters',
                    ),
                  ),
                if (!compact || _showMobileFilters) ...[
                  _selector(
                    label: 'Online branch',
                    value: _branch,
                    branches: true,
                    width: fieldWidth,
                    choices: [
                      ('', 'All online branches'),
                      for (final branch in snapshot.branches)
                        (branch.name, branch.name),
                    ],
                    changed: (value) {
                      _branch = value ?? '';
                      unawaited(_load());
                    },
                  ),
                  _selector(
                    label: 'Purchase Status',
                    value: _purchase,
                    width: fieldWidth,
                    choices: [
                      ('', 'All purchase statuses'),
                      for (final status in statuses)
                        (status, onlinePurchaseLabel(status)),
                    ],
                    changed: (value) {
                      _purchase = value ?? '';
                      _filter();
                    },
                  ),
                  SizedBox(
                    height: 46,
                    width: 46,
                    child: IconButton.filledTonal(
                      key: const ValueKey('online-clear-filters'),
                      onPressed: _clear,
                      tooltip: 'Clear filters',
                      style: IconButton.styleFrom(
                        foregroundColor: AppColors.primaryColor,
                        backgroundColor: AppColors.primaryColor.withValues(
                          alpha: .08,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 20),
                    ),
                  ),
                ],
                SizedBox(
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _refreshing ? null : _prepare,
                    icon: const Icon(Icons.cloud_sync_outlined, size: 18),
                    label: Text(
                      _refreshing
                          ? 'Updating…'
                          : compact
                          ? 'Update'
                          : 'Update data',
                    ),
                  ),
                ),
                SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: visible.isEmpty || _checking || _exporting
                        ? null
                        : _export,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      iconColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    icon: Icon(
                      _exporting
                          ? Icons.hourglass_top_rounded
                          : Icons.download_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _exporting
                          ? 'Exporting…'
                          : compact
                          ? 'Excel'
                          : 'Export Excel',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${visible.length} products · '
              'Stock as of ${catalogDate(snapshot.serverMeta['stock_day'])}.',
              style: const TextStyle(color: catalogMuted, fontSize: 14),
            ),
          ],
        ),
      );
    },
  );
}
