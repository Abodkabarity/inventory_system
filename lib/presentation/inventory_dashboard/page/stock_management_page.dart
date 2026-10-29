import '../../widgets/inventory_dropdown.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/stock_register_export.dart';
import '../../../core/utils/stock_excel_export.dart';
import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../data/datasources/remote/stock_management_remote_ds.dart';
import '../../../data/datasources/remote/stock_catalog_remote_ds.dart';
import '../../../domain/entities/stock_catalog.dart';
import 'stock_catalog_product_dialog.dart';
import '../../../data/datasources/remote/stock_expiry_remote_ds.dart';
import '../../../domain/entities/stock_expiry.dart';
import '../../../domain/entities/stock_management.dart';
import '../../widgets/app_date_range_picker_dialog.dart';
import '../widgets/stock_management_formatters.dart';
import '../widgets/stock_management_grid.dart';
import '../widgets/stock_mrn_receipts.dart';
import '../widgets/stock_sales_summary.dart';
import '../widgets/stock_catalog_visuals.dart';
import '../widgets/stock_workspace_style.dart';
import '../widgets/stock_mrn_update_card.dart';
import 'stock_expiry_page.dart';

const _ink = Color(0xFF142C40);
const _muted = Color(0xFF64748B);
const _teal = Color(0xFF008A83);
const _blue = Color(0xFF4169D8);
const _amber = Color(0xFFB76C06);
const _red = Color(0xFFC63E55);
const _line = Color(0xFFE5EBF2);
final _quantity = NumberFormat('#,##0.##');
String _qty(dynamic value) => _quantity.format(stockNumber(value));
String _date(String? value) {
  final date = DateTime.tryParse(value ?? '');
  return date == null ? '—' : DateFormat('dd MMM yyyy').format(date);
}

String _month(dynamic value) {
  final parts = (value?.toString() ?? '').split('/');
  if (parts.length != 2) return 'No sales';
  return DateFormat(
    'MMM yyyy',
  ).format(DateTime(int.parse(parts[1]), int.parse(parts[0])));
}

String _statusLabel(String status) => switch (status) {
  'no_stock' => 'No Stock',
  'no_sales' => 'No recent sales',
  'low_cover' => 'Below 30 days',
  _ => 'In stock',
};
Color _statusColor(String status) => switch (status) {
  'no_stock' => _red,
  'no_sales' => _muted,
  'low_cover' => _amber,
  _ => _teal,
};

Future<void> showStockManagementProductDetails(
  BuildContext context,
  StockManagementItem item, {
  StockManagementDataSource? dataSource,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => StockManagementProductDialog(
      item: item,
      source: dataSource is StockManagementRemoteDs
          ? dataSource.forReceipt(item)
          : dataSource ?? StockManagementRemoteDs(Supabase.instance.client),
    ),
  );
}

class StockManagementPage extends StatefulWidget {
  final bool cd;
  final StockManagementDataSource? dataSource;
  final StockExpiryDataSource? expiryDataSource;
  final VoidCallback? onOpenExpiry;
  final StockRegisterExporter? exporter;
  const StockManagementPage({
    super.key,
    this.cd = false,
    this.dataSource,
    this.expiryDataSource,
    this.onOpenExpiry,
    this.exporter,
  });
  @override
  State<StockManagementPage> createState() => _StockManagementPageState();
}

