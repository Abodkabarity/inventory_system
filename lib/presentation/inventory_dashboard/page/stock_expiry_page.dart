import '../../widgets/inventory_dropdown.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/stock_register_export.dart';
import '../../../core/utils/stock_excel_export.dart';
import '../../../core/utils/stock_vendor.dart';
import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../data/datasources/remote/stock_expiry_remote_ds.dart';
import '../../../domain/entities/stock_expiry.dart';
import '../../../domain/entities/stock_management.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/datasources/remote/stock_management_remote_ds.dart';
import 'stock_management_page.dart';
import '../widgets/stock_expiry_grid.dart';
import '../widgets/stock_workspace_style.dart';

const _ink = Color(0xFF142C40),
    _muted = Color(0xFF64748B),
    _teal = Color(0xFF008A83),
    _amber = Color(0xFFB76C06),
    _red = Color(0xFFC63E55),
    _expired = Color(0xFF9F2339),
    _orange = Color(0xFFC45A15),
    _gold = Color(0xFF96700E),
    _line = Color(0xFFE9E2D8);
String _qty(dynamic n) => NumberFormat('#,##0.##').format(stockNumber(n));
String _date(String s) => DateTime.tryParse(s) == null
    ? '—'
    : DateFormat('dd MMM yyyy').format(DateTime.parse(s));
// Review state is separate: the receipt's expiry always determines its colour.
Color _risk(StockExpiryAlert a) => a.days < 0
    ? _expired
    : a.days <= 60
    ? _red
    : a.days <= 90
    ? _orange
    : _gold;
const _expiryColourGuide =
    'Expiry colours: expired = dark red; 0–60 days = red; 61–90 days = orange; more than 90 days = gold. Colours indicate time to expiry, not stock coverage. Reviewed items keep their expiry colour.';
String _days(StockExpiryAlert a) => a.days < 0
    ? '${-a.days} days overdue'
    : a.days == 0
    ? 'Expires today'
    : '${a.days} days left';
const _sourceWarning =
    'Expiry dates come from MRN receipts, not a live batch balance. Received quantity is historical; current stock is for the whole product. Verify the remaining batch before taking action.';

class StockExpiryPage extends StatefulWidget {
  final StockExpiryDataSource dataSource;
  final ValueChanged<StockManagementItem>? onOpenProduct;
  final bool embedded;
  final bool readOnly;
  final StockManagementDataSource? productDataSource;
  final StockRegisterExporter? exporter;
  const StockExpiryPage({
    super.key,
    required this.dataSource,
    this.onOpenProduct,
    this.embedded = false,
    this.readOnly = false,
    this.productDataSource,
    this.exporter,
  });
  @override
  State<StockExpiryPage> createState() => _StockExpiryPageState();
}

