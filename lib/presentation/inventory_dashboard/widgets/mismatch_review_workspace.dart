import 'dart:async';
import 'dart:math' as math;
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

const _ink = Color(0xFF122D40),
    _teal = Color(0xFF087F8C),
    _muted = Color(0xFF64748B),
    _line = Color(0xFFE3EAF0);

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
      setState(
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

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => ValueListenableBuilder(
      valueListenable: StoreBranchIdentityRegistry.groups,
      builder: (context, _, _) => LayoutBuilder(
        builder: (context, box) {
          _project();
          final scope = _scopedRows, visible = _visibleRows;
          return ColoredBox(
            color: const Color(0xFFF4F7FA),
            child: Padding(
              padding: EdgeInsets.all(box.maxWidth < 700 ? 12 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(box.maxWidth),
                  const SizedBox(height: 16),
                  _metrics(scope, box.maxWidth),
                  const SizedBox(height: 16),
                  _filters(),
                  const SizedBox(height: 12),
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
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text(
                                  'Loading mismatch entries and stock history…',
                                ),
                              ],
                            ),
                          )
                        : _table(visible),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${visible.length} shown · ${scope.length} in scope · ${_controller.rows.length} active records  |  Updated ${_controller.syncedAt == null ? '—' : DateFormat('HH:mm:ss').format(_controller.syncedAt!)}',
                    style: const TextStyle(fontSize: 11, color: _muted),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _header(double width) => Container(
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF122D40), Color(0xFF154B5C)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 20,
      runSpacing: 14,
      children: [
        SizedBox(
          width: math.min(width - 100, 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'INVENTORY / RECONCILIATION',
                style: TextStyle(
                  color: Color(0xFF8CCCD7),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Mismatch Report',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Every mismatch has a story. Follow the stock, then decide what needs attention.',
                style: TextStyle(color: Color(0xFFCCDDE5), fontSize: 13),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Movement coverage · ${_coverageLabel()}',
              style: const TextStyle(color: Color(0xFFCCDDE5), fontSize: 12),
            ),
          ],
        ),
      ],
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
          end = to;
        }
      }
      ends.add(end);
    }
    ends.sort();
    return DateFormat('dd MMM yyyy').format(ends.first);
  }

  Widget _metrics(List<MismatchReview> rows, double width) {
    final cards = [
      (
        'Active mismatch entries',
        rows.length,
        Icons.inventory_2_outlined,
        _ink,
        'all',
      ),
      (
        'Needs follow-up',
        _followups,
        Icons.flag_outlined,
        const Color(0xFFB45309),
        'attention',
      ),
      (
        'Adjustments to review',
        _adjustmentReviews,
        Icons.tune_rounded,
        const Color(0xFF6D5DAD),
        'adjustment_review',
      ),
      (
        'Evidence gaps',
        _evidenceGaps,
        Icons.fact_check_outlined,
        _teal,
        'data',
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cardWidth =
            (c.maxWidth - (c.maxWidth < 800 ? 12 : 36)) /
            (c.maxWidth < 800 ? 2 : 4);
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map(
                (x) => SizedBox(
                  width: cardWidth,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(15),
                      onTap: () => setState(() => _risk = x.$5),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _risk == x.$5
                                ? x.$4.withValues(alpha: .45)
                                : _line,
                          ),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                color: x.$4.withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(x.$3, color: x.$4, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${x.$2}',
                                    style: TextStyle(
                                      color: x.$4,
                                      fontSize: 25,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    x.$1,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: _muted,
                                    ),
                                    maxLines: 2,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _filters() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 1100;
          final fieldWidth = box.maxWidth >= 650
              ? (box.maxWidth - 12) / 2
              : box.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: wide ? box.maxWidth - 918 : box.maxWidth,
                height: 56,
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: _ink, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'SEARCH',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    labelStyle: const TextStyle(color: _muted, fontSize: 11),
                    hintText: 'Product, code or branch',
                    hintStyle: const TextStyle(color: _muted, fontSize: 13),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 21,
                      color: _teal,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF5FAFD),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 20,
                    ),
                    border: _filterBorder(),
                    enabledBorder: _filterBorder(),
                    focusedBorder: _filterBorder(focused: true),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 17),
                            onPressed: () => setState(_search.clear),
                          ),
                  ),
                ),
              ),
              SizedBox(
                width: wide ? 270 : fieldWidth,
                height: 56,
                child: TrackerBranchDropdown(
                  value: _branch,
                  items: ['ALL', ..._branches],
                  height: 56,
                  onChanged: (value) => setState(() => _branch = value),
                ),
              ),
              SizedBox(
                width: wide ? 300 : fieldWidth,
                height: 56,
                child: _reportDateFilter(),
              ),
              SizedBox(
                width: 160,
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _recentFirst = !_recentFirst),
                  icon: Icon(
                    _recentFirst ? Icons.schedule_rounded : Icons.sort_rounded,
                    size: 19,
                  ),
                  label: Text(_recentFirst ? 'Newest first' : 'Priority first'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: _line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 140,
                height: 56,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _ink,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _exporting || widget.exportInProgress
                              ? Icons.hourglass_top
                              : Icons.download_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 7),
                        const Text(
                          'Export',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
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
      ),
    );
  }

  OutlineInputBorder _filterBorder({bool focused = false}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: focused ? _teal : _line,
          width: focused ? 1.5 : 1,
        ),
      );

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
                      'REPORT DATES',
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
                  onPressed: () => setState(() => _reportRange = null),
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

  Widget _table(List<MismatchReview> rows) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _line),
      borderRadius: BorderRadius.circular(16),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.view_list_outlined, size: 19, color: _ink),
              const SizedBox(width: 8),
              const Text(
                'Review queue',
                style: TextStyle(fontWeight: FontWeight.w800, color: _ink),
              ),
              const Spacer(),
              Text(
                '${rows.length} records',
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: _line),
        Expanded(
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
                        onPressed: () => setState(() {
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
                  builder: (context, b) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: math.max(b.maxWidth, 1120),
                      child: Column(
                        children: [
                          Container(
                            color: const Color(0xFFF7F9FB),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: const Row(
                              children: [
                                Expanded(
                                  flex: 6,
                                  child: Text('PRODUCT', style: _columnStyle),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text('BRANCH', style: _columnStyle),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('STOCK', style: _columnStyle),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: Text('REVIEW', style: _columnStyle),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    'LATEST INCOMING',
                                    style: _columnStyle,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    'REPORT DATE',
                                    style: _columnStyle,
                                  ),
                                ),
                                SizedBox(width: 30),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: rows.length,
                              itemExtent: 88,
                              itemBuilder: (context, index) {
                                final r = rows[index];
                                return Material(
                                  color: r.needsFollowup
                                      ? (r.status == 'priority_followup'
                                            ? const Color(0xFFFFF0EB)
                                            : const Color(0xFFFFF8E8))
                                      : r.status == 'adjustment_review'
                                      ? const Color(0xFFF6F2FC)
                                      : Colors.white,
                                  child: InkWell(
                                    onTap: () => _open(r),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: const BorderSide(
                                            color: _line,
                                          ),
                                          left: BorderSide(
                                            width: 3,
                                            color: r.needsFollowup
                                                ? reviewColor(r.status)
                                                : Colors.transparent,
                                          ),
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 13,
                                        vertical: 12,
                                      ),
                                      child: SelectionArea(
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.translucent,
                                          onTap: () => _open(r),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: 6,
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 14,
                                                      ),
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Text(
                                                        r.name,
                                                        style: const TextStyle(
                                                          color: _ink,
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      const SizedBox(height: 5),
                                                      Text(
                                                        r.code,
                                                        style: const TextStyle(
                                                          color: _muted,
                                                          fontSize: 11,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 3,
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 12,
                                                      ),
                                                  child: Text(
                                                    StoreBranchIdentityRegistry.displayName(
                                                      r.branch,
                                                    ),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: _ink,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      '${_n(r.raw['system_stock'])} → ${_n(r.raw['actual_stock'])}',
                                                      style: const TextStyle(
                                                        color: _ink,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Diff ${_n(r.raw['diff'], signed: true)}',
                                                      style: TextStyle(
                                                        color:
                                                            r.number('diff') < 0
                                                            ? const Color(
                                                                0xFFBE4B35,
                                                              )
                                                            : _teal,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                flex: 4,
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: ReviewBadge(
                                                    status: r.status,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 3,
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      r.stale
                                                          ? '—'
                                                          : 'Qty ${_n(r.analysis['receipt_qty'])} · ${_date(r.analysis['last_receipt'])}',
                                                      style: const TextStyle(
                                                        color: _ink,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      (r.analysis['receipt_types']
                                                                  as List? ??
                                                              [])
                                                          .join(', '),
                                                      style: const TextStyle(
                                                        color: _muted,
                                                        fontSize: 10,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  _date(r.eventAt),
                                                  style: const TextStyle(
                                                    color: _muted,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(
                                                width: 30,
                                                child: Icon(
                                                  Icons.chevron_right_rounded,
                                                  color: _muted,
                                                  size: 19,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
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
                  ),
                ),
        ),
      ],
    ),
  );

  Future<void> _open(MismatchReview row) async {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 700 ? 10 : 28,
        ),
        clipBehavior: Clip.antiAlias,
        child: SelectionArea(
          child: SizedBox(
            width: 1320,
            height: MediaQuery.sizeOf(context).height - 56,
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
  'priority_followup' => const Color(0xFFB5432E),
  'recent_receipt_followup' => const Color(0xFFA56512),
  'adjustment_review' => const Color(0xFF7561AC),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .14)),
      ),
      child: Text(
        reviewTitle(status),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
          Container(
            color: const Color(0xFFF5F9FB),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('MISMATCH REVIEW', style: _columnStyle),
                    const Spacer(),
                    IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded, size: 19),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(
                      Icons.storefront_rounded,
                      color: _teal,
                      size: 22,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        StoreBranchIdentityRegistry.displayName(row.branch),
                        style: const TextStyle(
                          color: _teal,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  row.name,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 7),
                SelectableText(
                  '${row.code}  ·  ${_reportEventLabel(a)}: ${_date(a['event_at'])}',
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                ReviewBadge(status: status),
              ],
            ),
          ),
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
                          TabBar(
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            labelColor: _teal,
                            unselectedLabelColor: _muted,
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
        padding: const EdgeInsets.all(24),
        children: [
          _caseStory(a, journey, status),
          const SizedBox(height: 18),
          _notice(
            widget.row.needsFollowup
                ? Icons.flag_outlined
                : Icons.info_outline_rounded,
            reviewRecommendation(status, customerReturn: returns),
            reviewColor(status),
          ),
          const SizedBox(height: 22),
          const Text(
            'STOCK MOVEMENT TIMELINE',
            style: TextStyle(
              color: _ink,
              fontWeight: FontWeight.w800,
              fontSize: 17,
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
              Icons.south_west_rounded,
              _teal,
            ),
            _journeyCard(
              '03',
              'Sales and transfers after receipt',
              movementTitle,
              journey.receiptDay == null
                  ? 'Cannot define the comparison period.'
                  : 'Sold ${_n(journey.sold)} · Transferred ${_n(journey.transferredOut)}\nOther outgoing ${_n(journey.otherOut)}\nStock corrections ${journey.laterAdjustments}'
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
              'System stock ${_n(widget.row.raw['system_stock'])} → Branch stock ${_n(widget.row.raw['actual_stock'])}\nDifference ${_n(widget.row.raw['diff'], signed: true)}',
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
          Container(
            padding: const EdgeInsets.all(18),
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
          const SizedBox(height: 22),
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
            const SizedBox(height: 16),
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
  ) => Container(
    constraints: const BoxConstraints(minHeight: 212),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .035),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: .2)),
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
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          headline,
          style: TextStyle(
            color: color,
            fontSize: 21,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          body,
          style: const TextStyle(color: _ink, fontSize: 13, height: 1.6),
        ),
      ],
    ),
  );

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
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .045),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .25)),
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
                height: 1.8,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$previous\n$movements\n$outcome',
              style: const TextStyle(color: _ink, fontSize: 14, height: 1.9),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _storyNumber('Received', received, _teal),
                _storyNumber('Sold after receipt', j.sold, _ink),
                _storyNumber('Transferred out', j.transferredOut, _ink),
                _storyNumber('Other stock removed', j.otherOut, _muted),
                _storyNumber('Expected system stock', expected, _teal),
                _storyNumber('Branch stock', actual, color),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              verdict,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 16,
                height: 1.7,
              ),
            ),
            if (a['old_shortage'] != null && a['added_shortage'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Previously missing: ${qty(older)}. Additional missing in this report entry: ${qty(added)}.',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 13,
                    height: 1.7,
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
                    height: 1.7,
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
                    height: 1.7,
                  ),
                ),
              ),
            if ((a['receipt_types'] as List? ?? []).contains('ReturnPOS'))
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'The latest stock received includes a customer return. Check the return document; it is not a new warehouse transfer.',
                  style: TextStyle(color: _muted, fontSize: 13, height: 1.7),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _storyNumber(String title, num? value, Color color) => Container(
    width: 168,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 5),
        Text(
          _n(value),
          style: TextStyle(
            color: color,
            fontSize: 24,
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
