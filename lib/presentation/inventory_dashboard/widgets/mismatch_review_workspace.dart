import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/mismatch_review_exporter.dart';
import '../../../core/utils/store_branch_identity_registry.dart';
import '../../../data/repositories/mismatch_review_repository.dart';
import '../../../domain/entities/mismatch_review.dart';
import '../../../domain/entities/mismatch_stock_journey.dart';
import '../../widgets/app_date_range_picker_dialog.dart';
import 'tracker_branch_dropdown.dart';
import 'mismatch_dashboard_visuals.dart';

const _ink = Color(0xFF07283E),
    _teal = Color(0xFF007F90),
    _muted = Color(0xFF64748B),
    _line = Color(0xFFC6DAED);

class MismatchReviewWorkspace extends StatefulWidget {
  const MismatchReviewWorkspace({
    super.key,
    this.controller,
    this.onLegacyExport,
    this.exportInProgress = false,
  });
  final MismatchReviewController? controller;
  final void Function(String branch, String search)? onLegacyExport;
  final bool exportInProgress;
  @override
  State<MismatchReviewWorkspace> createState() =>
      _MismatchReviewWorkspaceState();
}

class _MismatchReviewWorkspaceState extends State<MismatchReviewWorkspace> {
  late final MismatchReviewController _controller;
  final _search = TextEditingController();
  final _rowScroll = ScrollController(), _columnScroll = ScrollController();
  int _page = 0, _pageSize = 50;
  String _branch = 'ALL', _risk = 'all';
  DateTimeRange? _reportRange;
  bool _recentFirst = false, _exporting = false;
  List<Object?>? _projectionKey;
  List<MismatchReview> _scopedRows = [], _visibleRows = [];
  List<String> _branches = [];
  int _followups = 0, _adjustmentReviews = 0, _evidenceGaps = 0;