class _StockExpiryPageState extends State<StockExpiryPage> {
  final _search = TextEditingController();
  final _horizontal = ScrollController();
  final _gridKey = GlobalKey<StockExpiryGridState>();
  int _visibleRows = 0;
  bool _hasColumnFilters = false;
  final _busy = <String>{}, _fading = <String>{};
  Timer? _debounce;
  StockExpiryResult? _result;
  bool _exporting = false;
  String _state = 'pending', _urgency = '';
  String? _error;
  int _request = 0;
  bool _loading = true, _focusView = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _request++;
    _debounce?.cancel();
    _search.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    if (_exporting || _loading || _result == null) return;
    setState(() => _exporting = true);
    try {
      if (_debounce?.isActive ?? false) {
        _debounce?.cancel();
        await _load();
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (_error != null) {
        throw StateError('Reload the current filters before exporting.');
      }
      final rows = [
        for (final alert
            in _gridKey.currentState?.visibleAlerts ?? _result!.rows)
          stockExpiryExportRow(alert),
      ];
      if (rows.isEmpty) {
        throw StateError('No matching expiry alerts to export.');
      }
      await (widget.exporter ?? saveStockExcel)(rows, 'near_expiry.xlsx');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported ${rows.length} matching expiry alerts'),
          ),
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
      _error = null;
    });
    try {
      final data = await widget.dataSource.fetchAll(
        StockExpiryQuery(
          search: _search.text,
          reviewState: _state,
          urgency: _urgency,
        ),
        isCancelled: () => !mounted || request != _request,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _result = data;
        if (!_hasColumnFilters) _visibleRows = data.rows.length;
        _loading = false;
      });
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _error = 'Could not load expiry alerts. $e';
        });
      }
    }
  }

  void _filter(String state, [String urgency = '']) {
    setState(() {
      _state = state;
      _urgency = urgency;
    });
    _load();
  }

  Future<void> _review(StockExpiryAlert alert, String action) async {
    if (widget.readOnly || _busy.contains(alert.key)) return;
    setState(() => _busy.add(alert.key));
    try {
      final saved = await widget.dataSource.save(
        alert,
        note: alert.note,
        action: action,
      );
      if (!mounted) return;
      if (_state != 'all') {
        setState(() => _fading.add(alert.key));
        if (!MediaQuery.disableAnimationsOf(context)) {
          await Future<void>.delayed(const Duration(milliseconds: 180));
        }
      }
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      final undoAlert = StockExpiryAlert({
        ...alert.data,
        'review_updated_at': saved['updated_at'],
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'review'
                ? 'Reviewed — removed from active alarms.'
                : 'Alert reopened.',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () =>
                _review(undoAlert, action == 'review' ? 'reopen' : 'review'),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save. $e'),
            action: SnackBarAction(label: 'Reload', onPressed: () => _load()),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy.remove(alert.key);
          _fading.remove(alert.key);
        });
      }
    }
  }

  Future<void> _note(StockExpiryAlert alert) async {
    if (_busy.contains(alert.key)) return;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReviewDialog(
        alert: alert,
        source: widget.dataSource,
        productSource: widget.productDataSource,
        readOnly: widget.readOnly,
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8F5EF),
    body: DecoratedBox(
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
                          _filters(),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(color: _red),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => _load(),
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 3,
                    child: _loading
                        ? const LinearProgressIndicator(
                            color: _amber,
                            backgroundColor: _line,
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: StockWorkspaceRegisterFrame(
                      child: Column(
                        children: [
                          _registerHeader(compact),
                          Expanded(child: _body(compact)),
                        ],
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
  Widget _header(
    bool compact, {
    bool inlineStats = false,
  }) => StockWorkspaceBanner(
    compact: compact,
    child: Row(
      children: [
        if (!widget.embedded) ...[
          IconButton(
            tooltip: 'Back to Stock Management',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          const SizedBox(width: 8),
        ],
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF4AD61), Color(0xFFD5694D)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.notifications_active_outlined,
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
                'Near Expiry',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 23 : 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.4,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Stock Management / Near Expiry',
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
        if (!compact && !inlineStats) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .09),
              border: Border.all(color: Colors.white.withValues(alpha: .14)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFC47B),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_result == null ? '—' : _qty(_result!.summary['pending'])} awaiting review',
                  style: const TextStyle(
                    color: Color(0xFFFFDFB3),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
        ],
      ],
    ),
  );
  Widget _registerHeader(bool compact) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 1),
    child: Row(
      children: [
        Expanded(
          child: Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: _teal, size: 21),
              const SizedBox(width: 9),
              const Flexible(
                child: Text(
                  'Review register',
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
              _tag(_result == null ? '—' : _qty(_result!.total), _teal),
            ],
          ),
        ),
        if (!compact) Flexible(fit: FlexFit.tight, child: _sourceNotice()),
        const SizedBox(width: 8),
        if (compact) _alertHelp(),
        Tooltip(
          message: _focusView ? 'Show summary' : 'Expand table',
          child: compact
              ? IconButton(
                  key: const ValueKey('expiry-focus-view'),
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
                  key: const ValueKey('expiry-focus-view'),
                  onPressed: () => setState(() => _focusView = !_focusView),
                  style: TextButton.styleFrom(
                    foregroundColor: _teal,
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: Icon(
                    _focusView
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    size: 21,
                  ),
                  label: Text(_focusView ? 'Show summary' : 'Expand table'),
                ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Show stock and sales columns',
          visualDensity: VisualDensity.compact,
          onPressed: _result == null || _result!.rows.isEmpty
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
  Widget _stats(bool compact) {
    final summary = _result?.summary ?? {};
    final cards = [
      (
        'Near expiry',
        'near_expiry',
        _amber,
        Icons.notifications_active_outlined,
        'pending',
        'near',
      ),
      (
        'Within 30 days',
        'urgent',
        _red,
        Icons.hourglass_bottom_rounded,
        'pending',
        'urgent',
      ),
      (
        'Expired dates',
        'expired',
        _red,
        Icons.event_busy_outlined,
        'pending',
        'expired',
      ),
      ('Reviewed', 'reviewed', _teal, Icons.task_alt_rounded, 'reviewed', ''),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final count = compact ? 2 : 4;
        final width = (c.maxWidth - (count - 1) * 12) / count;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map(
                (card) => SizedBox(
                  width: width,
                  child: StockWorkspaceMetricCard(
                    label: card.$1,
                    value: _result == null
                        ? null
                        : stockNumber(summary[card.$2]),
                    color: card.$3,
                    icon: card.$4,
                    selected: _state == card.$5 && _urgency == card.$6,
                    caption: switch (card.$2) {
                      'urgent' => 'Prioritize these receipts',
                      'expired' => 'Verify and resolve',
                      'reviewed' => 'Notes safely retained',
                      _ => 'Check the remaining batch',
                    },
                    onTap: () => _filter(card.$5, card.$6),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  InputDecoration _filterDecoration() => InputDecoration(
    filled: true,
    fillColor: const Color(0xFFFFFDF9),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _teal, width: 1.5),
    ),
  );

  Widget _filters() => StockWorkspaceFilterSurface(
    child: Padding(
      padding: const EdgeInsets.all(6),
      child: LayoutBuilder(
        builder: (context, size) => Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: math.min(
                size.maxWidth,
                math.max(280, size.maxWidth * .25),
              ),
              height: 46,
              child: TextField(
                controller: _search,
                style: const TextStyle(color: _ink, fontSize: 15),
                decoration: _filterDecoration().copyWith(
                  hintText: 'Search product, code, supplier…',
                  hintStyle: const TextStyle(fontSize: 14, color: _muted),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 21,
                    color: _teal,
                  ),
                ),
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 350),
                    () => _load(),
                  );
                },
              ),
            ),
            for (final entry in [
              ('pending', 'Active'),
              ('reviewed', 'Reviewed'),
              ('all', 'All'),
            ])
              ChoiceChip(
                label: Text(entry.$2),
                selected: _state == entry.$1,
                onSelected: (_) => _filter(entry.$1),
                selectedColor: _teal,
                backgroundColor: const Color(0xFFFAF7F1),
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                  color: _state == entry.$1 ? Colors.white : _ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                side: BorderSide(color: _state == entry.$1 ? _teal : _line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            SizedBox(
              width: math.min(220, size.maxWidth),
              height: 46,
              child: InventoryDropdownFormField<String>(
                searchable: true,
                key: ValueKey(_urgency),
                initialValue: _urgency,
                isExpanded: true,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontSize: 14, color: _ink),
                decoration: _filterDecoration(),
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: _teal,
                ),
                items: const [
                  DropdownMenuItem(value: '', child: Text('All expiry dates')),
                  DropdownMenuItem(
                    value: 'near',
                    child: Text('Upcoming · <6 months'),
                  ),
                  DropdownMenuItem(value: 'urgent', child: Text('0–30 days')),
                  DropdownMenuItem(value: 'soon', child: Text('31–90 days')),
                  DropdownMenuItem(
                    value: 'later',
                    child: Text('91 days – <6 months'),
                  ),
                  DropdownMenuItem(value: 'expired', child: Text('Expired')),
                ],
                onChanged: (v) {
                  if (v != null) _filter(_state, v);
                },
              ),
            ),
            if (_search.text.isNotEmpty ||
                _urgency.isNotEmpty ||
                _state != 'pending' ||
                _hasColumnFilters)
              TextButton.icon(
                onPressed: () {
                  _search.clear();
                  _gridKey.currentState?.clearFilters();
                  _debounce?.cancel();
                  _filter('pending');
                },
                style: TextButton.styleFrom(foregroundColor: _teal),
                icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
                label: const Text('Clear filters'),
              ),
            StockWorkspaceExportButton(
              key: const ValueKey('expiry-export'),
              busy: _exporting,
              onPressed: _loading || _result == null ? null : _export,
            ),
          ],
        ),
      ),
    ),
  );
  Widget _sourceNotice() => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Expanded(
        child: Tooltip(
          message:
              'Earlier detected issues stay until reviewed. $_sourceWarning',
          child: Text(
            'Receipts ${_date('${_result?.meta['window_from'] ?? ''}')} – ${_date('${_result?.meta['window_through'] ?? ''}')}',
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _amber, fontSize: 13),
          ),
        ),
      ),
      _alertHelp(),
    ],
  );

  Widget _alertHelp() => IconButton(
    tooltip: 'About these alerts · expiry colour guide',
    visualDensity: VisualDensity.compact,
    onPressed: () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About these alerts'),
        content: Text(
          'Receipts ${_date('${_result?.meta['window_from'] ?? ''}')} – ${_date('${_result?.meta['window_through'] ?? ''}')}\n\n'
          '$_expiryColourGuide\n\n$_sourceWarning\n\nDiscovery starts with seven days ending yesterday in Dubai time. Earlier MRNs are excluded. Detected alerts remain in the permanent register after the week ends, stock changes or the source is replaced. Active includes expired alerts. New or changed receipts reactivate a review and preserve its note.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    ),
    icon: const Icon(Icons.help_outline_rounded, color: _amber, size: 18),
  );
  Widget _body(bool compact) {
    final data = _result;
    if (data == null) {
      return Center(
        child: _loading
            ? const CircularProgressIndicator(color: _amber)
            : const Text('Expiry alerts are unavailable. Retry above.'),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: StockExpiryGrid(
            key: _gridKey,
            alerts: data.rows,
            readOnly: widget.readOnly,
            busy: Set.of(_busy),
            fading: Set.of(_fading),
            horizontalController: _horizontal,
            riskColor: _risk,
            onOpen: _note,
            onReview: (a) => _review(a, a.reviewed ? 'reopen' : 'review'),
            onViewChanged: (visible, filtered) {
              if (!mounted ||
                  (visible == _visibleRows && filtered == _hasColumnFilters)) {
                return;
              }
              setState(() {
                _visibleRows = visible;
                _hasColumnFilters = filtered;
              });
            },
          ),
        ),
        if (data.rows.isEmpty || (_hasColumnFilters && _visibleRows == 0))
          const Positioned.fill(
            top: 54,
            child: IgnorePointer(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.filter_alt_off_outlined,
                        color: _muted,
                        size: 36,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'No expiry alerts match these filters.',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Change a column filter or use Clear filters above.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _muted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Widget _surface(Widget child) => Material(
  color: Colors.white,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
    side: const BorderSide(color: _line),
  ),
  clipBehavior: Clip.antiAlias,
  child: child,
);
Widget _tag(String label, Color color, {IconData? icon}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
  decoration: BoxDecoration(
    color: color.withValues(alpha: .08),
    borderRadius: BorderRadius.circular(7),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
      ],
      Flexible(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  ),
);

class _ReviewDialog extends StatefulWidget {
  final StockExpiryAlert alert;
  final StockExpiryDataSource source;
  final StockManagementDataSource? productSource;
  final bool readOnly;
  const _ReviewDialog({
    required this.alert,
    required this.source,
    this.productSource,
    this.readOnly = false,
  });
  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final _note = TextEditingController();
  StockExpiryAlert? _alert;
  bool _loading = true, _saving = false, _changed = false;
  String? _error;
  bool get _dirty => _alert != null && _note.text != _alert!.note;
  @override
  void initState() {
    super.initState();
    _load();
    _note.addListener(_edit);
  }

  void _edit() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final a = await widget.source.fetchItem(widget.alert);
      if (!mounted) return;
      _note.text = a.note;
      setState(() {
        _alert = a;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load the latest note. $e';
        });
      }
    }
  }

  Future<void> _close() async {
    if (_saving) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard unsaved note?'),
          content: const Text('Your changes have not been saved.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context, _changed);
  }

  Future<void> _save(String action) async {
    if (widget.readOnly) return;
    if (_alert == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.source.save(
        _alert!,
        note: _note.text,
        action: action,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _changed = true;
        _alert = StockExpiryAlert({
          ..._alert!.data,
          'note': _note.text,
          'review_updated_at': saved['updated_at'],
          'is_reviewed': action == 'review'
              ? true
              : action == 'reopen'
              ? false
              : _alert!.reviewed,
        });
      });
      if (action != 'note') {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save. $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _alert ?? widget.alert, c = _risk(a);
    return PopScope(
      canPop: !_saving && !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: StockManagementProductDialog(
        item: a.product,
        receiptDetails: StockManagementItem({
          'last_mrn_date': a.text('last_receipt_date'),
          'expiry_date': a.expiry,
          'vendor': a.data['vendor'],
          'ordered_quantity': a.data['ordered_qty'],
          'received_quantity': a.data['received_qty'],
          'last_mrn_qty': a.data['received_qty'],
        }),
        source:
            widget.productSource ??
            StockManagementRemoteDs(Supabase.instance.client),
        onClose: _close,
        extraSection: _reviewSection(a, c),
      ),
    );
  }

  Widget _reviewSection(StockExpiryAlert a, Color risk) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_alert != null) ...[
        Wrap(
          key: const ValueKey('expiry-review-badges'),
          spacing: 8,
          runSpacing: 8,
          children: [
            _tag('Expiry ${_date(a.expiry)}', risk, icon: Icons.event_outlined),
            _tag(_days(a), risk),
            _tag(
              'Expiry MRN date ${_date(a.text('last_receipt_date'))}',
              _teal,
              icon: Icons.calendar_month_rounded,
            ),
            _tag('MRN qty ${_qty(a.data['received_qty'])}', _amber),
            _tag(
              'Vendor ${formatStockVendor(a.data['vendor']).isEmpty ? '—' : formatStockVendor(a.data['vendor'])}',
              _teal,
              icon: Icons.local_shipping_outlined,
            ),
            _tag(
              a.product.stockAvailable
                  ? 'Current product stock ${_qty(a.data['total_stock'])}'
                  : 'Product stock unavailable',
              _teal,
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
      _surface(
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: _loading
              ? const SizedBox(
                  height: 56,
                  child: Center(child: CircularProgressIndicator(color: _teal)),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        color: _red.withValues(alpha: .06),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _error!,
                              style: const TextStyle(color: _red, fontSize: 14),
                            ),
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : () {
                                      if (_dirty) {
                                        showDialog<void>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text(
                                              'Copy your note first',
                                            ),
                                            content: const Text(
                                              'Reloading will replace your unsaved text with the latest saved version. Copy it before reloading.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                child: const Text(
                                                  'Keep editing',
                                                ),
                                              ),
                                              TextButton(
                                                onPressed: () {
                                                  Navigator.pop(context);
                                                  _load();
                                                },
                                                child: const Text(
                                                  'Reload anyway',
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      } else {
                                        _load();
                                      }
                                    },
                              child: const Text('Reload latest note'),
                            ),
                          ],
                        ),
                      ),

                    if (_alert != null) ...[
                      if (a.reviewed ||
                          a.newReceipts ||
                          a.data['stock_snapshot_missing'] == true)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (a.reviewed)
                                _tag(
                                  'Reviewed',
                                  _teal,
                                  icon: Icons.task_alt_rounded,
                                ),
                              if (a.newReceipts)
                                _tag('New receipts since review', _amber),
                              if (a.data['stock_snapshot_missing'] == true)
                                _tag(
                                  'Saved product facts · live stock unavailable',
                                  _amber,
                                ),
                            ],
                          ),
                        ),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final actions = widget.readOnly
                              ? const SizedBox.shrink()
                              : Wrap(
                                  key: const ValueKey('expiry-note-actions'),
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    SizedBox(
                                      height: 48,
                                      child: OutlinedButton.icon(
                                        onPressed: _saving || !_dirty
                                            ? null
                                            : () => _save('note'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: _teal,
                                          side: BorderSide(
                                            color: _teal.withValues(alpha: .25),
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.save_outlined,
                                          size: 18,
                                        ),
                                        label: const Text('Save note'),
                                      ),
                                    ),
                                    SizedBox(
                                      height: 48,
                                      child: FilledButton.icon(
                                        key: const ValueKey(
                                          'expiry-review-button',
                                        ),
                                        onPressed: _saving
                                            ? null
                                            : () => _save(
                                                a.reviewed
                                                    ? 'reopen'
                                                    : 'review',
                                              ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: _teal,
                                          foregroundColor: Colors.white,
                                          disabledBackgroundColor: _teal
                                              .withValues(alpha: .55),
                                          disabledForegroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                        icon: _saving
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : Icon(
                                                a.reviewed
                                                    ? Icons.undo_rounded
                                                    : Icons.task_alt_rounded,
                                                size: 18,
                                              ),
                                        label: Text(
                                          a.reviewed
                                              ? 'Reopen alarm'
                                              : 'Save & mark reviewed',
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                          final note = TextField(
                            key: const ValueKey('expiry-note-field'),
                            controller: _note,
                            readOnly: widget.readOnly,
                            enabled: !_saving,
                            minLines: 1,
                            maxLines: 2,
                            maxLength: 4000,
                            style: const TextStyle(color: _ink, fontSize: 14),
                            decoration: InputDecoration(
                              labelText: 'Review note',
                              hintText: 'Write a follow-up or action…',
                              prefixIcon: const Icon(
                                Icons.sticky_note_2_outlined,
                                color: _teal,
                                size: 19,
                              ),
                              suffixText: '${_note.text.length}/4000',
                              suffixStyle: const TextStyle(
                                color: _muted,
                                fontSize: 10,
                              ),
                              counterText: '',
                              filled: true,
                              fillColor: const Color(0xFFF6FAFC),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 17,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFFDFEAF0),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: _teal,
                                  width: 1.5,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                          return constraints.maxWidth >=
                                  820 *
                                      MediaQuery.textScalerOf(context).scale(1)
                              ? Row(
                                  key: const ValueKey('expiry-note-toolbar'),
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(child: note),
                                    const SizedBox(width: 12),
                                    actions,
                                  ],
                                )
                              : Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    note,
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: actions,
                                    ),
                                  ],
                                );
                        },
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Theme(
                              data: Theme.of(
                                context,
                              ).copyWith(dividerColor: Colors.transparent),
                              child: ExpansionTile(
                                key: const ValueKey('expiry-receipt-evidence'),
                                tilePadding: EdgeInsets.zero,
                                childrenPadding: EdgeInsets.zero,
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                minTileHeight: 40,
                                title: Text(
                                  'Receipt evidence (${a.receipts.length})',
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      _sourceWarning,
                                      style: TextStyle(
                                        color: _muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  for (final receipt in a.receipts)
                                    ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(
                                        Icons.receipt_long_outlined,
                                        color: _muted,
                                        size: 18,
                                      ),
                                      title: Text(
                                        'MRN ${receipt['mrn_no']} · ${_date('${receipt['mrn_date'] ?? ''}')}',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                      subtitle: Text(
                                        StoreBranchIdentityRegistry.displayName(
                                          receipt['warehouse']?.toString(),
                                        ),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      trailing: Text(
                                        _qty(receipt['received_qty']),
                                        style: const TextStyle(
                                          color: _ink,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (_changed && !_dirty)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                'Saved',
                                style: TextStyle(
                                  color: _teal,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          Tooltip(
                            message:
                                '$_sourceWarning\nReviewed items leave the active list; notes remain saved. Changed receipts create a fresh alarm.',
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: Icon(
                                Icons.info_outline_rounded,
                                color: _muted,
                                size: 17,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ),
    ],
  );
}
