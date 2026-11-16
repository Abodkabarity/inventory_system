import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../domain/entities/daily_order_query.dart';
import '../../../domain/entities/daily_order_row.dart';
import '../../orders/bloc/order_bloc/orders_state.dart';
import '../../orders/widgets/orders_table.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_state.dart';
import '../widgets/inventory_columns_panel.dart';
import '../widgets/inventory_daily_order_exports.dart';
import '../widgets/inventory_daily_order_excel_filter.dart';
import '../widgets/inventory_orders_table.dart';
import '../widgets/tracker_branch_dropdown.dart';

const _navy = Color(0xFF17354D);
const _teal = Color(0xFF0C6F73);
const _border = Color(0xFFDEE7EF);
const _muted = Color(0xFF506677);

class InventoryDailyOrderPage extends StatefulWidget {
  final String runDate;
  const InventoryDailyOrderPage({super.key, required this.runDate});

  @override
  State<InventoryDailyOrderPage> createState() =>
      _InventoryDailyOrderPageState();
}

class _InventoryDailyOrderPageState extends State<InventoryDailyOrderPage> {
  final _search = TextEditingController();
  final _verticalScroll = ScrollController();
  final _filters = <String, DailyOrderColumnFilter>{};
  final _widths = <String, double>{};
  final _seen = <(String, String)>{};
  final _loadedBranches = <String>{};
  final _number = NumberFormat.decimalPattern('en_US');
  List<DailyOrderRow> _rows = const [];
  List<String> _branches = const [];
  String? _branch;
  String _sort = 'item_code';
  bool _ascending = true;
  DailyOrderQuery? _query;
  DailyOrderCursor? _next;
  Timer? _debounce;
  int _request = 0;
  int _results = 0;
  bool _updating = true;
  bool _loadingMore = false;
  bool _updateFailed = false;
  bool _moreFailed = false;