  void _project() {
    final key = <Object?>[
      _controller.rows,
      StoreBranchIdentityRegistry.groups.value,
      _search.text,
      _branch,
      _risk,
      _reportRange,
      _recentFirst,
    ];
    if (listEquals(key, _projectionKey)) return;
    _projectionKey = key;
    _scopedRows = _scope();
    _visibleRows = _visible(_scopedRows);
    _page = _page.clamp(
      0,
      math.max(0, (_visibleRows.length / _pageSize).ceil() - 1),
    );
    _followups = _scopedRows.where((r) => r.needsFollowup).length;
    _adjustmentReviews = _scopedRows
        .where((r) => r.status == 'adjustment_review')
        .length;
    _evidenceGaps = _scopedRows
        .where(
          (r) => const [
            'data_review',
            'pending',
            'analysis_error',
          ].contains(r.status),
        )
        .length;
    _branches = _controller.rows.map((r) => r.branch).toSet().toList()
      ..sort(
        (a, b) => StoreBranchIdentityRegistry.displayName(
          a,
        ).compareTo(StoreBranchIdentityRegistry.displayName(b)),
      );
  }

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        MismatchReviewController(
          SupabaseMismatchReviewRepository(Supabase.instance.client),
        );
    _controller.start();
  }

  @override
  void dispose() {
    _search.dispose();
    _rowScroll.dispose();
    _columnScroll.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  List<MismatchReview> _scope() {
    return _controller.rows
        .where(
          (r) =>
              (_branch == 'ALL' || r.branch == _branch) &&
              r.matches(_search.text) &&
              _matchesReportDate(r),
        )
        .toList();
  }

  bool _matchesReportDate(MismatchReview row) {
    final range = _reportRange;
    if (range == null) return true;
    final event = row.eventAt;
    if (event == null) return false;
    // Zoned timestamps are converted to the branch's UAE calendar date.
    final local = event.isUtc ? event.add(const Duration(hours: 4)) : event;
    final day = DateTime(local.year, local.month, local.day);
    return !day.isBefore(range.start) && !day.isAfter(range.end);
  }

  Future<void> _pickReportRange() async {
    final range = await showDialog<DateTimeRange>(
      context: context,
      builder: (_) => AppDateRangePickerDialog(
        initialRange: _reportRange,
        allowSingleDay: true,
      ),
    );
    if (range != null && mounted) {
      _filterChanged(
        () => _reportRange = DateTimeRange(
          start: DateUtils.dateOnly(range.start),
          end: DateUtils.dateOnly(range.end),
        ),
      );
    }
  }

  List<MismatchReview> _visible(List<MismatchReview> scope) {
    final result = scope
        .where(
          (r) =>
              _risk == 'all' ||
              (_risk == 'attention'
                  ? r.needsFollowup
                  : _risk == 'data'
                  ? [
                      'data_review',
                      'pending',
                      'analysis_error',
                    ].contains(r.status)
                  : r.status == _risk),
        )
        .toList();
    result.sort((a, b) {
      final rank = _recentFirst ? 0 : a.priority.compareTo(b.priority);
      return rank != 0
          ? rank
          : (b.eventAt ?? DateTime(1900)).compareTo(
              a.eventAt ?? DateTime(1900),
            );
    });
    return result;
  }

  void _filterChanged(VoidCallback change) => setState(() {
    change();
    _page = 0;
    if (_rowScroll.hasClients) _rowScroll.jumpTo(0);
  });

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => ValueListenableBuilder(
      valueListenable: StoreBranchIdentityRegistry.groups,
      builder: (context, _, _) => LayoutBuilder(
        builder: (context, box) {
          _project();
          final inset = box.maxWidth < 700 ? 16.0 : 26.0;
          return ColoredBox(
            color: const Color(0xFF003E4C),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(box.maxWidth),
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFF5FAFF),
                          Color(0xFFEDF5FD),
                          Color(0xFFF4F9FF),
                        ],
                      ),
                    ),
                    padding: EdgeInsets.fromLTRB(inset, 18, inset, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _metrics(_scopedRows, box.maxWidth),
                        const SizedBox(height: 24),
                        _filters(),
                        const SizedBox(height: 14),
                        if (_controller.error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _notice(
                              Icons.cloud_off_outlined,
                              _controller.error!,
                              const Color(0xFFB45309),
                            ),
                          ),
                        if (_controller.lastChangedId != null &&
                            _controller.lastChangedAt != null &&
                            DateTime.now()
                                    .difference(_controller.lastChangedAt!)
                                    .inMinutes <
                                2)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _activity(),
                          ),
                        Expanded(
                          child: _controller.loading
                              ? const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircularProgressIndicator(color: _teal),
                                      SizedBox(height: 16),
                                      Text(
                                        'Loading mismatch entries and stock history…',
                                      ),
                                    ],
                                  ),
                                )
                              : _table(_visibleRows),
                        ),
                        const SizedBox(height: 12),
                        _pagination(_visibleRows.length),
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
  );

  Widget _header(double width) {
    final compact = width < 850;
    final title = Row(
      children: [
        Container(
          width: compact ? 58 : 74,
          height: compact ? 58 : 74,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: const Color(0xFF1396A5)),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF08899B), Color(0xFF006071)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x18001F2C),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: MismatchCubeIcon(
              color: Colors.white,
              size: compact ? 34 : 43,
            ),
          ),
        ),
        const SizedBox(width: 22),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'INVENTORY / RECONCILIATION',
                style: TextStyle(
                  color: Color(0xFFD2F3F8),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Mismatch Report',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 26 : 32,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Every mismatch has a story. Follow the stock, then decide what needs attention.',
                style: TextStyle(
                  color: Color(0xFFECFAFF),
                  fontSize: 14,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final coverage = Container(
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 11),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF28CDD4), width: 1.3),
        borderRadius: BorderRadius.circular(13),
        color: const Color(0x30004D5B),
        boxShadow: const [
          BoxShadow(color: Color(0x2200E9E0), blurRadius: 12, spreadRadius: -5),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.calendar_today_outlined,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              'Movement coverage · ${_coverageLabel()}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return MismatchHeaderBackdrop(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 20 : 38,
          vertical: 16,
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [title, const SizedBox(height: 14), coverage],
              )
            : Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 25),
                  coverage,
                ],
              ),
      ),
    );
  }

  Widget _metrics(List<MismatchReview> rows, double width) {
    final cards = [
      (
        'Active mismatch entries',
        rows.length,
        Icons.inventory_2_outlined,
        const Color(0xFF00518C),
        'all',
        const Color(0xFFEEF8FE),
        const Color(0xFFCFE7F5),
      ),
      (
        'Needs follow-up',
        _followups,
        Icons.outlined_flag_rounded,
        const Color(0xFFCA3207),
        'attention',
        const Color(0xFFFFF9F4),
        const Color(0xFFFFEAD9),
      ),
      (
        'Adjustments to review',
        _adjustmentReviews,
        Icons.tune_rounded,
        const Color(0xFF5E39B2),
        'adjustment_review',
        const Color(0xFFFAF6FF),
        const Color(0xFFE6DDFB),
      ),
      (
        'Evidence gaps',
        _evidenceGaps,
        Icons.fact_check_outlined,
        const Color(0xFF09666B),
        'data',
        const Color(0xFFF0FBFC),
        const Color(0xFFCFECEE),
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 880 ? 4 : 2;
        final gap = c.maxWidth < 700 ? 12.0 : 16.0;
        final cardWidth = (c.maxWidth - gap * (columns - 1)) / columns;
        final small = cardWidth < 250;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final x in cards)
              SizedBox(
                width: cardWidth,
                height: small ? 82 : 86,
                child: MismatchMetricCard(
                  key: ValueKey('mismatch-metric-${x.$5}'),
                  id: x.$5,
                  title: x.$1,
                  count: x.$2,
                  icon: x.$3,
                  color: x.$4,
                  background: [x.$6, x.$7],
                  small: small,
                  selected: _risk == x.$5 && _risk != 'all',
                  cube: x.$5 == 'all',
                  onTap: () => _filterChanged(() => _risk = x.$5),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _filters() => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 1120;
      final fieldWidth = (box.maxWidth - 16) / 2;
      final available = box.maxWidth - 80;
      return Wrap(
        spacing: wide ? 20 : 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: wide ? available * .400 : box.maxWidth,
            height: 52,
            child: TextField(
              controller: _search,
              onChanged: (_) => _filterChanged(() {}),
              style: const TextStyle(color: _ink, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search product, code or branch...',
                hintStyle: const TextStyle(
                  color: Color(0xFF3B5D80),
                  fontSize: 14,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 24,
                  color: _teal,
                ),
                filled: true,
                fillColor: const Color(0xFFEAF4FC),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                border: _filterBorder(),
                enabledBorder: _filterBorder(),
                focusedBorder: _filterBorder(focused: true),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _filterChanged(_search.clear),
                      ),
              ),
            ),
          ),
          SizedBox(
            width: wide ? available * .182 : fieldWidth,
            height: 52,
            child: TrackerBranchDropdown(
              value: _branch,
              items: ['ALL', ..._branches],
              height: 52,
              accentColor: const Color(0xFF008DAA),
              label: 'Branch',
              plainIcon: true,
              onChanged: (value) => _filterChanged(() => _branch = value),
            ),
          ),
          SizedBox(
            width: wide ? available * .183 : fieldWidth,
            height: 52,
            child: _reportDateFilter(),
          ),
          SizedBox(
            width: wide ? available * .131 : math.min(180, fieldWidth),
            height: 52,
            child: OutlinedButton(
              onPressed: () =>
                  _filterChanged(() => _recentFirst = !_recentFirst),
              style: OutlinedButton.styleFrom(
                foregroundColor: _ink,
                backgroundColor: const Color(0xFFF6FAFF),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                side: const BorderSide(color: _line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _recentFirst ? Icons.schedule_rounded : Icons.sort_rounded,
                    size: 22,
                    color: _teal,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _recentFirst ? 'Newest first' : 'Priority first',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 21,
                    color: _teal,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: wide ? available * .104 : math.min(150, fieldWidth),
            height: 52,
            child: PopupMenuButton<String>(
              enabled: !_exporting && !widget.exportInProgress,
              onSelected: (value) async {
                if (value == 'legacy') {
                  widget.onLegacyExport?.call(_branch, _search.text);
                  return;
                }
                setState(() => _exporting = true);
                try {
                  await MismatchReviewExporter.export(
                    _visibleRows.map((r) => r.exportRow()).toList(),
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('$e')));
                  }
                } finally {
                  if (mounted) setState(() => _exporting = false);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'review',
                  child: Text('Export visible reviews · Excel'),
                ),
                if (widget.onLegacyExport != null)
                  const PopupMenuItem(
                    value: 'legacy',
                    child: Text('Original records / history · Excel'),
                  ),
              ],
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: const Color(0xFF087B89)),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF006C7A), Color(0xFF004652)],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x10004E5E),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _exporting || widget.exportInProgress
                          ? Icons.hourglass_top
                          : Icons.file_download_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Export',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  OutlineInputBorder _filterBorder({bool focused = false}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(
          color: focused ? _teal : _line,
          width: focused ? 1.5 : 1.2,
        ),
      );

  Widget _table(List<MismatchReview> rows) {
    final start = _page * _pageSize;
    final pageRows = rows.skip(start).take(_pageSize).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 57,
          child: Row(
            children: [
              const Icon(
                Icons.view_list_outlined,
                size: 25,
                color: Color(0xFF003E52),
              ),
              const SizedBox(width: 12),
              const Text(
                'Review Queue',
                style: TextStyle(
                  fontSize: 21,
                  color: _ink,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
              const Spacer(),
              Text(
                '${NumberFormat.decimalPattern().format(rows.length)} records',
                style: const TextStyle(fontSize: 14, color: Color(0xFF3B5D80)),
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFF9FCFF),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: _line),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x09004669),
                  blurRadius: 18,
                  offset: Offset(0, 7),
                ),
              ],
            ),
            child: rows.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.filter_alt_off_outlined,
                          size: 40,
                          color: _muted,
                        ),
                        const SizedBox(height: 12),
                        const Text('No mismatch entries match these filters'),
                        TextButton(
                          onPressed: () => _filterChanged(() {
                            _branch = 'ALL';
                            _risk = 'all';
                            _reportRange = null;
                            _search.clear();
                          }),
                          child: const Text('Clear filters'),
                        ),
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, b) => Scrollbar(
                      controller: _columnScroll,
                      thumbVisibility: b.maxWidth < 1390,
                      notificationPredicate: (notification) =>
                          notification.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: _columnScroll,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: math.max(b.maxWidth, 1390),
                          child: Column(
                            children: [
                              Container(
                                height: 45,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF107987),
                                      Color(0xFF005563),
                                      Color(0xFF004858),
                                    ],
                                  ),
                                ),
                                child: _columns([
                                  _column('#'),
                                  _column('Product'),
                                  _column('Branch', Icons.storefront_outlined),
                                  _column('System Qty'),
                                  _column('Actual Qty'),
                                  _column('Difference'),
                                  _column('Review', Icons.chat_outlined),
                                  _column(
                                    'Latest Incoming',
                                    Icons.local_shipping_outlined,
                                  ),
                                  _column(
                                    'Report Date',
                                    Icons.calendar_today_outlined,
                                  ),
                                  const SizedBox(),
                                ], header: true),
                              ),
                              Expanded(
                                child: ListView.builder(
                                  controller: _rowScroll,
                                  itemCount: pageRows.length,
                                  itemExtent: 52,
                                  itemBuilder: (context, i) =>
                                      _tableRow(pageRows[i], start + i),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _column(String label, [IconData? icon]) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 9),
      ],
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );

  Widget _columns(List<Widget> cells, {bool header = false}) {
    Widget cell(int i) => Container(
      height: double.infinity,
      alignment: i == 0 || i == 3 || i == 4 || i == 5 || i == 9
          ? Alignment.center
          : Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: i == 0 || i == 9 ? 5 : 12),
      decoration: header
          ? BoxDecoration(
              border: Border(
                right: BorderSide(color: Colors.white.withValues(alpha: .09)),
              ),
            )
          : null,
      child: cells[i],
    );
    return Row(
      children: [
        SizedBox(width: 54, child: cell(0)),
        Expanded(flex: 6, child: cell(1)),
        Expanded(flex: 3, child: cell(2)),
        SizedBox(width: 100, child: cell(3)),
        SizedBox(width: 100, child: cell(4)),
        SizedBox(width: 106, child: cell(5)),
        Expanded(flex: 4, child: cell(6)),
        Expanded(flex: 3, child: cell(7)),
        SizedBox(width: 143, child: cell(8)),
        SizedBox(width: 49, child: cell(9)),
      ],
    );
  }

  Widget _tableRow(MismatchReview r, int index) => Material(
    color: index.isEven ? const Color(0xFFF7FAFE) : const Color(0xFFF0F5FB),
    child: InkWell(
      onTap: () => _open(r),
      hoverColor: const Color(0xFFE4F3F8),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE0EAF4))),
        ),
        child: SelectionArea(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _open(r),
            child: _columns([
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1EAF6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r.code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF46617E),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDF2F9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: Color(0xFF005068),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          StoreBranchIdentityRegistry.displayName(r.branch),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                _n(r.raw['system_stock']),
                key: ValueKey('mismatch-system-qty-${r.id}'),
                style: const TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                _n(r.raw['actual_stock']),
                key: ValueKey('mismatch-actual-qty-${r.id}'),
                style: const TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: r.number('diff') < 0
                      ? const Color(0xFFFFE4E8)
                      : const Color(0xFFDEF3F1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Diff ${_n(r.raw['diff'], signed: true)}',
                  maxLines: 1,
                  style: TextStyle(
                    color: r.number('diff') < 0
                        ? const Color(0xFFD50018)
                        : _teal,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: ReviewBadge(status: r.status),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.stale
                        ? '—'
                        : 'Qty ${_n(r.analysis['receipt_qty'])} · ${_date(r.analysis['last_receipt'])}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _ink, fontSize: 13),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    (r.analysis['receipt_types'] as List? ?? []).join(', '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF46617E),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(
                    Icons.calendar_month_outlined,
                    size: 19,
                    color: Color(0xFF006074),
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      _date(r.eventAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _ink, fontSize: 13),
                    ),
                  ),
                ],
              ),
              Container(
                width: 33,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FBFF),
                  border: Border.all(color: const Color(0xFFD2E1F0)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF00517A),
                  size: 25,
                ),
              ),
            ]),
          ),
        ),
      ),
    ),
  );

  void _goToPage(int page) => setState(() {
    _page = page;
    if (_rowScroll.hasClients) _rowScroll.jumpTo(0);
  });

  Widget _pagination(int total) => LayoutBuilder(
    builder: (context, box) {
      final pages = math.max(1, (total / _pageSize).ceil());
      final from = total == 0 ? 0 : _page * _pageSize + 1;
      final to = math.min(total, (_page + 1) * _pageSize);
      final label = Text(
        'Showing ${_n(from)} – ${_n(to)} of ${_n(total)} records',
        style: const TextStyle(color: Color(0xFF3B5D80), fontSize: 13),
      );
      final sizePicker = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Rows per page:',
            style: TextStyle(color: Color(0xFF3B5D80), fontSize: 13),
          ),
          const SizedBox(width: 12),
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FCFF),
              border: Border.all(color: _line),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                key: const ValueKey('mismatch-page-size'),
                value: _pageSize,
                isDense: true,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: _ink,
                  size: 20,
                ),
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: _ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                items: [25, 50, 100]
                    .map(
                      (size) =>
                          DropdownMenuItem(value: size, child: Text('$size')),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) _filterChanged(() => _pageSize = value);
                },
              ),
            ),
          ),
        ],
      );
      final buttons = box.maxWidth < 500 ? 3 : 5;
      final first = math.max(
        0,
        math.min(_page - buttons ~/ 2, pages - buttons),
      );
      final numbered = List.generate(
        math.min(pages, buttons),
        (i) => first + i,
      );
      final controls = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pageButton(
            icon: Icons.keyboard_double_arrow_left_rounded,
            tooltip: 'First page',
            onTap: _page == 0 ? null : () => _goToPage(0),
          ),
          if (first > 0)
            _pageButton(
              icon: Icons.chevron_left_rounded,
              tooltip: 'Previous page',
              onTap: () => _goToPage(_page - 1),
            ),
          for (final page in numbered)
            _pageButton(
              text: '${page + 1}',
              selected: page == _page,
              tooltip: 'Page ${page + 1}',
              onTap: () => _goToPage(page),
            ),
          if (box.maxWidth >= 500 && numbered.last < pages - 1) ...[
            const SizedBox(
              width: 28,
              child: Center(
                child: Text('...', style: TextStyle(color: _ink)),
              ),
            ),
            _pageButton(
              text: '$pages',
              tooltip: 'Page $pages',
              onTap: () => _goToPage(pages - 1),
            ),
          ],
          _pageButton(
            icon: Icons.chevron_right_rounded,
            tooltip: 'Next page',
            onTap: _page >= pages - 1 ? null : () => _goToPage(_page + 1),
          ),
        ],
      );
      if (box.maxWidth >= 1050) {
        return SizedBox(
          height: 64,
          child: Row(
            children: [
              Expanded(child: label),
              sizePicker,
              const SizedBox(width: 26),
              controls,
            ],
          ),
        );
      }
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 14,
        runSpacing: 10,
        children: [label, sizePicker, controls],
      );
    },
  );

  Widget _pageButton({
    String? text,
    IconData? icon,
    required String tooltip,
    bool selected = false,
    VoidCallback? onTap,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? const Color(0xFF00616E) : const Color(0xFFF6FAFF),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 35,
            height: 35,
            alignment: Alignment.center,
            decoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF007B88), Color(0xFF004B58)],
                    ),
                  )
                : null,
            child: icon != null
                ? Icon(
                    icon,
                    size: 23,
                    color: onTap == null
                        ? const Color(0xFF9DC5D8)
                        : const Color(0xFF00567A),
                  )
                : Text(
                    text!,
                    style: TextStyle(
                      color: selected ? Colors.white : _ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    ),
  );

  String _coverageLabel() {
    if (_controller.coverage.isEmpty) return 'Not available';
    final companies = _controller.coverage
        .map((e) => '${e['company']}')
        .toSet();
    final ends = <DateTime>[];
    for (final company in companies) {
      var end = DateTime(2025, 12, 31);
      final periods =
          _controller.coverage.where((e) => e['company'] == company).toList()
            ..sort(
              (a, b) => '${a['from_date']}'.compareTo('${b['from_date']}'),
            );
      for (final p in periods) {
        final from = DateTime.parse('${p['from_date']}'),
            to = DateTime.parse('${p['to_date']}');
        if (p['complete'] == true &&
            p['expected_rows'] == p['committed_rows'] &&
            !from.isAfter(end.add(const Duration(days: 1)))) {
          if (to.isAfter(end)) end = to;
        }
      }
      ends.add(end);
    }
    ends.sort();
    return DateFormat('dd MMM yyyy').format(ends.first);
  }

  Widget _reportDateFilter() {
    final range = _reportRange;
    final format = DateFormat('dd MMM yy');
    final label = range == null
        ? 'Choose dates'
        : DateUtils.isSameDay(range.start, range.end)
        ? format.format(range.start)
        : '${format.format(range.start)} – ${format.format(range.end)}';
    return Material(
      color: const Color(0xFFF5FAFD),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('mismatch-report-date-range'),
        onTap: _pickReportRange,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.date_range_rounded, size: 21, color: _teal),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Report Dates',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (range != null)
                IconButton(
                  tooltip: 'Clear report dates',
                  onPressed: () => _filterChanged(() => _reportRange = null),
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 32,
                  ),
                  padding: const EdgeInsets.all(4),
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: _muted,
                  ),
                )
              else
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: _teal,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activity() {
    final row = _controller.rows
        .where((r) => r.id == _controller.lastChangedId)
        .firstOrNull;
    return Material(
      color: const Color(0xFFEAF6F5),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: row == null ? null : () => _open(row),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.bolt_rounded, color: _teal, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  row == null
                      ? 'A mismatch was removed. Report updated.'
                      : 'Mismatch updated · ${StoreBranchIdentityRegistry.displayName(row.branch)} · ${row.code} · ${reviewTitle(row.status)}',
                  style: const TextStyle(
                    color: _teal,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (row != null)
                const Icon(Icons.arrow_forward_rounded, size: 16, color: _teal),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(MismatchReview row) async {
    await showDialog<void>(
      context: context,
      barrierColor: const Color(0x8800192C),
      builder: (_) => BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
        child: Dialog(
          alignment: const Alignment(0, -.7),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shadowColor: const Color(0x9900172B),
          elevation: 28,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          insetPadding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 700 ? 10 : 28,
          ),
          clipBehavior: Clip.antiAlias,
          child: SelectionArea(
            child: SizedBox(
              width: 1028,
              height: math.min(900, MediaQuery.sizeOf(context).height - 86),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final current = _controller.rows
                      .where((r) => r.id == row.id)
                      .firstOrNull;
                  return current == null
                      ? const Center(
                          child: Text('This mismatch is no longer active.'),
                        )
                      : ValueListenableBuilder(
                          valueListenable: StoreBranchIdentityRegistry.groups,
                          builder: (context, _, _) => MismatchReviewDetail(
                            row: current,
                            controller: _controller,
                            revision: _controller.revision,
                            onClose: () => Navigator.pop(context),
                          ),
                        );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _columnStyle = TextStyle(
  fontSize: 10,
  fontWeight: FontWeight.w700,
  color: _muted,
  letterSpacing: .6,
);
Color reviewColor(String status) => switch (status) {
  'priority_followup' => const Color(0xFFCC071B),
  'recent_receipt_followup' => const Color(0xFFA56512),
  'adjustment_review' => const Color(0xFF6B43B4),
  'data_review' || 'pending' || 'analysis_error' => _teal,
  _ => _muted,
};

class ReviewBadge extends StatelessWidget {
  const ReviewBadge({super.key, required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = reviewColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: status == 'priority_followup'
            ? const Color(0xFFFFE6E9)
            : color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: status == 'priority_followup'
              ? const Color(0xFFFFBAC3)
              : color.withValues(alpha: .18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            switch (status) {
              'priority_followup' ||
              'recent_receipt_followup' => Icons.outlined_flag_rounded,
              'adjustment_review' => Icons.tune_rounded,
              'resolved' => Icons.check_circle_outline_rounded,
              _ => Icons.fact_check_outlined,
            },
            size: 16,
            color: color,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              reviewTitle(status),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

String _n(dynamic value, {bool signed = false}) {
  if (value == null) return '—';
  final v = num.tryParse('$value');
  if (v == null) return '$value';
  return '${signed && v > 0 ? '+' : ''}${NumberFormat('#,##0.###').format(v)}';
}

String _date(dynamic value) {
  final date = value is DateTime ? value : DateTime.tryParse('$value');
  return date == null ? '—' : DateFormat('dd MMM yy').format(date);
}

String _reportEventLabel(Map<String, dynamic> analysis) =>
    switch (analysis['event_action']) {
      'update' => 'Updated in mismatch report',
      'add' => 'Added to mismatch report',
      _ => 'Mismatch report entry',
    };

String _movementName(Map row) {
  final raw = '${row['trans_type'] ?? 'Unknown'}';
  final positive = MismatchStockJourney.quantity(row) > 0;
  final label = switch (MismatchStockJourney.type(row)) {
    'pos' || 'posdvn' =>
      positive ? 'Positive sale-type entry · review' : 'Sold to customer',
    'stocktransferfrom' =>
      positive
          ? 'Positive outgoing-transfer entry · review'
          : 'Transferred out of branch',
    'stocktransferto' =>
      positive
          ? 'Received by branch transfer'
          : 'Negative incoming-transfer entry · review',
    'returnpos' => 'Customer return',
    'invadjustment' => 'Stock correction',
    'invbatchreplacement' => 'Batch replacement',
    _ => positive ? 'Other stock received' : 'Other stock removed',
  };
  return '$label · $raw';
}

Widget _notice(IconData icon, String message, Color color) => Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: color.withValues(alpha: .07),
    borderRadius: BorderRadius.circular(10),
  ),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: color, size: 17),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          message,
          style: TextStyle(color: color, fontSize: 12, height: 1.6),
        ),
      ),
    ],
  ),
);

class MismatchReviewDetail extends StatefulWidget {
  const MismatchReviewDetail({
    super.key,
    required this.row,
    required this.controller,
    required this.revision,
    required this.onClose,
  });
  final MismatchReview row;
  final MismatchReviewController controller;
  final int revision;
  final VoidCallback onClose;
  @override
  State<MismatchReviewDetail> createState() => _MismatchReviewDetailState();
}

class _MismatchReviewDetailState extends State<MismatchReviewDetail> {
  Map<String, dynamic>? _data;
  MismatchStockJourney? _journey;
  String? _loadedKey;
  String? _error;
  int _generation = 0;
  bool _loading = true;
  @override
  void initState() {
    super.initState();
    _loadedKey = widget.controller.detailKey(widget.row);
    final cached = widget.controller.cachedDetail(widget.row);
    if (cached != null) {
      _accept(cached);
      _loading = false;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  void _accept(Map<String, dynamic>? result) {
    _data = result;
    _journey = result == null
        ? null
        : MismatchStockJourney(
            Map<String, dynamic>.from(
              result['analysis'] as Map? ?? widget.row.analysis,
            ),
            Map<String, dynamic>.from(result['evidence'] as Map? ?? {}),
          );
  }

  @override
  void didUpdateWidget(covariant MismatchReviewDetail old) {
    super.didUpdateWidget(old);
    if (_loadedKey != widget.controller.detailKey(widget.row)) {
      _load();
    }
  }

  Future<void> _load() async {
    final token = ++_generation;
    _loadedKey = widget.controller.detailKey(widget.row);
    setState(() {
      _loading = true;
      _error = null;
      _accept(null);
    });
    try {
      final result = await widget.controller.detail(widget.row);
      if (!mounted || token != _generation) return;
      setState(() {
        _accept(result);
        _loading = false;
        if (result == null) _error = 'This mismatch is no longer active.';
      });
    } catch (_) {
      if (mounted && token == _generation) {
        setState(() {
          _loading = false;
          _error = 'Could not load movement evidence. Retry the review.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final a = Map<String, dynamic>.from(
      _data?['analysis'] as Map? ?? row.analysis,
    );
    final evidence = Map<String, dynamic>.from(
      _data?['evidence'] as Map? ?? {},
    );
    final status = _error != null
        ? 'analysis_error'
        : '${a['status'] ?? 'pending'}';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _detailHeader(row, a, status),
          const Divider(height: 1, color: _line),
          Expanded(
            child: _loading
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Received qty ${_n(a['receipt_qty'])} · ${_date(a['last_receipt'])}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const SizedBox(
                        width: 220,
                        child: LinearProgressIndicator(),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Loading sales, transfers and stock corrections…',
                        style: TextStyle(color: _muted),
                      ),
                    ],
                  )
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : DefaultTabController(
                    length: 4,
                    child: Builder(
                      builder: (context) => Column(
                        children: [
                          DecoratedBox(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFFF8FBFF), Color(0xFFEEF5FC)],
                              ),
                            ),
                            child: TabBar(
                              isScrollable: true,
                              tabAlignment: TabAlignment.start,
                              labelColor: _teal,
                              unselectedLabelColor: const Color(0xFF35547B),
                              dividerColor: _line,
                              indicatorWeight: 4,
                              indicatorSize: TabBarIndicatorSize.tab,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              labelPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              indicatorColor: _teal,
                              labelStyle: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                              tabs: [
                                const Tab(text: 'Case summary'),
                                const Tab(text: 'Movements'),
                                Tab(
                                  text:
                                      'Stock corrections (${_journey!.adjustments.length})',
                                ),
                                const Tab(text: 'Mismatch history'),
                              ],
                            ),
                          ),
                          Expanded(
                            child: AnimatedBuilder(
                              animation: DefaultTabController.of(context),
                              builder: (context, _) =>
                                  switch (DefaultTabController.of(
                                    context,
                                  ).index) {
                                    1 => _movements(evidence),
                                    2 => _adjustments(a, evidence),
                                    3 => _history(evidence),
                                    _ => _decision(a, status, evidence),
                                  },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _detailHeader(
    MismatchReview row,
    Map<String, dynamic> analysis,
    String status,
  ) => ClipRRect(
    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(19)),
    child: MismatchHeaderBackdrop(
      modal: true,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(34, 18, 44, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MISMATCH REVIEW',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .4,
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.storefront_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        StoreBranchIdentityRegistry.displayName(row.branch),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, box) {
                    final title = Text(
                      row.name,
                      key: const ValueKey('mismatch-detail-product'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    );
                    final badge = DecoratedBox(
                      key: const ValueKey('mismatch-detail-review-badge'),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ReviewBadge(status: status),
                    );
                    return box.maxWidth >= 560
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Flexible(child: title),
                              const SizedBox(width: 16),
                              badge,
                            ],
                          )
                        : Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [title, badge],
                          );
                  },
                ),
                const SizedBox(height: 5),
                SelectableText(
                  '${row.code}  ·  ${_reportEventLabel(analysis)}: ${_date(analysis['event_at'])}',
                  style: const TextStyle(
                    color: Color(0xFFF1FAFF),
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 14,
            right: 16,
            child: IconButton(
              tooltip: 'Close review',
              onPressed: widget.onClose,
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 23,
              ),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _decision(
    Map<String, dynamic> a,
    String status,
    Map<String, dynamic> evidence,
  ) {
    final issues = (a['issues'] as List? ?? [])
        .map((e) => reviewIssue('$e'))
        .toList();
    final returns = (a['receipt_types'] as List? ?? []).contains('ReturnPOS');
    final journey = _journey!;
    final adjustments = journey.adjustments;
    final lastAdj = adjustments.lastOrNull;
    final movementTitle = journey.receiptDay == null
        ? 'No incoming checkpoint'
        : journey.laterMovements.isNotEmpty
        ? '${journey.laterMovements.length} later movements'
        : journey.noLaterMovementEstablished
        ? 'No later movement'
        : 'No later rows in archive';
    return LayoutBuilder(
      builder: (context, box) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
        children: [
          _caseStory(a, journey, status),
          const SizedBox(height: 12),
          _notice(
            widget.row.needsFollowup
                ? Icons.flag_outlined
                : Icons.info_outline_rounded,
            reviewRecommendation(status, customerReturn: returns),
            reviewColor(status),
          ),
          const SizedBox(height: 14),
          const Text(
            'Stock Movement Timeline',
            style: TextStyle(
              color: _ink,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'From stock received to mismatch report.',
            style: TextStyle(color: _muted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          _journeyCards(box.maxWidth, [
            _journeyCard(
              '01',
              'Last date system stock was zero',
              a['last_zero'] == null
                  ? 'No zero stock date found'
                  : _date(a['last_zero']),
              a['last_zero'] == null
                  ? 'The available history does not show a day when system stock was 0.'
                  : 'System stock = 0 qty',
              Icons.restart_alt_rounded,
              _teal,
            ),
            _journeyCard(
              '02',
              returns
                  ? 'Last stock received · customer return'
                  : 'Last stock received',
              _date(a['last_receipt']),
              a['last_receipt'] == null
                  ? 'No stock received before this report entry.'
                  : '+${_n(a['receipt_qty'])} qty\n${(a['receipt_types'] as List? ?? []).join(', ')}',
              Icons.check_rounded,
              _teal,
            ),
            _journeyCard(
              '03',
              'Sales and transfers after receipt',
              movementTitle,
              journey.receiptDay == null
                  ? 'Cannot define the comparison period.'
                  : 'Sold ${_n(journey.sold)} · Transferred ${_n(journey.transferredOut)}'
                        '${journey.otherOut == 0 ? '' : '\nOther outgoing ${_n(journey.otherOut)}'}'
                        '${journey.laterAdjustments == 0 ? '' : '\nStock corrections ${journey.laterAdjustments}'}'
                        '${journey.laterMovements.isEmpty ? '' : '\nLast: ${_date(journey.laterMovements.last['trans_date'])}'}',
              journey.noLaterMovementEstablished
                  ? Icons.pause_circle_outline
                  : Icons.swap_horiz_rounded,
              journey.noLaterMovementEstablished ? reviewColor(status) : _ink,
            ),
            _journeyCard(
              '04',
              _reportEventLabel(a),
              '${_date(a['event_at'])}${journey.daysToCount != null && journey.daysToCount! >= 0 ? '\nAfter ${journey.elapsedEnglish}' : ''}',
              'System Qty ${_n(widget.row.raw['system_stock'])} · Actual Qty ${_n(widget.row.raw['actual_stock'])}\nDifference ${_n(widget.row.raw['diff'], signed: true)}',
              Icons.fact_check_outlined,
              reviewColor(status),
            ),
          ]),
          if (journey.receiptDayOtherMovements.isNotEmpty ||
              !journey.coverageComplete) ...[
            const SizedBox(height: 12),
            _notice(
              Icons.schedule_rounded,
              '${journey.receiptDayOtherMovements.isNotEmpty ? '${journey.receiptDayOtherMovements.length} other movements occurred on the incoming day; their order relative to the receipt is unknown. ' : ''}'
              '${!journey.coverageComplete ? 'Archive coverage is incomplete. Missing rows do not establish that no movement occurred.' : ''}',
              const Color(0xFFA56512),
            ),
          ],
          const SizedBox(height: 20),
          if (adjustments.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F2FC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2D8F1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.tune_rounded,
                        color: Color(0xFF7561AC),
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              adjustments.isEmpty
                                  ? 'No INVAdjustment found in available history'
                                  : 'Previously adjusted · ${adjustments.length} INVAdjustment entries',
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              lastAdj == null
                                  ? 'Checked 1-1-2026 through the report date. History before 2026 is unavailable.'
                                  : 'Latest: ${_date(lastAdj['trans_date'])}  ·  Qty ${_n(MismatchStockJourney.quantity(lastAdj), signed: true)}  ·  Adj No ${lastAdj['trans_no'] ?? '—'}\n${journey.adjustmentTiming(lastAdj)}',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 13,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (adjustments.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: TextButton.icon(
                        onPressed: () =>
                            DefaultTabController.of(context).animateTo(2),
                        icon: const Icon(Icons.history_rounded, size: 18),
                        label: const Text('View all previous adjustments'),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          const Text(
            'EXPECTED STOCK AND PREVIOUS SHORTAGE',
            style: _columnStyle,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: box.maxWidth >= 950
                    ? (box.maxWidth - 84) / 4
                    : (box.maxWidth - 60) / 2,
                child: _value('1-1-2026 stock', a['baseline_qty']),
              ),
              SizedBox(
                width: box.maxWidth >= 950
                    ? (box.maxWidth - 84) / 4
                    : (box.maxWidth - 60) / 2,
                child: _value(
                  'Expected system stock',
                  a['reconstructed_before'],
                ),
              ),
              SizedBox(
                width: box.maxWidth >= 950
                    ? (box.maxWidth - 84) / 4
                    : (box.maxWidth - 60) / 2,
                child: _value('Older shortage', a['old_shortage']),
              ),
              SizedBox(
                width: box.maxWidth >= 950
                    ? (box.maxWidth - 84) / 4
                    : (box.maxWidth - 60) / 2,
                child: _value('Additional shortage', a['added_shortage']),
              ),
            ],
          ),
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 7),
            const Text('EVIDENCE TO RESOLVE', style: _columnStyle),
            const SizedBox(height: 8),
            ...issues.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _notice(Icons.help_outline_rounded, s, _teal),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _journeyCards(double width, List<Widget> cards) {
    final columns = width >= 950
        ? 4
        : width >= 650
        ? 2
        : 1;
    return Column(
      children: [
        for (var index = 0; index < cards.length; index += columns) ...[
          if (index > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (
                  var column = 0;
                  column < columns && index + column < cards.length;
                  column++
                ) ...[
                  if (column > 0) const SizedBox(width: 12),
                  Expanded(child: cards[index + column]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _journeyCard(
    String step,
    String title,
    String headline,
    String body,
    IconData icon,
    Color color,
  ) {
    final displayBody = step == '04'
        ? ''
        : step == '02'
        ? body.split('\n').first
        : body;
    final headlineText = Text(
      headline,
      style: TextStyle(
        color: color,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        height: 1.15,
        letterSpacing: -.3,
      ),
    );
    return Tooltip(
      message: '$title\n$headline\n$body',
      child: Container(
        constraints: const BoxConstraints(minHeight: 146),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(Colors.white, color, .025)!,
              Color.lerp(Colors.white, color, .10)!,
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 23),
                const Spacer(),
                Text(
                  step,
                  style: TextStyle(
                    color: color.withValues(alpha: .5),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              title,
              style: const TextStyle(
                color: _ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            if (headline == 'No later movement')
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: headlineText,
              )
            else
              headlineText,
            if (displayBody.isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(
                displayBody,
                style: const TextStyle(color: _ink, fontSize: 13, height: 1.35),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _caseStory(
    Map<String, dynamic> a,
    MismatchStockJourney j,
    String status,
  ) {
    final actual = num.tryParse('${widget.row.raw['actual_stock']}');
    final expected = j.expectedBeforeCount;
    final shortage = expected == null || actual == null
        ? null
        : expected - actual;
    final received = num.tryParse('${a['receipt_qty']}');
    final reliable = j.canCompareCount && actual != null;
    final color = !reliable
        ? _teal
        : shortage != null && shortage > 0
        ? (widget.row.needsFollowup
              ? reviewColor(status)
              : const Color(0xFFA56512))
        : _teal;
    String storyDate(dynamic value) {
      final d = MismatchStockJourney.day(value);
      return d == null ? 'Unknown date' : DateFormat('dd MMM yyyy').format(d);
    }

    String qty(num? value) =>
        value == null ? 'Unknown qty' : 'Qty ${_n(value)}';

    final receiptDate = storyDate(a['last_receipt']);
    final countDate = storyDate(a['event_at']);
    final facts = <String>[
      if (j.sold > 0) 'Sold ${qty(j.sold)}',
      if (j.transferredOut > 0)
        'Transferred ${qty(j.transferredOut)} out of the branch',
      if (j.otherOut > 0) 'Other stock removed: ${qty(j.otherOut)}',
      if (j.otherIn > 0) 'Other stock received: ${qty(j.otherIn)}',
      if (j.beforeCountMovements.any(MismatchStockJourney.isAdjustment))
        'Stock corrections: total qty ${_n(j.adjustmentNet, signed: true)}',
    ];
    final lead = j.receiptDay == null
        ? 'No stock received is recorded before this report entry. We cannot link the difference to a recent receipt.'
        : 'Received ${qty(received)} on $receiptDate. '
              'The branch reported the difference ${j.elapsedEnglish} later, on $countDate.';
    final previous = j.stockBeforeReceipt == null
        ? 'Stock before the receipt day is unknown. Unknown does not mean zero.'
        : 'System stock before the receipt day: ${qty(j.stockBeforeReceipt)}.';
    final movements = j.receiptDay == null
        ? ''
        : facts.isEmpty
        ? (j.coverageComplete
              ? 'No sales or transfers were recorded after the receipt day and before the report day.'
              : 'No later movements appear in the available history, but some dates are missing.')
        : 'After the receipt day and before the report day: ${facts.join('; ')}.';
    final outcome = expected == null || actual == null
        ? 'There is not enough data to calculate the expected stock and compare it with the branch stock.'
        : 'Expected system stock: ${qty(expected)}. Branch stock: ${qty(actual)}.';
    final older = num.tryParse('${a['old_shortage']}');
    final added = num.tryParse('${a['added_shortage']}');
    final verdict = !reliable
        ? 'Check the stock history before following up with the branch.'
        : shortage! > 0 && older != null && older >= shortage && added == 0
        ? 'This shortage was already reported and has not increased. Check the earlier report entry.'
        : shortage > 0
        ? 'Missing: ${qty(shortage)}. Check with the branch.'
        : shortage < 0
        ? 'Extra stock: ${qty(-shortage)}. Check the branch stock.'
        : 'The recorded movements explain the stock. No difference remains.';
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: status == 'priority_followup'
                ? [const Color(0xFFFFF5F7), const Color(0xFFFFEFF2)]
                : [
                    Color.lerp(Colors.white, color, .025)!,
                    Color.lerp(Colors.white, color, .065)!,
                  ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: status == 'priority_followup'
                ? const Color(0xFFFFBAC4)
                : color.withValues(alpha: .25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'What happened to this item?',
              style: TextStyle(
                color: _ink,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              lead,
              style: const TextStyle(
                color: _ink,
                fontSize: 16,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$previous\n$movements\n$outcome',
              style: const TextStyle(color: _ink, fontSize: 14, height: 1.45),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, box) {
                final columns = box.maxWidth >= 840
                    ? 6
                    : box.maxWidth >= 500
                    ? 3
                    : 2;
                final width = (box.maxWidth - (columns - 1) * 8) / columns;
                final facts = [
                  ('Received', received, _teal),
                  ('Sold after receipt', j.sold, _ink),
                  ('Transferred out', j.transferredOut, _ink),
                  ('Other stock removed', j.otherOut, _ink),
                  ('Expected system stock', expected, _teal),
                  ('Branch stock', actual, color),
                ];
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final fact in facts)
                      SizedBox(
                        width: width,
                        child: _storyNumber(fact.$1, fact.$2, fact.$3),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Text(
              verdict,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                height: 1.4,
              ),
            ),
            if (a['old_shortage'] != null && a['added_shortage'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  'Previously missing: ${qty(older)}. Additional missing in this report entry: ${qty(added)}.',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            if (j.receiptDayOtherMovements.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${j.receiptDayOtherMovements.length} other ${j.receiptDayOtherMovements.length == 1 ? 'movement was' : 'movements were'} recorded on the receipt day, changing stock by total qty ${_n(j.receiptDayOtherNet, signed: true)}. This is included in the stock calculation, but we do not know if it happened before or after the receipt.',
                  style: const TextStyle(
                    color: Color(0xFFA56512),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            if (j.countDayMovements.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${j.countDayMovements.length} ${j.countDayMovements.length == 1 ? 'movement was' : 'movements were'} recorded on the report day. This may have happened before or after the report entry. The sales and transfers above cover earlier days only.',
                  style: const TextStyle(
                    color: Color(0xFFA56512),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            if ((a['receipt_types'] as List? ?? []).contains('ReturnPOS'))
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'The latest stock received includes a customer return. Check the return document; it is not a new warehouse transfer.',
                  style: TextStyle(color: _muted, fontSize: 13, height: 1.4),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _storyNumber(String title, num? value, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    constraints: const BoxConstraints(minHeight: 80),
    decoration: BoxDecoration(
      color: const Color(0xFFFCFDFF),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 28,
          child: Text(
            title,
            maxLines: 2,
            style: const TextStyle(
              color: Color(0xFF35547B),
              fontSize: 11,
              height: 1.2,
            ),
          ),
        ),
        Text(
          _n(value),
          style: TextStyle(
            color: color,
            fontSize: 24,
            height: 1.1,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  Widget _value(String title, dynamic value) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F8FA),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 10, color: _muted)),
        const SizedBox(height: 5),
        Text(
          _n(value),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
      ],
    ),
  );
  Widget _lineValue(String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value.isEmpty ? '—' : value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: _ink,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
  Widget _adjustments(Map<String, dynamic> a, Map<String, dynamic> evidence) =>
      _movements(evidence, adjustmentsOnly: true, analysis: a);

  Widget _movements(
    Map<String, dynamic> evidence, {
    bool adjustmentsOnly = false,
    Map<String, dynamic>? analysis,
  }) {
    final rows = (evidence['movements'] as List? ?? [])
        .cast<Map>()
        .where((r) => !adjustmentsOnly || MismatchStockJourney.isAdjustment(r))
        .toList();
    final journey = analysis == null ? null : _journey;
    return rows.isEmpty
        ? Center(
            child: Text(
              adjustmentsOnly
                  ? 'No INVAdjustment found in available 2026 history.'
                  : 'No source movements for this item.',
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final r = rows[rows.length - 1 - index];
              final q = num.tryParse('${r['qty']}') ?? 0;
              final adj = MismatchStockJourney.isAdjustment(r);
              final color = adj
                  ? const Color(0xFF7561AC)
                  : q < 0
                  ? const Color(0xFFB5432E)
                  : _teal;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: adj ? color.withValues(alpha: .35) : _line,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          adj
                              ? Icons.tune_rounded
                              : q < 0
                              ? Icons.north_east_rounded
                              : Icons.south_west_rounded,
                          size: 17,
                          color: color,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _movementName(r),
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Text(
                          _n(q, signed: true),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_date(r['trans_date'])} · ${r['mode']}',
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (journey != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${journey.adjustmentTiming(r)} · ${q > 0
                              ? 'Stock increased'
                              : q < 0
                              ? 'Stock decreased'
                              : 'Zero quantity'}',
                          style: TextStyle(
                            color: color,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            'Adj No ${r['trans_no'] ?? '—'}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy adjustment number',
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: '${r['trans_no'] ?? ''}'),
                          ),
                          icon: const Icon(Icons.copy_outlined, size: 15),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
  }

  Widget _history(Map<String, dynamic> evidence) {
    final events = (evidence['events'] as List? ?? []).cast<Map>();
    return events.isEmpty
        ? const Center(child: Text('No logged mismatch history.'))
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            itemBuilder: (context, index) {
              final e = events[events.length - 1 - index];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F9FB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${e['action']}'.toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: _teal,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${e['changed_at']}'.replaceAll('T', ' '),
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                    const SizedBox(height: 10),
                    _lineValue(
                      'System',
                      '${_n(e['old_system_stock'])} → ${_n(e['new_system_stock'])}',
                    ),
                    _lineValue(
                      'Actual',
                      '${_n(e['old_actual_stock'])} → ${_n(e['new_actual_stock'])}',
                    ),
                    _lineValue(
                      'Difference',
                      '${_n(e['old_diff'])} → ${_n(e['new_diff'])}',
                    ),
                  ],
                ),
              );
            },
          );
  }
}
