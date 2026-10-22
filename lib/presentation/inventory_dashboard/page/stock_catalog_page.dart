import '../../../core/utils/stock_excel_export.dart';
import '../../widgets/inventory_dropdown.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../domain/entities/stock_distribution.dart';
import '../widgets/stock_distribution_widgets.dart';
import '../../../core/utils/stock_catalog_export.dart';
import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../data/datasources/remote/stock_catalog_remote_ds.dart';
import '../../../data/datasources/remote/stock_product_image_service.dart';
import '../../../core/config/stock_product_image_config.dart';
import '../../../domain/entities/stock_catalog.dart';
import '../../../domain/entities/stock_management.dart';
import '../../../core/theme/app_colors.dart';
import '../widgets/stock_catalog_grid.dart';
import '../widgets/stock_catalog_visuals.dart';
import 'stock_catalog_product_dialog.dart';

class StockCatalogPage extends StatefulWidget {
  final StockCatalogDataSource? dataSource;
  final bool readOnly;
  const StockCatalogPage({super.key, this.dataSource, this.readOnly = false});
  @override
  State<StockCatalogPage> createState() => _StockCatalogPageState();
}

class _StockCatalogPageState extends State<StockCatalogPage> {
  late final StockCatalogDataSource _source;
  final _search = TextEditingController();
  final _gridKey = GlobalKey<StockCatalogGridState>();
  List<StockCatalogItem>? _columnRows;
  Timer? _debounce, _poll;
  StockCatalogResult? _result, _complete;
  String _signal = '', _category = '', _supplier = '', _sort = 'item_status';
  // Empty selects all; the prefix keeps an unspecified status selectable.
  String _itemStatus = '';
  int _request = 0, _loaded = 0, _loadTotal = 0;
  bool _loading = true, _refreshing = false, _exporting = false;
  String? _error, _refreshError;
  StockDistributionRules _distributionRules = const StockDistributionRules();
  @override
  void initState() {
    super.initState();
    _source =
        widget.dataSource ?? StockCatalogRemoteDs(Supabase.instance.client);
    if (widget.dataSource == null) {
      unawaited(StoreBranchIdentityRegistry.load(Supabase.instance.client));
    }
    _load();
    if (widget.dataSource == null) unawaited(_restoreDistributionRules());
    _resumeRefresh();
  }

