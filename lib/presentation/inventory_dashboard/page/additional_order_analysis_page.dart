import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';
import '../widgets/additional_analysis/additional_analysis_header.dart';
import '../widgets/additional_analysis/additional_insights_section.dart';
import '../widgets/additional_analysis/top_branches_card.dart';
import '../widgets/additional_analysis/top_products_card.dart';

class AdditionalOrderAnalysisPage extends StatefulWidget {
  const AdditionalOrderAnalysisPage({super.key});

  @override
  State<AdditionalOrderAnalysisPage> createState() =>
      _AdditionalOrderAnalysisPageState();
}

class _AdditionalOrderAnalysisPageState
    extends State<AdditionalOrderAnalysisPage> {
  late DateTime _from;
  late DateTime _to;
  bool _isAnalysisLoading = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    // ✅ Check if data already exists — if so, skip the loading state entirely
    final existingData = context.read<InventoryBloc>().state.additionalAnalysis;
    if (existingData.isEmpty) {
      _load();
    }
    // If data exists, _isAnalysisLoading stays false and we render immediately
  }

  void _load() {
    setState(() => _isAnalysisLoading = true);
    context.read<InventoryBloc>().add(
      LoadAdditionalOrderAnalysis(from: _from, to: _to),
    );
  }

  Future<void> _pickDateRange() async {
    final result = await showDialog<DateTimeRange>(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => _DateRangePickerDialog(
        initialRange: DateTimeRange(start: _from, end: _to),
      ),
    );
    if (result != null) {
      setState(() {
        _from = result.start;
        _to = DateTime(
          result.end.year,
          result.end.month,
          result.end.day,
          23,
          59,
          59,
        );
      });
      _load();
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return BlocListener<InventoryBloc, InventoryState>(
      listenWhen: (prev, curr) =>
          prev.additionalAnalysis != curr.additionalAnalysis,
      listener: (_, __) => setState(() => _isAnalysisLoading = false),
      child: Container(
        color: const Color(0xffF0F4F8),
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: BlocBuilder<InventoryBloc, InventoryState>(
                builder: (context, state) {
                  if (_isAnalysisLoading) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xff06B6D4),
                      ),
                    );
                  }

                  final data = state.additionalAnalysis;

                  if (data.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.analytics_outlined,
                            color: Color(0xffCBD5E1),
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No data for the selected period',
                            style: TextStyle(
                              color: Color(0xff94A3B8),
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: _load,
                            icon: const Icon(
                              Icons.refresh,
                              color: Color(0xff06B6D4),
                            ),
                            label: const Text(
                              'Reload',
                              style: TextStyle(color: Color(0xff06B6D4)),
                            ),
                          ),
                        ],
                      ),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AdditionalKpiCards(data: data),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 480,
                          child: Row(
                            children: [
                              Expanded(
                                child: TopBranchesCard(branches: branches),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: TopProductsCard(products: products),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        AdditionalInsightsSection(data: data),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xffE2E8F0))),
      ),
      child: Row(
        children: [
          const Icon(Icons.analytics, color: Color(0xff06B6D4)),
          const SizedBox(width: 12),
          const Text(
            'Additional Order Analysis',
            style: TextStyle(
              color: Color(0xff1E293B),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          // Date badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xffF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xffE2E8F0)),
            ),
            child: Text(
              '${_formatDate(_from)}  →  ${_formatDate(_to)}',
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
}

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOM DATE RANGE PICKER DIALOG
// ═══════════════════════════════════════════════════════════════════════════════

class _DateRangePickerDialog extends StatefulWidget {
  final DateTimeRange initialRange;
  const _DateRangePickerDialog({required this.initialRange});

  @override
  State<_DateRangePickerDialog> createState() => _DateRangePickerDialogState();
}

class _DateRangePickerDialogState extends State<_DateRangePickerDialog> {
  late DateTime _start;
  DateTime? _end;
  DateTime? _hoverDay;
  late DateTime _leftMonth;
  bool _selectingEnd = false;

  static const _accent = Color(0xff06B6D4);
  static const _accentBg = Color(0xffCCF2F8);
  static const _textPri = Color(0xff1E293B);
  static const _textSec = Color(0xff64748B);
  static const _textHint = Color(0xff94A3B8);
  static const _border = Color(0xffE2E8F0);
  static const _inputBg = Color(0xffF1F5F9);
  static const _surfaceBg = Color(0xffF8FAFC);

  static const _weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _monthsShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _start = _d(widget.initialRange.start);
    _end = _d(widget.initialRange.end);
    _leftMonth = DateTime(_start.year, _start.month);
  }

  DateTime _d(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
  DateTime get _rightMonth => DateTime(_leftMonth.year, _leftMonth.month + 1);

  bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _inRange(DateTime day) {
    final endRef = _end ?? (_selectingEnd ? _hoverDay : null);
    if (endRef == null) return false;
    final s = _start.isBefore(endRef) ? _start : endRef;
    final e = _start.isBefore(endRef) ? endRef : _start;
    return day.isAfter(s) && day.isBefore(e);
  }

  bool _isStart(DateTime day) => _same(day, _start);
  bool _isEnd(DateTime day) {
    final endRef = _end ?? (_selectingEnd ? _hoverDay : null);
    return endRef != null && _same(day, endRef);
  }

  void _onDayTap(DateTime day) {
    setState(() {
      if (!_selectingEnd) {
        _start = day;
        _end = null;
        _selectingEnd = true;
      } else {
        if (day.isBefore(_start)) {
          _end = _start;
          _start = day;
        } else {
          _end = day;
        }
        _selectingEnd = false;
        _hoverDay = null;
      }
    });
  }

  void _onHover(DateTime? day) {
    if (_selectingEnd) setState(() => _hoverDay = day);
  }

  void _preset(DateTime s, DateTime e) {
    setState(() {
      _start = _d(s);
      _end = _d(e);
      _selectingEnd = false;
      _hoverDay = null;
      _leftMonth = DateTime(_start.year, _start.month);
    });
  }

  String _fmt(DateTime d) => '${_monthsShort[d.month - 1]} ${d.day}, ${d.year}';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      elevation: 20,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 840,
        height: 490,
        child: Row(
          children: [
            _buildSidebar(),
            Container(width: 1, color: _border),
            Expanded(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildMonth(_leftMonth)),
                        Container(width: 1, color: _border),
                        Expanded(child: _buildMonth(_rightMonth)),
                      ],
                    ),
                  ),
                  _buildFooter(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sidebar ──────────────────────────────────────────────────────────────
  Widget _buildSidebar() {
    final now = DateTime.now();
    final today = _d(now);
    final weekStart = today.subtract(Duration(days: today.weekday % 7));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);

    final presets = [
      ('Today', today, today),
      (
        'Yesterday',
        today.subtract(const Duration(days: 1)),
        today.subtract(const Duration(days: 1)),
      ),
      ('This Week', weekStart, weekEnd),
      ('Last 7 Days', today.subtract(const Duration(days: 6)), today),
      ('This Month', monthStart, monthEnd),
      ('Last 30 Days', today.subtract(const Duration(days: 29)), today),
      ('Last 3 Months', DateTime(now.year, now.month - 2, 1), monthEnd),
      ('Last 6 Months', DateTime(now.year, now.month - 5, 1), monthEnd),
    ];

    return Container(
      width: 155,
      color: _surfaceBg,
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 6, bottom: 8),
            child: Text(
              'QUICK SELECT',
              style: TextStyle(
                color: _textHint,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          ...presets.map((p) {
            final active =
                _end != null && _same(_start, p.$2) && _same(_end!, p.$3);
            return GestureDetector(
              onTap: () => _preset(p.$2, p.$3),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 3),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? _accent.withValues(alpha: 0.10)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: active
                      ? Border.all(color: _accent.withValues(alpha: 0.3))
                      : null,
                ),
                child: Text(
                  p.$1,
                  style: TextStyle(
                    color: active ? _accent : _textPri,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          _navBtn(
            Icons.chevron_left,
            () => setState(
              () =>
                  _leftMonth = DateTime(_leftMonth.year, _leftMonth.month - 1),
            ),
          ),
          const SizedBox(width: 6),
          _navBtn(
            Icons.chevron_right,
            () => setState(
              () =>
                  _leftMonth = DateTime(_leftMonth.year, _leftMonth.month + 1),
            ),
          ),
          const SizedBox(width: 14),
          _dateChip('From', _fmt(_start), !_selectingEnd),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 14,
              color: _textHint,
            ),
          ),
          _dateChip(
            'To',
            _end != null
                ? _fmt(_end!)
                : _selectingEnd
                ? 'Pick end…'
                : '—',
            _selectingEnd,
            faded: _end == null,
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 18, color: _textSec),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: _inputBg,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: _border),
        ),
        child: Icon(icon, size: 16, color: _textSec),
      ),
    );
  }

  Widget _dateChip(
    String label,
    String text,
    bool active, {
    bool faded = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: active ? _accent.withValues(alpha: 0.08) : _surfaceBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? _accent.withValues(alpha: 0.35) : _border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: active ? _accent : _textHint,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          Text(
            text,
            style: TextStyle(
              color: faded
                  ? _textHint
                  : active
                  ? _accent
                  : _textPri,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── Month grid ────────────────────────────────────────────────────────────
  Widget _buildMonth(DateTime month) {
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final offset = DateTime(month.year, month.month, 1).weekday % 7;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Column(
        children: [
          Text(
            '${_months[month.month - 1]} ${month.year}',
            style: const TextStyle(
              color: _textPri,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: _weekdays
                .map(
                  (w) => Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: const TextStyle(
                          color: _textSec,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.1,
            ),
            itemCount: offset + days,
            itemBuilder: (_, i) {
              if (i < offset) return const SizedBox();
              final day = DateTime(month.year, month.month, i - offset + 1);
              return _buildCell(day);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCell(DateTime day) {
    final isStart = _isStart(day);
    final isEnd = _isEnd(day);
    final inRange = _inRange(day);
    final isFuture = day.isAfter(DateTime.now());
    final isEdge = isStart || isEnd;

    // Strip halves
    final endRef = _end ?? (_selectingEnd ? _hoverDay : null);
    bool stripLeft = false;
    bool stripRight = false;
    if (endRef != null) {
      final s = _start.isBefore(endRef) ? _start : endRef;
      final e = _start.isBefore(endRef) ? endRef : _start;
      if (!day.isBefore(s) && !day.isAfter(e)) {
        stripLeft = !_same(day, s);
        stripRight = !_same(day, e);
      }
    }

    Color textColor = isFuture ? const Color(0xffCBD5E1) : _textPri;
    if (isEdge) {
      textColor = Colors.white;
    } else if (inRange) {
      textColor = _accent;
    }

    return MouseRegion(
      onEnter: (_) => _onHover(day),
      onExit: (_) => _onHover(null),
      cursor: isFuture
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: isFuture ? null : () => _onDayTap(day),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    color: stripLeft ? _accentBg : Colors.transparent,
                  ),
                ),
                Expanded(
                  child: Container(
                    color: stripRight ? _accentBg : Colors.transparent,
                  ),
                ),
              ],
            ),
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isEdge ? _accent : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  color: textColor,
                  fontSize: 11,
                  fontWeight: isEdge ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          if (_end != null)
            Text(
              '${_fmt(_start)}  →  ${_fmt(_end!)}',
              style: const TextStyle(color: _textSec, fontSize: 11),
            ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: _textSec),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _end != null
                ? () => Navigator.of(
                    context,
                  ).pop(DateTimeRange(start: _start, end: _end!))
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _border,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Apply',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