class _StockManagementPageState extends State<StockManagementPage> {
  late final StockManagementDataSource _source;
  StockExpiryDataSource? _expirySource;
  Map<String, dynamic>? _expirySummary;
  String? _expiryError;
  bool _expiryLoading = true;
  int _expiryRequest = 0;
  final _search = TextEditingController();
  final _horizontal = ScrollController();
  final _gridKey = GlobalKey<StockManagementGridState>();
  Timer? _debounce, _poll, _autoRefreshCheck;
  DateTime? _lastCompletedRefresh;
  bool _checkingAutoRefresh = false;
  StockManagementResult? _result;
  List<StockManagementItem> _filtered = const [];
  String _status = '', _category = '', _supplier = '', _sort = 'latest_mrn';
  DateTimeRange? _received;
  int _request = 0, _polls = 0, _loaded = 0, _loadTotal = 0;
  int _gridVisible = 0;
  bool _gridFiltered = false;
  bool _loading = true, _refreshing = false, _focusView = false;
  bool _exporting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _source =
        widget.dataSource ??
        StockManagementRemoteDs(Supabase.instance.client, cd: widget.cd);
    if (widget.cd) {
      StoreBranchIdentityRegistry.groups.addListener(_branchLabelsChanged);
      if (_source is StockManagementRemoteDs) {
        StoreBranchIdentityRegistry.load(
          _source.client,
        );
      }
    }
    _expirySource =
        (widget.cd ? null : widget.expiryDataSource) ??
        (widget.dataSource == null && !widget.cd
            ? StockExpiryRemoteDs(Supabase.instance.client)
            : null);
    _load();
    _resumeRefresh();
    _autoRefreshCheck = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkForAutomaticRefresh(),
    );
    _loadExpirySummary();
  }

  @override
  void dispose() {
    if (widget.cd) {
      StoreBranchIdentityRegistry.groups.removeListener(_branchLabelsChanged);
    }
    _request++;
    _debounce?.cancel();
    _poll?.cancel();
    _autoRefreshCheck?.cancel();
    _search.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  void _applyFilters() {
    final result = _result;
    if (result == null) return;
    final search = _search.text.trim().toLowerCase();
    final rows = result.rows.where((item) {
      if (search.isNotEmpty &&
          !'${item.code} ${item.name} ${item.text('supplier')} ${item.text('company')} ${widget.cd ? StoreBranchIdentityRegistry.displayName(item.warehouse) : ''}'
              .toLowerCase()
              .contains(search)) {
        return false;
      }
      if (_status.isNotEmpty && item.status != _status) {
        return false;
      }
      if (_category.isNotEmpty && item.text('category') != _category) {
        return false;
      }
      if (_supplier.isNotEmpty && item.text('supplier') != _supplier) {
        return false;
      }
      if (_received != null) {
        final date = DateTime.tryParse(item.text('last_mrn_date'));
        if (date == null ||
            date.isBefore(_received!.start) ||
            date.isAfter(_received!.end)) {
          return false;
        }
      }
      return true;
    }).toList();
    switch (_sort) {
      case 'days_low':
        rows.sort(
          (a, b) =>
              (a.days ?? double.infinity).compareTo(b.days ?? double.infinity),
        );
      case 'stock_high':
        rows.sort(
          (a, b) => b.number('total_stock').compareTo(a.number('total_stock')),
        );
      case 'sales_high':
        rows.sort(
          (a, b) => stockNumber(
            b.year(2026)['total'],
          ).compareTo(stockNumber(a.year(2026)['total'])),
        );
      default:
        rows.sort((a, b) {
          final dates = b
              .text('last_mrn_date')
              .compareTo(a.text('last_mrn_date'));
          return dates != 0 ? dates : a.code.compareTo(b.code);
        });
    }
    setState(() {
      _filtered = rows;
      _gridVisible = rows.length;
      _gridFiltered = false;
    });
  }

  void _branchLabelsChanged() {
    if (mounted) _applyFilters();
  }

  Future<void> _export() async {
    if (_exporting || _loading || _result == null) return;
    setState(() => _exporting = true);
    try {
      _debounce?.cancel();
      _applyFilters();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final rows = [
        for (final item in _gridKey.currentState?.visibleItems ?? _filtered)
          stockRegisterExportRow(item),
      ];
      if (rows.isEmpty) throw StateError('No matching products to export.');
      await (widget.exporter ?? saveStockExcel)(
        rows,
        widget.cd ? 'mrn_cd_overview.xlsx' : 'mrn_overview.xlsx',
      );
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
        _result = result;
        _loading = false;
      });
      _applyFilters();
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _error = 'Could not load stock data. $error';
        _loading = false;
      });
    }
  }

  Future<void> _resumeRefresh() async {
    try {
      final state = await _source.refreshState();
      if (!mounted) return;
      if (state?['status'] == 'queued') {
        setState(() => _refreshing = true);
        _startPolling();
      } else if (state?['status'] == 'complete') {
        _lastCompletedRefresh = DateTime.tryParse(
          state?['completed_at']?.toString() ?? '',
        );
      }
    } catch (_) {
      /* Reading the list remains available if state lookup fails. */
    }
  }

  Future<void> _checkForAutomaticRefresh() async {
    if (_checkingAutoRefresh || _loading || _refreshing) return;
    _checkingAutoRefresh = true;
    try {
      final state = await _source.refreshState();
      if (!mounted) return;
      if (state?['status'] == 'queued') {
        setState(() => _refreshing = true);
        _startPolling();
        return;
      }
      if (state?['status'] != 'complete') return;
      final completedAt = DateTime.tryParse(
        state?['completed_at']?.toString() ?? '',
      );
      if (completedAt == null ||
          (_lastCompletedRefresh != null &&
              !completedAt.isAfter(_lastCompletedRefresh!))) {
        return;
      }
      await _load();
      if (_error == null) {
        _lastCompletedRefresh = completedAt;
        if (mounted) _loadExpirySummary();
      }
    } catch (_) {
      /* Keep the current snapshot if the background status is unavailable. */
    } finally {
      _checkingAutoRefresh = false;
    }
  }

  Future<void> _loadExpirySummary() async {
    if (_expirySource == null) return;
    final request = ++_expiryRequest;
    setState(() {
      _expiryLoading = true;
      _expiryError = null;
    });
    try {
      final data = await _expirySource!.fetchPage(
        const StockExpiryQuery(limit: 1),
      );
      if (mounted && request == _expiryRequest) {
        setState(() {
          _expirySummary = data.summary;
          _expiryLoading = false;
        });
      }
    } catch (_) {
      if (mounted && request == _expiryRequest) {
        setState(() {
          _expiryError = 'Could not check alerts';
          _expiryLoading = false;
        });
      }
    }
  }

  Future<void> _openExpiry() async {
    if (widget.onOpenExpiry != null) {
      widget.onOpenExpiry!();
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => StockExpiryPage(
          dataSource: _expirySource!,
          productDataSource: _source,
          onOpenProduct: _details,
        ),
      ),
    );
    if (mounted) _loadExpirySummary();
  }

  void _startPolling() {
    _poll?.cancel();
    _polls = 0;
    _poll = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final state = await _source.refreshState();
        if (!mounted) return;
        if (state?['status'] == 'complete') {
          _poll?.cancel();
          setState(() => _refreshing = false);
          await _load();
          if (_error == null) {
            _lastCompletedRefresh = DateTime.tryParse(
              state?['completed_at']?.toString() ?? '',
            );
          }
          if (mounted) _loadExpirySummary();
        } else if (state?['status'] == 'failed' || ++_polls >= 65) {
          _poll?.cancel();
          setState(() {
            _refreshing = false;
            _error = state?['status'] == 'failed'
                ? 'Refresh failed: ${state?['error']}. The previous snapshot is still available.'
                : 'Refresh is taking longer than expected. Reopen this page to check its status.';
          });
        }
      } catch (error) {
        _poll?.cancel();
        if (mounted) {
          setState(() {
            _refreshing = false;
            _error = 'Could not check refresh status. $error';
          });
        }
      }
    });
  }

  Future<void> _chooseDates() async {
    final range = await showDialog<DateTimeRange>(
      context: context,
      builder: (_) => AppDateRangePickerDialog(
        firstDate: DateTime(2026),
        lastDate: DateTime.now().add(const Duration(days: 1)),
        initialRange: _received,
      ),
    );
    if (range != null && mounted) {
      setState(() => _received = range);
      _applyFilters();
    }
  }

  void _details(StockManagementItem item) {
    showStockManagementProductDetails(context, item, dataSource: _source);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return DecoratedBox(
      decoration: StockWorkspaceStyle.background,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, size) {
            final compact = size.maxWidth < 850;
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 12 : 16,
                vertical: 10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: size.maxHeight * (compact ? .38 : .32),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!_focusView) ...[
                            _header(
                              size.maxWidth < 1150,
                              inlineStats: size.maxWidth >= 1150,
                            ),
                            if (size.maxWidth < 1150) ...[
                              const SizedBox(height: 8),
                              _stats(compact),
                            ],
                            const SizedBox(height: 8),
                          ],
                          if (!widget.cd)
                            StockMrnUpdateCard(
                              enabled:
                                  widget.dataSource == null ||
                                  widget.dataSource is StockManagementRemoteDs,
                              onUpdated: () {
                                if (!_loading) _load();
                                _loadExpirySummary();
                              },
                            ),
                          _filters(result, compact),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: _notice(
                                _error!,
                                _red,
                                action: TextButton(
                                  onPressed: _loading ? null : _load,
                                  child: const Text('Retry'),
                                ),
                              ),
                            ),
                          if (_refreshing)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: _notice(
                                'Refreshing source data in the background. This usually takes up to 90 seconds.',
                                _blue,
                                action: const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 3,
                    child: _loading
                        ? LinearProgressIndicator(
                            color: _teal,
                            backgroundColor: _line,
                            value: _loadTotal > 0 ? _loaded / _loadTotal : null,
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: StockWorkspaceRegisterFrame(
                      child: Column(
                        children: [
                          _registerHeader(compact),
                          Expanded(child: _table(result)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  _footer(result, compact),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _header(bool compact, {bool inlineStats = false}) =>
      StockWorkspaceBanner(
        compact: compact,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF35B7AB), Color(0xFF087D80)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                color: Colors.white,
                size: 23,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: inlineStats ? 3 : 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.cd ? 'MRN CD Overview' : 'MRN Overview',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 23 : 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.cd
                        ? 'Stock Management / MRN CD Overview'
                        : 'Stock Management / MRN Overview',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFFBFDBD7),
                      fontSize: 12,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            if (inlineStats) ...[
              const SizedBox(width: 14),
              Expanded(flex: 7, child: _stats(false)),
              const SizedBox(width: 14),
            ],
          ],
        ),
      );

  Widget _stats(bool compact) {
    final result = _result;
    final cards = [
      (
        widget.cd ? 'MRN CD entries' : 'MRN products',
        result?.total.toDouble(),
        _teal,
        Icons.layers_outlined,
        '',
        widget.cd
            ? 'One entry per receiving warehouse and product'
            : 'All products received in 2026',
      ),
      (
        'No Stock',
        result == null ? null : stockNumber(result.summary['no_stock']),
        _red,
        Icons.inventory_2_outlined,
        'no_stock',
        'Products without available stock',
      ),
      (
        'Below 30 days',
        result == null ? null : stockNumber(result.summary['low_cover']),
        _amber,
        Icons.hourglass_bottom_rounded,
        'low_cover',
        'Products with less than 30 days of stock',
      ),
      (
        'No recent sales',
        result == null ? null : stockNumber(result.summary['no_sales']),
        _blue,
        Icons.pause_circle_outline,
        'no_sales',
        'No sales in the recent demand window',
      ),
    ];
    return LayoutBuilder(
      builder: (_, constraints) {
        final columns = compact ? 2 : 4;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map(
                (card) => SizedBox(
                  width: width,
                  child: StockWorkspaceMetricCard(
                    label: card.$1,
                    value: card.$2,
                    color: card.$3,
                    icon: card.$4,
                    selected: _status == card.$5,
                    stackValue: true,
                    caption: card.$6,
                    onTap: () {
                      setState(() => _status = card.$5);
                      _applyFilters();
                    },
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _filters(
    StockManagementResult? result,
    bool compact,
  ) => StockWorkspaceFilterSurface(
    child: Padding(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(
        builder: (context, size) {
          final hasFilters =
              _received != null ||
              _search.text.isNotEmpty ||
              _status.isNotEmpty ||
              _category.isNotEmpty ||
              _supplier.isNotEmpty ||
              _gridFiltered;
          final search = SizedBox(
            height: 46,
            child: TextField(
              key: const ValueKey('mrn-search'),
              controller: _search,
              decoration: _input('Search product, code, supplier or company…')
                  .copyWith(
                    fillColor: const Color(0xFFF5FAFE),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 21,
                      color: AppColors.primaryColor,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppColors.primaryColor.withValues(alpha: .18),
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
                _debounce = Timer(
                  const Duration(milliseconds: 200),
                  _applyFilters,
                );
              },
            ),
          );
          final controls = <SizedBox>[
            _dropdown('Stock status', _status, const {
              '': 'All stock',
              'no_stock': 'No Stock',
              'low_cover': 'Below 30 days',
              'in_stock': 'In stock',
              'no_sales': 'No recent sales',
            }, (v) => _status = v),
            _dropdown('Category', _category, {
              '': 'All categories',
              for (final c in result?.categories ?? <String>[]) c: c,
            }, (v) => _category = v),
            _dropdown('Supplier', _supplier, {
              '': 'All suppliers',
              for (final s in result?.suppliers ?? <String>[]) s: s,
            }, (v) => _supplier = v),
            _dropdown('Sort', _sort, const {
              'latest_mrn': 'Latest receipt',
              'days_low': 'Lowest coverage',
              'stock_high': 'Highest stock',
              'sales_high': 'Highest 2026 sales',
            }, (v) => _sort = v),
            SizedBox(
              key: const ValueKey('mrn-date-filter'),
              width: 168,
              height: 46,
              child: OutlinedButton.icon(
                onPressed: _chooseDates,
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor.withValues(
                    alpha: .08,
                  ),
                  foregroundColor: AppColors.primaryColor,
                  side: BorderSide(
                    color: AppColors.primaryColor.withValues(alpha: .2),
                  ),
                  iconColor: AppColors.primaryColor,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.date_range_rounded, size: 18),
                label: Text(
                  _received == null
                      ? 'MRN Date Range'
                      : '${DateFormat('dd MMM').format(_received!.start)} – ${DateFormat('dd MMM').format(_received!.end)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            SizedBox(
              width: 46,
              height: 46,
              child: IconButton.filledTonal(
                key: const ValueKey('mrn-clear-filters'),
                tooltip: 'Clear filters',
                onPressed: hasFilters
                    ? () {
                        _search.clear();
                        _debounce?.cancel();
                        _gridKey.currentState?.clearFilters();
                        setState(() {
                          _status = '';
                          _category = '';
                          _supplier = '';
                          _received = null;
                        });
                        _applyFilters();
                      }
                    : null,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primaryColor.withValues(
                    alpha: .08,
                  ),
                  foregroundColor: AppColors.primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.filter_alt_off_outlined, size: 20),
              ),
            ),
          ];
          final export = SizedBox(
            width: 160,
            child: StockWorkspaceExportButton(
              key: const ValueKey('mrn-export'),
              busy: _exporting,
              onPressed: _loading || _result == null ? null : _export,
            ),
          );
          final fixedWidth =
              controls.fold<double>(0, (sum, control) => sum + control.width!) +
              160 +
              10 * (controls.length + 1);
          if (size.maxWidth >= fixedWidth + 320) {
            return Row(
              children: [
                Expanded(child: search),
                for (final control in controls) ...[
                  const SizedBox(width: 10),
                  control,
                ],
                const SizedBox(width: 10),
                export,
              ],
            );
          }
          // Fill the final wrap line so Export remains at the right edge.
          var used = 0.0;
          for (final control in controls) {
            final width = math.min(control.width!, size.maxWidth);
            final next = used == 0 ? width : used + 10 + width;
            used = next > size.maxWidth ? width : next;
          }
          final remaining = size.maxWidth - used - 10;
          final exportSlot = remaining >= 160 ? remaining : size.maxWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final control in controls)
                    SizedBox(
                      width: math.min(control.width!, size.maxWidth),
                      child: control,
                    ),
                  SizedBox(
                    width: exportSlot,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: export,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
  SizedBox _dropdown(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> change,
  ) => SizedBox(
    width: switch (label) {
      'Supplier' => 184,
      'Sort' => 164,
      'Stock status' => 154,
      _ => 156,
    },
    height: 46,
    child: InventoryDropdownFormField<String>(
      searchable: true,
      key: ValueKey('$label:$value:${options.length}'),
      initialValue: options.containsKey(value) ? value : '',
      isExpanded: true,
      decoration: _input(label),
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontSize: 14, color: _ink),
      items: options.entries
          .map(
            (e) => DropdownMenuItem(
              value: e.key,
              child: Text(e.value, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) {
          setState(() => change(v));
          _applyFilters();
        }
      },
    ),
  );

  Widget _registerHeader(bool compact) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
    child: Row(
      children: [
        const Icon(Icons.fact_check_outlined, color: _teal, size: 21),
        const SizedBox(width: 9),
        const Flexible(
          child: Text(
            'Product register',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        _pill(
          _result == null
              ? '—'
              : '${_qty(_gridVisible)} / ${_qty(_result!.total)}',
          _teal,
        ),
        const Spacer(),
        if (!compact)
          const Text(
            'Open a product for full stock and sales details',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _muted, fontSize: 13),
          ),
        if (_expirySource != null) ...[
          const SizedBox(width: 10),
          Tooltip(
            message: _expiryError ?? 'Open Near Expiry and review notes',
            child: compact
                ? IconButton(
                    tooltip: 'Near Expiry',
                    onPressed: _openExpiry,
                    icon: const Icon(
                      Icons.notifications_active_outlined,
                      color: _amber,
                    ),
                  )
                : TextButton.icon(
                    onPressed: _openExpiry,
                    style: TextButton.styleFrom(foregroundColor: _amber),
                    icon: const Icon(
                      Icons.notifications_active_outlined,
                      size: 18,
                    ),
                    label: Text(
                      'Near Expiry${_expiryLoading || _expiryError != null ? '' : ' · ${_qty(_expirySummary?['near_expiry'])}'}',
                    ),
                  ),
          ),
        ],
        const SizedBox(width: 8),
        Tooltip(
          message: _focusView ? 'Show summary' : 'Expand table',
          child: compact
              ? IconButton(
                  key: const ValueKey('overview-focus-view'),
                  onPressed: () => setState(() => _focusView = !_focusView),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    _focusView
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    color: _teal,
                  ),
                )
              : TextButton.icon(
                  key: const ValueKey('overview-focus-view'),
                  onPressed: () => setState(() => _focusView = !_focusView),
                  style: TextButton.styleFrom(foregroundColor: _teal),
                  icon: Icon(
                    _focusView
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    size: 20,
                  ),
                  label: Text(_focusView ? 'Show summary' : 'Expand table'),
                ),
        ),
        IconButton(
          tooltip: 'Show stock and sales columns',
          visualDensity: VisualDensity.compact,
          onPressed: _filtered.isEmpty
              ? null
              : () {
                  if (_horizontal.hasClients) {
                    _horizontal.animateTo(
                      math.min(
                        _horizontal.position.maxScrollExtent,
                        _horizontal.offset + 650,
                      ),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                    );
                  }
                },
          icon: const Icon(Icons.arrow_forward_rounded, color: _teal, size: 19),
        ),
      ],
    ),
  );

  Widget _table(StockManagementResult? result) => result == null && _loading
      ? const Center(child: CircularProgressIndicator(color: _teal))
      : result == null
      ? const Center(
          child: Text(
            'Stock data could not be loaded.',
            style: TextStyle(color: _muted),
          ),
        )
      : _filtered.isEmpty
      ? Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.manage_search_rounded, size: 46, color: _muted),
              const SizedBox(height: 10),
              Text(
                result.meta.isEmpty
                    ? 'Build your first stock snapshot'
                    : 'No products match these filters',
                style: const TextStyle(
                  fontSize: 19,
                  color: _ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                result.meta.isEmpty
                    ? 'MRN products will appear when a stock snapshot is available.'
                    : 'Try another search or clear the filters.',
                style: const TextStyle(color: _muted),
              ),
            ],
          ),
        )
      : StockManagementGrid(
          key: _gridKey,
          items: _filtered,
          showWarehouse: widget.cd,
          horizontalController: _horizontal,
          onOpen: _details,
          onViewChanged: (visible, filtered) {
            if (_gridVisible != visible || _gridFiltered != filtered) {
              setState(() {
                _gridVisible = visible;
                _gridFiltered = filtered;
              });
            }
          },
        );
  Widget _footer(StockManagementResult? result, bool compact) {
    final total = result?.total ?? 0;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 20,
      runSpacing: 6,
      children: [
        Tooltip(
          message:
              'STORE + all active APG and 71 branches. Virtual and expired warehouses are excluded.\n'
              'Days on hand = total stock ÷ net daily sales over the latest available 45-day window.\n'
              '2026 sales and best month include the current partial month.\n'
              'Total Qty uses the reported total_qty. Bonus is shown as a note and is not added again.\n'
              'MRN CD entries and their histories are separate for each receiving warehouse. Stock and sales columns show the whole product.\n'
              'Expiry is the earliest date across the latest-day receipts. Total Qty is historical, not remaining batch stock.',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline_rounded, color: _muted, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  result == null
                      ? 'Source dates appear after loading'
                      : 'Stock: ${_date(result.meta['stock_updated_at']?.toString())}  ·  MRN through: ${_date(result.meta['mrn_through']?.toString())}  ·  Sales through: ${_date(result.meta['demand_through']?.toString())}',
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _loading
                  ? 'Loading ${_qty(_loaded)} / ${_qty(_loadTotal)} products…'
                  : 'Showing ${_qty(_gridVisible)} of ${_qty(total)}${_gridFiltered ? ' · column filters active' : ''}',
              style: const TextStyle(color: _muted, fontSize: 14),
            ),
          ],
        ),
      ],
    );
  }
}

InputDecoration _input(String label, {IconData? icon}) => InputDecoration(
  hintText: label,
  hintStyle: const TextStyle(color: _muted, fontSize: 14),
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  prefixIcon: icon == null ? null : Icon(icon, size: 19, color: _teal),
  filled: true,
  fillColor: const Color(0xFFFFFDF9),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: StockWorkspaceStyle.line),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: StockWorkspaceStyle.line),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: _teal, width: 1.5),
  ),
);
Widget _pill(String label, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
  decoration: BoxDecoration(
    color: color.withValues(alpha: .09),
    borderRadius: BorderRadius.circular(7),
  ),
  child: Text(
    label,
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700),
  ),
);
Widget _notice(String text, Color color, {Widget? action}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
  decoration: BoxDecoration(
    color: color.withValues(alpha: .07),
    borderRadius: BorderRadius.circular(10),
  ),
  child: Row(
    children: [
      Icon(Icons.info_outline, color: color, size: 18),
      const SizedBox(width: 10),
      Expanded(
        child: Text(text, style: TextStyle(color: color, fontSize: 14)),
      ),
      ?action,
    ],
  ),
);
Widget _heading(
  String label,
  double width, {
  bool warm = false,
  bool centered = false,
}) => SizedBox(
  width: width,
  height: double.infinity,
  child: DecoratedBox(
    decoration: BoxDecoration(
      border: warm
          ? const Border(right: BorderSide(color: StockWorkspaceStyle.line))
          : null,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Align(
        alignment: centered ? Alignment.center : Alignment.centerLeft,
        child: Text(
          label,
          textAlign: centered ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: warm ? const Color(0xFF705B49) : _muted,
            fontSize: warm ? 12.5 : 12,
            fontWeight: FontWeight.w800,
            letterSpacing: .5,
          ),
        ),
      ),
    ),
  ),
);