  Future<void> _restoreDistributionRules() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _distributionRules = StockDistributionRules(
      maxAgeDays: (prefs.getInt('stock_distribution_age') ?? 30).clamp(1, 365),
      minStoreStock: (prefs.getDouble('stock_distribution_store') ?? 50).clamp(
        1,
        1000000000,
      ),
      maxCoveredBranches: (prefs.getInt('stock_distribution_branches') ?? 6)
          .clamp(0, 1000),
    );
    _applyFilters();
  }

  Future<void> _editDistributionRules() async {
    final rules = await showStockDistributionRules(context, _distributionRules);
    if (!mounted || rules == null) return;
    _distributionRules = rules;
    _applyFilters();
    if (widget.dataSource == null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('stock_distribution_age', rules.maxAgeDays);
      await prefs.setDouble('stock_distribution_store', rules.minStoreStock);
      await prefs.setInt(
        'stock_distribution_branches',
        rules.maxCoveredBranches,
      );
    }
  }

  @override
  void dispose() {
    _request++;
    _search.dispose();
    _debounce?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _loaded = 0;
      _loadTotal = 0;
      _error = null;
    });
    try {
      final result = await _source.fetchAll(
        isCancelled: () => !mounted || request != _request,
        onProgress: (loaded, total) {
          if (mounted && request == _request) {
            setState(() {
              _loaded = loaded;
              _loadTotal = total;
            });
          }
        },
      );
      if (!mounted || request != _request) return;
      setState(() {
        _complete = result;
        _loading = false;
      });
      _applyFilters();
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _error = 'Unable to load Overview. $e';
          _loading = false;
        });
      }
    }
  }

  void _applyFilters() {
    final complete = _complete;
    if (complete == null) return;
    final search = _search.text.trim().toLowerCase();
    final rows = complete.rows
        .map((item) => item.withDistributionRules(_distributionRules))
        .where((item) {
          if (search.isNotEmpty &&
              !'${item.code} ${item.name} ${item.text('supplier')} ${item.text('company')}'
                  .toLowerCase()
                  .contains(search)) {
            return false;
          }
          if (_category.isNotEmpty && item.text('category') != _category) {
            return false;
          }
          if (_supplier.isNotEmpty && item.text('supplier') != _supplier) {
            return false;
          }
          if (_itemStatus.isNotEmpty &&
              'status:${item.itemStatus}' != _itemStatus) {
            return false;
          }
          return switch (_signal) {
            'distribution' => item.distributionStatus.needsDistribution,
            'surge' => item.surge || item.newDemand,
            'shortage' => item.salesExceedStock,
            'low_cover' => item.status == 'low_cover',
            'no_stock' => item.number('total_stock') <= 0,
            'no_sales' => item.status == 'no_sales',
            _ => true,
          };
        })
        .toList();
    rows.sort((a, b) {
      final order = switch (_sort) {
        'growth' =>
          a.growth == null
              ? (b.growth == null ? 0 : 1)
              : b.growth == null
              ? -1
              : b.growth!.compareTo(a.growth!),
        'cover' => (a.days ?? double.infinity).compareTo(
          b.days ?? double.infinity,
        ),
        'stock' => b.number('total_stock').compareTo(a.number('total_stock')),
        'sales' => stockNumber(
          b.year(2026)['total'],
        ).compareTo(stockNumber(a.year(2026)['total'])),
        'distribution' =>
          (a.distributionStatus.needsDistribution ? 0 : 1).compareTo(
            b.distributionStatus.needsDistribution ? 0 : 1,
          ),
        'item_status' || 'item_status_desc' =>
          a.itemStatus.isEmpty
              ? (b.itemStatus.isEmpty ? 0 : 1)
              : b.itemStatus.isEmpty
              ? -1
              : (_sort == 'item_status_desc' ? -1 : 1) *
                    a.itemStatus.toLowerCase().compareTo(
                      b.itemStatus.toLowerCase(),
                    ),
        _ => 0,
      };
      if (order != 0) return order;
      final name = a.name.compareTo(b.name);
      return name == 0 ? a.code.compareTo(b.code) : name;
    });
    setState(() {
      _columnRows = null;
      _result = StockCatalogResult(
        rows: rows,
        summary: {
          'items': rows.length,
          'surge': rows.where((r) => r.surge || r.newDemand).length,
          'shortage': rows.where((r) => r.salesExceedStock).length,
          'low_cover': rows.where((r) => r.status == 'low_cover').length,
          'distribution': rows
              .where((r) => r.distributionStatus.needsDistribution)
              .length,
        },
        meta: complete.meta,
        categories: complete.categories,
        suppliers: complete.suppliers,
      );
    });
  }

  Future<void> _resumeRefresh() async {
    try {
      final state = await _source.refreshState();
      if (!mounted) return;
      if (state?['status'] == 'queued') {
        setState(() => _refreshing = true);
        _startPolling();
      } else if (state?['status'] == 'failed') {
        setState(
          () => _refreshError =
              'Last rebuild failed. Previous snapshot remains available. ${state?['error'] ?? ''}',
        );
      }
    } catch (_) {
      /* List loading reports any connectivity error. */
    }
  }

  Future<void> _refresh() async {
    if (widget.readOnly) return;
    setState(() {
      _refreshing = true;
      _refreshError = null;
    });
    try {
      await _source.requestRefresh();
      if (mounted) _startPolling();
    } catch (e) {
      if (mounted) {
        setState(() {
          _refreshing = false;
          _refreshError = 'Could not rebuild data. $e';
        });
      }
    }
  }

  void _startPolling() {
    _poll?.cancel();
    var checking = false;
    _poll = Timer.periodic(const Duration(seconds: 4), (timer) async {
      if (checking) return;
      checking = true;
      try {
        final state = await _source.refreshState();
        if (!mounted) return;
        if (state?['status'] == 'complete') {
          timer.cancel();
          setState(() => _refreshing = false);
          await _load();
        } else if (state?['status'] == 'failed') {
          timer.cancel();
          setState(() {
            _refreshing = false;
            _refreshError =
                'Rebuild failed; previous data preserved. ${state?['error'] ?? ''}';
          });
        }
      } catch (e) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _refreshing = false;
            _refreshError =
                'Refresh monitoring lost connection. Reload to resume. $e';
          });
        }
      } finally {
        checking = false;
      }
    });
  }

  Future<void> _export() async {
    _debounce?.cancel();
    _applyFilters();
    // Let toolbar changes reach the persistent grid source before exporting.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final result = _result;
    if (result == null) return;
    setState(() => _exporting = true);
    try {
      final rows = [
        for (final item in _gridKey.currentState?.visibleItems ?? result.rows)
          {
            ...catalogExportRow(item),
            'Sales through': result.meta['demand_through'],
            'Recent calendar days': result.meta['recent_days'],
            'Baseline calendar days': result.meta['baseline_days'],
          },
      ];
      if (rows.isEmpty) throw StateError('No matching products to export.');
      await saveStockExcel(rows, 'stock_overview.xlsx');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported ${rows.length} matching products')),
        );
      }
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

  void _selectSignal(String value) {
    setState(() => _signal = _signal == value ? '' : value);
    _debounce?.cancel();
    _applyFilters();
  }

  @override
  Widget build(BuildContext context) =>
      Theme(data: catalogControlTheme(context), child: _workspace(context));

  Widget _workspace(BuildContext context) => Container(
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
              Expanded(
                child: Column(
                  children: [
                    // The top workspace scrolls on narrow screens without constraining the table.
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: compact ? 180 : 220,
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
                    if (_refreshing)
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                    if (_refreshError != null)
                      _errorStrip(_refreshError!, () => _resumeRefresh()),
                    const SizedBox(height: 10),
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
                        child: _error != null
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Text(
                                        _error!,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    FilledButton.icon(
                                      onPressed: () => _load(),
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              )
                            : _loading
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(),
                                    if (_loadTotal > 0)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Text(
                                          'Loading ${catalogQty(_loaded)} / ${catalogQty(_loadTotal)} products',
                                          style: const TextStyle(
                                            color: catalogMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              )
                            : _complete?.rows.isEmpty ?? true
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    _result?.total == 0 &&
                                            _search.text.isEmpty &&
                                            _signal.isEmpty &&
                                            _category.isEmpty &&
                                            _itemStatus.isEmpty &&
                                            _supplier.isEmpty
                                        ? 'No catalog snapshot yet. Rebuild data to load Item Report products.'
                                        : 'No products match these filters.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: catalogMuted),
                                  ),
                                ),
                              )
                            : StockCatalogGrid(
                                key: _gridKey,
                                items: _result!.rows,
                                onViewChanged: (rows, filtered) {
                                  setState(
                                    () => _columnRows = filtered ? rows : null,
                                  );
                                },
                                onOpen: (item) => showDialog<void>(
                                  context: context,
                                  builder: (_) => StockCatalogProductDialog(
                                    item: item,
                                    source: _source,
                                    resolveImage:
                                        StockProductImageConfig.enabled &&
                                            _source is StockCatalogRemoteDs
                                        ? StockProductImageService.forClient(
                                            _source.client,
                                          ).resolve
                                        : null,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.insights_rounded,
            color: Color(0xFF82E4CF),
            size: 24,
          ),
        ),
        const SizedBox(width: 16),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'STOCK MANAGEMENT / ITEM REPORT',
                style: TextStyle(
                  color: Color(0xFFB6C9E6),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Overview',
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
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.sync_rounded),
            label: const Text('Reload'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF7083A7)),
            ),
          ),
          const SizedBox(width: 10),
        ],
        IconButton(
          onPressed: _editDistributionRules,
          tooltip: 'Distribution rules',
          icon: const Icon(
            Icons.rule_folder_outlined,
            color: Color(0xFF82E4CF),
          ),
        ),
        if (!widget.readOnly)
          Tooltip(
            message:
                'Rebuild Item Report stock and sales snapshot in the background',
            child: IconButton.filledTonal(
              onPressed: _refreshing ? null : _refresh,
              icon: const Icon(Icons.cloud_sync_outlined),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: catalogInk,
              ),
            ),
          ),
      ],
    ),
  );
  Widget _metrics(double width) {
    final count = width < 600
        ? 2
        : width < 1100
        ? 3
        : 5;
    final w = (width - (count - 1) * 12) / count;
    final columnRows = _columnRows;
    final summary = columnRows == null
        ? _result?.summary ?? {}
        : {
            'items': columnRows.length,
            'surge': columnRows.where((r) => r.surge || r.newDemand).length,
            'shortage': columnRows.where((r) => r.salesExceedStock).length,
            'low_cover': columnRows
                .where((r) => r.status == 'low_cover')
                .length,
            'distribution': columnRows
                .where((r) => r.distributionStatus.needsDistribution)
                .length,
          };
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final spec in [
          (
            'distribution',
            'NEEDS DISTRIBUTION',
            'New ≤${_distributionRules.maxAgeDays} days · STORE ≥${catalogQty(_distributionRules.minStoreStock)} · ≤${_distributionRules.maxCoveredBranches} branches',
            catalogOrange,
            Icons.local_shipping_outlined,
            'distribution',
          ),
          (
            'items',
            _search.text.isNotEmpty ||
                    columnRows != null ||
                    _signal.isNotEmpty ||
                    _category.isNotEmpty ||
                    _itemStatus.isNotEmpty ||
                    _supplier.isNotEmpty
                ? 'MATCHING PRODUCTS'
                : 'ALL PRODUCTS',
            'Item Report catalog',
            catalogBlue,
            Icons.inventory_2_outlined,
            '',
          ),
          (
            'surge',
            'SALES INCREASE',
            '≥2× daily sales or new demand',
            catalogPurple,
            Icons.bolt_rounded,
            'surge',
          ),
          (
            'shortage',
            'SALES > STOCK',
            '45-day demand exceeds supply',
            catalogRose,
            Icons.warning_amber_rounded,
            'shortage',
          ),
          (
            'low_cover',
            'LOW COVER',
            'Less than 30 days available',
            catalogOrange,
            Icons.hourglass_bottom_rounded,
            'low_cover',
          ),
        ])
          SizedBox(
            width: w,
            child: CatalogMetric(
              dense: true,
              title: spec.$2,
              value: _result == null ? '—' : catalogQty(summary[spec.$1]),
              caption: spec.$3,
              color: spec.$4,
              icon: spec.$5,
              selected: _signal == spec.$6 && spec.$6.isNotEmpty,
              onTap: () => spec.$6.isEmpty ? _clear() : _selectSignal(spec.$6),
            ),
          ),
      ],
    );
  }

  void _clear() {
    _debounce?.cancel();
    _gridKey.currentState?.clearFilters();
    _gridKey.currentState?.clearSorting();
    setState(() {
      _search.clear();
      _signal = '';
      _category = '';
      _supplier = '';
      _itemStatus = '';
      _sort = 'item_status';
    });
    _applyFilters();
  }

  Widget _filters() => LayoutBuilder(
    builder: (context, size) {
      final inline = size.maxWidth >= 1320;
      final fieldWidth = size.maxWidth < 500 ? (size.maxWidth - 28) / 2 : 155.0;
      final statuses =
          (_complete?.rows ?? <StockCatalogItem>[])
              .map((item) => item.itemStatus)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      final controls = [
        _dropdown(
          'Status',
          _signal,
          const {
            '': 'All statuses',
            'distribution': 'New · Needs distribution',
            'surge': 'Sales increase',
            'shortage': 'Sales > stock',
            'low_cover': 'Low cover',
            'no_stock': 'No stock',
            'no_sales': 'No recent sales',
          },
          (v) {
            _signal = v;
            _applyFilters();
          },
          icon: Icons.tune_rounded,
          width: fieldWidth,
        ),
        _dropdown(
          'Item Status',
          _itemStatus,
          {
            '': 'All statuses',
            for (final status in statuses.where((s) => s.isNotEmpty))
              'status:$status': status,
            if (statuses.contains('')) 'status:': 'Not specified',
          },
          (v) {
            _itemStatus = v;
            _applyFilters();
          },
          icon: Icons.sell_outlined,
          width: fieldWidth,
        ),
        _dropdown(
          'Category',
          _category,
          {
            '': 'All categories',
            for (final c in _result?.categories ?? <String>[]) c: c,
          },
          (v) {
            _category = v;
            _applyFilters();
          },
          icon: Icons.category_outlined,
          width: fieldWidth,
        ),
        _dropdown(
          'Supplier',
          _supplier,
          {
            '': 'All suppliers',
            for (final c in _result?.suppliers ?? <String>[]) c: c,
          },
          (v) {
            _supplier = v;
            _applyFilters();
          },
          icon: Icons.local_shipping_outlined,
          width: fieldWidth,
        ),
        _dropdown(
          'Sort',
          _sort,
          const {
            'name': 'Product name',
            'distribution': 'Needs distribution first',
            'item_status': 'Item status A–Z',
            'item_status_desc': 'Item status Z–A',
            'growth': 'Highest growth',
            'cover': 'Lowest cover',
            'stock': 'Highest stock',
            'sales': 'Highest sales 2026',
          },
          (v) {
            _sort = v;
            _gridKey.currentState?.clearSorting();
            _applyFilters();
          },
          icon: Icons.sort_rounded,
          width: fieldWidth,
        ),
        SizedBox(
          height: 46,
          width: 42,
          child: IconButton.filledTonal(
            onPressed: _clear,
            tooltip: 'Clear filters',
            style: IconButton.styleFrom(
              foregroundColor: AppColors.primaryColor,
              backgroundColor: AppColors.primaryColor.withValues(alpha: .09),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.restart_alt_rounded, size: 21),
          ),
        ),
        SizedBox(
          height: 46,
          child: Tooltip(
            message: 'Export all matching products',
            child: FilledButton.icon(
              onPressed: _exporting || _loading ? null : _export,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                iconColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              icon: Icon(
                _exporting
                    ? Icons.hourglass_top_rounded
                    : Icons.download_rounded,
                size: 18,
              ),
              label: Text(_exporting ? 'Exporting…' : 'Export Excel'),
            ),
          ),
        ),
      ];
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
        child: inline
            ? Row(
                children: [
                  Expanded(child: _searchField()),
                  for (final control in controls) ...[
                    const SizedBox(width: 8),
                    control,
                  ],
                ],
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(width: size.maxWidth - 20, child: _searchField()),
                  ...controls,
                ],
              ),
      );
    },
  );

  Widget _searchField() => SizedBox(
    height: 46,
    child: TextField(
      controller: _search,
      cursorColor: AppColors.primaryColor,
      style: const TextStyle(color: AppColors.secondaryColor, fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Search product, code or supplier',
        hintStyle: const TextStyle(color: catalogMuted, fontSize: 13),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.primaryColor,
          size: 21,
        ),
        filled: true,
        fillColor: AppColors.primaryColor.withValues(alpha: .055),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: AppColors.primaryColor.withValues(alpha: .14),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.primaryColor,
            width: 1.5,
          ),
        ),
      ),
      onChanged: (_) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 320), _applyFilters);
      },
      onSubmitted: (_) {
        _debounce?.cancel();
        _applyFilters();
      },
    ),
  );
  Widget _dropdown(
    String label,
    String value,
    Map<String, String> entries,
    ValueChanged<String> change, {
    required IconData icon,
    required double width,
  }) {
    return SizedBox(
      width: width,
      height: 46,
      child: InventoryDropdown<String>(
        searchable: true,
        value: value,
        label: label,
        icon: Icon(icon),
        isExpanded: true,
        items: [
          for (final entry in entries.entries)
            DropdownMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        onChanged: _loading
            ? null
            : (v) {
                if (v != null) {
                  _debounce?.cancel();
                  change(v);
                }
              },
      ),
    );
  }

  Widget _errorStrip(String error, VoidCallback retry) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: catalogRose, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            error,
            maxLines: 2,
            style: const TextStyle(color: catalogRose, fontSize: 11),
          ),
        ),
        TextButton(onPressed: retry, child: const Text('Check again')),
      ],
    ),
  );
}