  @override
  void initState() {
    super.initState();
    _verticalScroll.addListener(_maybeLoadMore);
    StoreBranchIdentityRegistry.groups.addListener(_onBranchLabelsChanged);
    unawaited(_loadBranchOptions());
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant InventoryDailyOrderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runDate != widget.runDate) {
      _rows = const [];
      _loadedBranches.clear();
      unawaited(_reload());
    }
  }

  @override
  void dispose() {
    StoreBranchIdentityRegistry.groups.removeListener(_onBranchLabelsChanged);
    _debounce?.cancel();
    _verticalScroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadBranchOptions() async {
    try {
      final settings = await context
          .read<InventoryBloc>()
          .repo
          .fetchBranchSettings();
      if (!mounted) return;
      setState(() {
        _branches = settings
            .map((setting) => setting.branchName)
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList();
      });
    } catch (error) {
      debugPrint('Daily Order branch options: $error');
    }
  }

  void _onBranchLabelsChanged() {
    setState(() {});
    final search = _search.text.trim().toLowerCase();
    if (search.isNotEmpty &&
        (_displayedBranchMatches(search).isNotEmpty ||
            _query?.displayedBranchMatches.isNotEmpty == true)) {
      _onSearchChanged();
    }
  }

  List<String> _displayedBranchMatches(String search) {
    return [
      for (final name in StoreBranchIdentityRegistry.groups.value.keys)
        if (!name.toLowerCase().contains(search) &&
            StoreBranchIdentityRegistry.displayName(
              name,
            ).toLowerCase().contains(search))
          name,
    ];
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    // Supersede both searches and scroll requests as soon as the input changes.
    _request++;
    setState(() {
      _updating = true;
      _updateFailed = false;
      _loadingMore = false;
      _moreFailed = false;
    });
    _debounce = Timer(const Duration(milliseconds: 280), _reload);
  }

  DailyOrderQuery _makeQuery({bool allBranches = false}) {
    final search = _search.text.trim();
    return DailyOrderQuery(
      runDate: widget.runDate,
      search: search,
      branch: allBranches ? null : _branch,
      displayedBranchMatches: search.isEmpty
          ? const []
          : _displayedBranchMatches(search.toLowerCase()),
      filters: _filters,
      sort: _sort,
      ascending: _ascending,
    );
  }

  Future<void> _reload() async {
    _debounce?.cancel();
    final request = ++_request;
    final query = _makeQuery();
    setState(() {
      _updating = true;
      _updateFailed = false;
      _loadingMore = false;
      _moreFailed = false;
    });

    try {
      final batch = await context
          .read<InventoryBloc>()
          .repo
          .fetchDailyOrderBatch(query);
      if (!mounted || request != _request) return;
      if (_verticalScroll.hasClients) _verticalScroll.jumpTo(0);
      setState(() {
        _results++;
        _query = query;
        _next = batch.next;
        _seen.clear();
        _rows = _uniqueRows(batch.rows).toList(growable: false);
        _updating = false;
      });
      _checkScrollAfterLayout();
    } catch (error) {
      if (!mounted || request != _request) return;
      debugPrint('Daily Order results: $error');
      setState(() {
        _updating = false;
        _updateFailed = true;
      });
    }
  }

  Iterable<DailyOrderRow> _uniqueRows(List<DailyOrderRow> rows) sync* {
    for (final row in rows) {
      if (_seen.add((row.itemCode, row.branch))) {
        _loadedBranches.add(row.branch);
        yield row;
      }
    }
  }

  void _checkScrollAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLoadMore();
    });
  }

  void _maybeLoadMore() {
    if (_moreFailed || !_verticalScroll.hasClients) return;
    final position = _verticalScroll.position;
    if (position.hasContentDimensions && position.extentAfter < 720) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadMore() async {
    final next = _next;
    final query = _query;
    if (next == null ||
        query == null ||
        _loadingMore ||
        _updating ||
        _updateFailed) {
      return;
    }
    final request = _request;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    try {
      final batch = await context
          .read<InventoryBloc>()
          .repo
          .fetchDailyOrderBatch(query, after: next);
      if (!mounted || request != _request) return;
      if (batch.next == next) {
        throw StateError('Daily Order cursor did not advance.');
      }
      setState(() {
        _rows = [..._rows, ..._uniqueRows(batch.rows)];
        _next = batch.next;
        _loadingMore = false;
      });
      _checkScrollAfterLayout();
    } catch (error) {
      if (!mounted || request != _request) return;
      debugPrint('Daily Order continuation: $error');
      setState(() {
        _loadingMore = false;
        _moreFailed = true;
      });
    }
  }

  void _clearFilters() {
    _search.clear();
    _branch = null;
    _filters.clear();
    unawaited(_reload());
  }

  void _sortBy(String column) {
    if (_sort == column) {
      _ascending = !_ascending;
    } else {
      _sort = column;
      _ascending = true;
    }
    unawaited(_reload());
  }

  Future<void> _editFilter(String column, [Rect? bounds]) async {
    final field = DailyOrderField.fields[column];
    if (field == null) return;
    final runDate = widget.runDate;
    final repo = context.read<InventoryBloc>().repo;
    final query = _makeQuery(allBranches: column == 'branch');
    final initial =
        _filters[column] ??
        (column == 'branch' && _branch != null
            ? DailyOrderColumnFilter.values({_branch})
            : null);
    final result = await showGeneralDialog<DailyOrderFilterAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss column filter',
      barrierColor: const Color(0x24142A46),
      transitionDuration: const Duration(milliseconds: 130),
      pageBuilder: (context, animation, secondaryAnimation) {
        final padding = MediaQuery.paddingOf(context);
        final keyboard = MediaQuery.viewInsetsOf(context).bottom;
        return LayoutBuilder(
          builder: (context, constraints) {
            final left = padding.left + 10;
            final top = padding.top + 10;
            final right = constraints.maxWidth - padding.right - 10;
            final bottom =
                constraints.maxHeight - math.max(keyboard, padding.bottom) - 10;
            final width = math.min(330.0, right - left);
            final height = math.min(480.0, math.max(0.0, bottom - top));
            final preferredTop = bounds == null
                ? (top + bottom - height) / 2
                : bounds.bottom + height + 4 <= bottom
                ? bounds.bottom + 4
                : bounds.top - height - 4 >= top
                ? bounds.top - height - 4
                : bottom - height;
            return Stack(
              children: [
                Positioned(
                  left:
                      (bounds == null
                              ? (left + right - width) / 2
                              : bounds.right - width)
                          .clamp(left, right - width),
                  top: preferredTop.clamp(top, math.max(top, bottom - height)),
                  width: width,
                  height: height,
                  child: InventoryDailyOrderExcelFilter(
                    title: _columnTitle(column),
                    field: field,
                    initial: initial,
                    ascending: _sort == column ? _ascending : null,
                    loadValues: (lookup, after) =>
                        repo.fetchDailyOrderFilterValues(
                          query,
                          field: field,
                          lookup: lookup,
                          lookupBranches:
                              column == 'branch' && lookup.isNotEmpty
                              ? _displayedBranchMatches(lookup.toLowerCase())
                              : const [],
                          after: after,
                        ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (!mounted || result == null || widget.runDate != runDate) return;
    if (result.ascending case final ascending?) {
      _sort = column;
      _ascending = ascending;
    }
    if (result.filter case final filter?) {
      if (column == 'branch') _branch = null;
      if (filter.isActive) {
        _filters[column] = filter;
      } else {
        _filters.remove(column);
      }
    }
    unawaited(_reload());
  }

  void _openColumns() {
    final bloc = context.read<InventoryBloc>();
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Columns',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) => Align(
        alignment: Alignment.centerRight,
        child: BlocProvider.value(
          value: bloc,
          child: const InventoryColumnsPanel(),
        ),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          SlideTransition(
            position: Tween(begin: const Offset(1, 0), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          ),
    );
  }

  String _columnTitle(String column) =>
      (OrdersTable.titles[column] ??
              OrdersTable.optionalTitles[column] ??
              column)
          .replaceAll('\n', ' ');

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      buildWhen: (previous, current) =>
          previous.visibleColumns != current.visibleColumns ||
          previous.columnOrder != current.columnOrder,
      builder: (context, state) {
        final visible = state.visibleColumns.isEmpty
            ? OrdersState.defaultVisibleInTable
            : state.visibleColumns;
        final order = state.columnOrder.isEmpty
            ? OrdersState.defaultColumnOrder
            : state.columnOrder;
        final columns = order
            .where(
              (key) =>
                  key != 'branch' &&
                  visible.contains(key) &&
                  (key == 'row_no' || DailyOrderField.fields.containsKey(key)),
            )
            .toList();
        final code = columns.indexOf('item_code');
        columns.insert(code < 0 ? 0 : code, 'branch');

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildToolbar(context),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: _border),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 3,
                        child: _updating
                            ? const LinearProgressIndicator(
                                color: _teal,
                                backgroundColor: Color(0xFFE7F4F3),
                              )
                            : const SizedBox.shrink(),
                      ),
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            InventoryOrdersTable(
                              rows: _rows,
                              resultsVersion: _results,
                              orderedColumns: columns,
                              columnWidths: _widths,
                              verticalScrollController: _verticalScroll,
                              onColumnResized: (column, width) =>
                                  _widths[column] = width,
                              sortColumn: _sort,
                              ascending: _ascending,
                              filteredColumns: {
                                ..._filters.keys,
                                if (_branch != null) 'branch',
                              },
                              onSort: _sortBy,
                              onFilter: _editFilter,
                            ),
                            if (_rows.isEmpty)
                              Positioned.fill(
                                top: InventoryOrdersTable.headerHeight,
                                child: _buildEmpty(),
                              ),
                          ],
                        ),
                      ),
                      if (_rows.isNotEmpty) _buildFooter(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final branchOptions =
        <String>{
          ..._branches,
          ..._loadedBranches,
          ?_branch,
        }.where((branch) => branch.isNotEmpty).toList()..sort(
          (a, b) => StoreBranchIdentityRegistry.displayName(a)
              .toLowerCase()
              .compareTo(
                StoreBranchIdentityRegistry.displayName(b).toLowerCase(),
              ),
        );
    final date = DateTime.tryParse(widget.runDate);
    final dateLabel = date == null
        ? widget.runDate
        : DateFormat('EEE, d MMM yyyy', 'en_US').format(date);

    const fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide.none,
    );
    final searchField = TextField(
      controller: _search,
      onChanged: (_) => _onSearchChanged(),
      onSubmitted: (_) => unawaited(_reload()),
      textInputAction: TextInputAction.search,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: _navy,
      ),
      decoration: InputDecoration(
        hintText: 'Search item name, code, barcode or branch',
        hintStyle: const TextStyle(
          color: _muted,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: const Icon(Icons.search_rounded, color: _teal, size: 21),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 42,
          minHeight: 40,
        ),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded, size: 18, color: _muted),
                onPressed: () {
                  _search.clear();
                  unawaited(_reload());
                },
              ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 42,
          minHeight: 40,
        ),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 13,
          horizontal: 12,
        ),
        border: fieldBorder,
        enabledBorder: fieldBorder,
        focusedBorder: fieldBorder.copyWith(
          borderSide: const BorderSide(color: Color(0xFF63D9C7), width: 2),
        ),
      ),
    );

    final branchPicker = TrackerBranchDropdown(
      compact: true,
      value: _branch ?? 'ALL',
      items: ['ALL', ...branchOptions],
      onChanged: (branch) {
        _branch = branch == 'ALL' ? null : branch;
        _filters.remove('branch');
        unawaited(_reload());
      },
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1217344B),
            blurRadius: 16,
            offset: Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF142A46),
                  Color(0xFF16415A),
                  Color(0xFF12676B),
                ],
                stops: [0, .60, 1],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 1040;
                  final compact = constraints.maxWidth < 550;
                  final title = _toolbarTitle(dateLabel, compact: compact);
                  final actions = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_branch != null || _filters.isNotEmpty) ...[
                        _toolbarAction(
                          label: 'Clear filters',
                          icon: Icons.filter_alt_off_outlined,
                          onPressed: _clearFilters,
                        ),
                        const SizedBox(width: 6),
                      ],
                      _toolbarAction(
                        label: 'Refresh orders',
                        icon: Icons.refresh_rounded,
                        onPressed: _updating
                            ? null
                            : () => unawaited(_reload()),
                      ),
                      const SizedBox(width: 6),
                      _toolbarAction(
                        label: 'Columns',
                        icon: Icons.view_column_outlined,
                        showLabel: !compact,
                        onPressed: _openColumns,
                      ),
                      const SizedBox(width: 6),
                      _toolbarAction(
                        label: 'Export',
                        icon: Icons.download_rounded,
                        showLabel: !compact,
                        emphasized: true,
                        onPressed: () {
                          final repo = context.read<InventoryBloc>().repo;
                          showDialog<void>(
                            context: context,
                            builder: (_) =>
                                InventoryDailyOrderExports(repository: repo),
                          );
                        },
                      ),
                    ],
                  );

                  final controls = Row(
                    children: [
                      Expanded(child: searchField),
                      const SizedBox(width: 8),
                      SizedBox(width: 192, child: branchPicker),
                    ],
                  );
                  if (wide) {
                    return Row(
                      children: [
                        SizedBox(width: 197, child: title),
                        const SizedBox(width: 10),
                        Expanded(child: controls),
                        const SizedBox(width: 12),
                        actions,
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(child: title),
                          const SizedBox(width: 8),
                          actions,
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (constraints.maxWidth >= 510)
                        controls
                      else ...[
                        searchField,
                        const SizedBox(height: 7),
                        branchPicker,
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
          if (_filters.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: Icon(
                        Icons.filter_alt_outlined,
                        size: 17,
                        color: _teal,
                      ),
                    ),
                    for (final entry in _filters.entries)
                      _filterChip(
                        _filterLabel(entry.key, entry.value),
                        () {
                          _filters.remove(entry.key);
                          unawaited(_reload());
                        },
                        onPressed: () => _editFilter(entry.key),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _toolbarTitle(String dateLabel, {required bool compact}) {
    return Row(
      children: [
        if (!compact) ...[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF75DEC9).withValues(alpha: .15),
              border: Border.all(
                color: const Color(0xFF75DEC9).withValues(alpha: .25),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.shopping_cart_outlined,
              color: Color(0xFF8FE6D5),
              size: 21,
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Daily Order',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 18 : 21,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                dateLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFBCD3DF),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toolbarAction({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool showLabel = false,
    bool emphasized = false,
  }) {
    return Tooltip(
      message: label,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: emphasized ? const Color(0xFF113B39) : Colors.white,
          disabledForegroundColor: const Color(0xFF91ADBA),
          backgroundColor: emphasized
              ? const Color(0xFFA2EADB)
              : const Color(0x1AFFFFFF),
          disabledBackgroundColor: const Color(0x13FFFFFF),
          minimumSize: const Size(40, 40),
          padding: EdgeInsets.symmetric(horizontal: showLabel ? 12 : 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          side: emphasized ? null : const BorderSide(color: Color(0x3DFFFFFF)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            if (showLabel) ...[
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _filterLabel(String column, DailyOrderColumnFilter filter) {
    final title = _columnTitle(column);
    if (filter.values case final values?) {
      return filter.excludeValues
          ? '$title · ${values.length} excluded'
          : '$title · ${values.length} selected';
    }
    if (filter.rules.length != 1) {
      return '$title · ${filter.rules.length} rules';
    }
    final rule = filter.rules.single;
    final value = column == 'is_upp'
        ? (rule.value == 'true' ? 'Yes' : 'No')
        : rule.value;
    return rule.operator.needsValue
        ? '$title · ${rule.operator.label} $value'
        : '$title · ${rule.operator.label}';
  }

  Widget _filterChip(
    String label,
    VoidCallback onDeleted, {
    VoidCallback? onPressed,
  }) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: InputChip(
      backgroundColor: const Color(0xFFEAF6F5),
      side: const BorderSide(color: Color(0xFFCFE8E7)),
      tooltip: label,
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: _navy),
        ),
      ),
      onPressed: onPressed,
      onDeleted: onDeleted,
    ),
  );

  Widget _buildEmpty() {
    final filtered =
        _query != null &&
        (_query!.search.isNotEmpty ||
            _query!.branch != null ||
            _query!.filters.isNotEmpty);
    final title = _updating
        ? 'Loading daily orders…'
        : _updateFailed
        ? 'Couldn’t load orders'
        : filtered
        ? 'No matching orders'
        : 'No orders for this date';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_updating)
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: _updateFailed
                    ? const Color(0xFFFFF0EC)
                    : const Color(0xFFEAF5F5),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                _updateFailed
                    ? Icons.cloud_off_outlined
                    : filtered
                    ? Icons.search_off_rounded
                    : Icons.inventory_2_outlined,
                size: 27,
                color: _updateFailed ? const Color(0xFFA44838) : _teal,
              ),
            ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: _navy,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (!_updating && _updateFailed)
            TextButton(onPressed: _reload, child: const Text('Retry')),
          if (!_updating && !_updateFailed && filtered)
            TextButton(
              onPressed: _clearFilters,
              child: const Text('Clear filters'),
            ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final message = _updating
        ? 'Updating results…'
        : _updateFailed
        ? 'Update failed. Showing previous results.'
        : _loadingMore
        ? 'Loading more…'
        : _moreFailed
        ? 'Couldn’t load more orders.'
        : _next == null
        ? 'End of results'
        : 'Scroll for more';
    final failed = _updateFailed || _moreFailed;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _border)),
        color: Color(0xFFF6F9FC),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFE5F3F1),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '${_number.format(_rows.length)} rows loaded',
              style: const TextStyle(
                color: Color(0xFF1B615C),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (_loadingMore) ...[
            const SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: _teal),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                message,
                style: TextStyle(
                  color: failed ? const Color(0xFFA44838) : _muted,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          if (failed)
            TextButton(
              onPressed: _updateFailed ? _reload : _loadMore,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