/// Server-paginated product register for the Overview workspace.
class StockManagementTable extends StatelessWidget {
  final ScrollController controller;
  final int rowCount;
  final IndexedWidgetBuilder rowBuilder;
  final Key? listKey;
  final List<Widget> afterProductHeadings;
  final double extraWidth;
  final bool warmStyle;
  final double rowExtent, headingHeight;
  const StockManagementTable({
    super.key,
    required this.controller,
    required this.rowCount,
    required this.rowBuilder,
    this.listKey,
    this.afterProductHeadings = const [],
    this.extraWidth = 0,
    this.warmStyle = false,
    this.rowExtent = 105,
    this.headingHeight = 54,
  });
  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: controller,
    thumbVisibility: true,
    trackVisibility: true,
    notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
    child: SingleChildScrollView(
      controller: controller,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 2170 + extraWidth,
        child: Column(
          children: [
            Container(
              height: headingHeight,
              color: warmStyle
                  ? const Color(0xFFFAF3E8)
                  : const Color(0xFFF5F8FC),
              child: Row(
                children: [
                  _heading('PRODUCT / SUPPLIER', 350, warm: warmStyle),
                  _heading('MRN DATE', 190, warm: warmStyle),
                  ...afterProductHeadings,
                  _heading('STOCK TOTAL', 170, warm: warmStyle),
                  _heading('STORE', 115, warm: warmStyle),
                  _heading('BRANCHES', 130, warm: warmStyle),
                  _heading('STORE / BRANCHES', 160, warm: warmStyle),
                  _heading('DAYS ON HAND', 180, warm: warmStyle),
                  _heading(
                    '2025 SALES · QTY',
                    300,
                    warm: warmStyle,
                    centered: true,
                  ),
                  _heading(
                    '2026 SALES · QTY',
                    300,
                    warm: warmStyle,
                    centered: true,
                  ),
                  _heading('BEST MONTH · 25 / 26', 240, warm: warmStyle),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                key: listKey,
                itemCount: rowCount,
                itemExtent: rowExtent,
                padding: const EdgeInsets.only(bottom: 14),
                itemBuilder: rowBuilder,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class StockManagementTableRow extends StatefulWidget {
  final StockManagementItem item;
  final VoidCallback onTap;
  final List<Widget> afterProductCells;
  final String? expiryReceiptDate;
  final Color? riskAccent;
  final bool alternate;
  final bool warmStyle;
  const StockManagementTableRow({
    super.key,
    required this.item,
    required this.onTap,
    this.afterProductCells = const [],
    this.expiryReceiptDate,
    this.riskAccent,
    this.alternate = false,
    this.warmStyle = false,
  });
  @override
  State<StockManagementTableRow> createState() => _StockRowState();
}

class _StockRowState extends State<StockManagementTableRow> {
  bool _hover = false;
  Widget cell(double width, Widget child) => SizedBox(
    width: width,
    height: double.infinity,
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: widget.warmStyle
            ? const Border(right: BorderSide(color: StockWorkspaceStyle.line))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: widget.riskAccent != null
              ? Color.alphaBlend(
                  widget.riskAccent!.withValues(
                    alpha: _hover
                        ? .11
                        : widget.alternate
                        ? .065
                        : .04,
                  ),
                  Colors.white,
                )
              : _hover
              ? const Color(0xFFEAF5F2)
              : widget.warmStyle
              ? widget.alternate
                    ? const Color(0xFFFCF9F5)
                    : Colors.white
              : Colors.white,
          border: Border(
            bottom: BorderSide(
              color: widget.riskAccent != null || widget.warmStyle
                  ? const Color(0xFFF0E8DB)
                  : _line,
            ),
            left: widget.riskAccent != null
                ? BorderSide(
                    color: widget.riskAccent!.withValues(alpha: .95),
                    width: 3,
                  )
                : BorderSide.none,
          ),
        ),
        child: InkWell(
          onTap: widget.onTap,
          child: Row(
            children: [
              cell(
                350,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Tooltip(
                      message: item.name,
                      child: Text(
                        item.name,
                        maxLines:
                            widget.riskAccent != null &&
                                MediaQuery.textScalerOf(context).scale(1) <= 1.1
                            ? 2
                            : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _ink,
                          fontSize: widget.riskAccent == null ? 14 : 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.code,
                      style: TextStyle(
                        color: widget.riskAccent == null ? _blue : _muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${item.text('supplier')} · ${item.text('category')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              cell(
                190,
                _MrnDateCell(
                  item: item,
                  expiryReceiptDate: widget.expiryReceiptDate,
                ),
              ),
              ...widget.afterProductCells,
              cell(
                170,
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item.stockAvailable
                            ? _qty(item.number('total_stock'))
                            : 'Unavailable',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _pill(
                      item.stockAvailable
                          ? _statusLabel(item.status)
                          : 'No snapshot',
                      item.stockAvailable && widget.riskAccent == null
                          ? _statusColor(item.status)
                          : _muted,
                    ),
                  ],
                ),
              ),
              cell(
                115,
                Text(
                  item.stockAvailable ? _qty(item.number('store_stock')) : '—',
                  style: TextStyle(
                    color: widget.riskAccent == null ? _blue : _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              cell(
                130,
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.stockAvailable
                          ? _qty(item.number('branches_stock'))
                          : '—',
                      maxLines: widget.riskAccent == null ? null : 1,
                      overflow: widget.riskAccent == null
                          ? null
                          : TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.riskAccent == null ? _teal : _ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      item.stockAvailable
                          ? '${_qty(item.number('stocked_branches'))} stocked'
                          : 'No snapshot',
                      maxLines: widget.riskAccent == null ? null : 1,
                      overflow: widget.riskAccent == null
                          ? null
                          : TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              cell(
                160,
                Text(
                  formatStockPercentage(item.storeTotalPercent),
                  style: const TextStyle(color: _ink, fontSize: 15),
                ),
              ),
              cell(
                180,
                _Coverage(item: item, neutral: widget.riskAccent != null),
              ),
              cell(
                300,
                StockSalesSummary(
                  data: item.year(2025),
                  totalColor: widget.riskAccent == null ? _blue : _ink,
                ),
              ),
              cell(
                300,
                StockSalesSummary(
                  data: item.year(2026),
                  totalColor: widget.riskAccent == null ? _teal : _ink,
                ),
              ),
              cell(
                240,
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '25  ${_month(item.year(2025)['best_month'])}  ·  Qty ${_qty(item.year(2025)['best_qty'])}',
                      style: TextStyle(
                        color: widget.riskAccent == null ? _blue : _ink,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '26  ${_month(item.year(2026)['best_month'])}  ·  Qty ${_qty(item.year(2026)['best_qty'])}',
                      style: TextStyle(
                        color: widget.riskAccent == null ? _teal : _ink,
                        fontSize: 13,
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
  }
}

class _MrnDateCell extends StatelessWidget {
  final StockManagementItem item;
  final String? expiryReceiptDate;
  const _MrnDateCell({required this.item, this.expiryReceiptDate});
  @override
  Widget build(BuildContext context) {
    final linked = expiryReceiptDate != null;
    final dateColor = linked ? _ink : _blue;
    final date = linked ? expiryReceiptDate! : item.text('last_mrn_date');
    return Tooltip(
      message: linked
          ? "Last receipt linked to this expiry alert. Latest product MRN: ${_date(item.text('last_mrn_date'))}."
          : 'All approved MRNs on the latest receipt day. Open the product for receipt details.',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: dateColor.withValues(alpha: linked ? .055 : .08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    size: 17,
                    color: dateColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _date(date),
                    key: ValueKey('mrn-date:${item.code}'),
                    style: TextStyle(
                      color: dateColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            linked
                ? 'Expiry-linked receipt'
                : 'Received ${_qty(item.number('last_mrn_qty'))}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          if (linked && date != item.text('last_mrn_date'))
            Text(
              'Latest: ${_date(item.text('last_mrn_date'))}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _Coverage extends StatelessWidget {
  final StockManagementItem item;
  final bool neutral;
  const _Coverage({required this.item, this.neutral = false});
  @override
  Widget build(BuildContext context) {
    if (!item.stockAvailable) {
      return const Text(
        'Unavailable',
        style: TextStyle(color: _muted, fontSize: 14),
      );
    }
    final days = item.days;
    final color = neutral ? _muted : _statusColor(item.status);
    return Tooltip(
      message:
          'Total stock ÷ average net daily sales. Returns reduce sales.\n'
          'Recent net quantity: ${_qty(item.number('recent_sales'))}; daily rate: ${_qty(item.number('daily_sales'))}.',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.status == 'no_stock'
                ? 'No Stock'
                : days == null
                ? 'No recent sales'
                : '${_qty(days)} days',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: days == null ? 0 : (days / 90).clamp(0, 1),
              minHeight: 4,
              backgroundColor: color.withValues(alpha: .1),
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// MRN and expiry share the Overview's charts, layout and branch controls.
class StockManagementProductDialog extends StatelessWidget {
  final StockManagementItem item;
  final StockManagementDataSource source;
  final Widget? extraSection;
  final StockManagementItem? receiptDetails;
  final VoidCallback? onClose;
  const StockManagementProductDialog({
    super.key,
    required this.item,
    required this.source,
    this.extraSection,
    this.receiptDetails,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) => StockCatalogProductDialog(
    item: StockCatalogItem({
      ...item.data,
      'item_name': item.name.toUpperCase(),
      'company': item.text('company').toUpperCase(),
      'catalog_unavailable': true,
    }),
    source: source is StockManagementRemoteDs
        ? StockCatalogRemoteDs((source as StockManagementRemoteDs).client)
        : null,
    loadItem: () async {
      final loaded = await source.fetchItem(item.code);
      return StockCatalogItem({
        ...loaded.data,
        if (!loaded.data.containsKey('last_3_sales'))
          'catalog_unavailable': true,
      });
    },
    onClose: onClose,
    allowSavedFallback: extraSection != null,
    detailsSection: (product) {
      final receipt =
          receiptDetails ??
          StockManagementItem(
            product.data['mrn_details'] is Map
                ? stockMap(product.data['mrn_details'])
                : product.data,
          );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (extraSection != null) ...[
            extraSection!,
            const SizedBox(height: 16),
          ],
          _mrnDetails(receipt),
          if (extraSection == null) ...[
            const SizedBox(height: 16),
            StockMrnReceipts(
              item: receipt,
              loadHistory: () => source.fetchReceiptHistory(item.code),
            ),
          ],
        ],
      );
    },
  );

  Widget _mrnDetails(StockManagementItem product) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth < 600
          ? 2
          : constraints.maxWidth < 1000
          ? 3
          : 5;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        key: const ValueKey('mrn-receipt-cards'),
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final entry in [
            if (product.isCdReceipt)
              (
                'WAREHOUSE',
                StoreBranchIdentityRegistry.displayName(product.warehouse),
                catalogTeal,
                Icons.storefront_outlined,
              ),
            (
              'LAST MRN',
              _date(product.text('last_mrn_date')),
              catalogBlue,
              Icons.event_note_rounded,
            ),
            (
              'VENDOR',
              formatStockVendor(product.data['vendor']),
              catalogTeal,
              Icons.local_shipping_outlined,
            ),
            (
              'EXPIRY DATE',
              '${_date(product.text('expiry_date'))}${product.number('expiry_count') > 1 ? ' (+${product.number('expiry_count').toInt() - 1})' : ''}',
              catalogOrange,
              Icons.event_busy_outlined,
            ),
            (
              'ORDERED QTY',
              product.data['ordered_quantity'] == null
                  ? '—'
                  : _qty(product.number('ordered_quantity')),
              catalogBlue,
              Icons.shopping_bag_outlined,
            ),
            (
              'TOTAL QTY',
              _qty(product.receiptTotal),
              catalogTeal,
              Icons.move_to_inbox_outlined,
            ),
          ])
            SizedBox(
              width: width,
              child: CatalogMetric(
                title: entry.$1,
                value: entry.$2.isEmpty ? '—' : entry.$2,
                caption: entry.$1 == 'TOTAL QTY' && product.receiptBonus > 0
                    ? 'Bonus ${_qty(product.receiptBonus)}'
                    : '',
                color: entry.$3,
                icon: entry.$4,
              ),
            ),
        ],
      );
    },
  );
}
