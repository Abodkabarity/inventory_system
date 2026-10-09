import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

enum AppDateRangePickerMode { history, deadline }

typedef AppDateRangePreset = (String, DateTime, DateTime);

class AppDateRangePickerDialog extends StatefulWidget {
  final DateTimeRange? initialRange;
  final AppDateRangePickerMode mode;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final List<AppDateRangePreset> Function(DateTime now)? presets;
  final bool allowSingleDay;

  const AppDateRangePickerDialog({
    super.key,
    this.initialRange,
    this.mode = AppDateRangePickerMode.history,
    this.firstDate,
    this.lastDate,
    this.presets,
    this.allowSingleDay = false,
  });

  @override
  State<AppDateRangePickerDialog> createState() =>
      AppDateRangePickerDialogState();
}

class AppDateRangePickerDialogState extends State<AppDateRangePickerDialog> {
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
    _start = _d(
      widget.initialRange?.start ?? widget.lastDate ?? DateTime.now(),
    );
    _end = widget.initialRange == null ? null : _d(widget.initialRange!.end);
    _leftMonth = DateTime(_start.year, _start.month);
  }

  DateTime _d(DateTime dt) => DateTime(dt.year, dt.month, dt.day);
  DateTime get _rightMonth => DateTime(_leftMonth.year, _leftMonth.month + 1);

  bool _inBounds(DateTime day) {
    if (widget.firstDate != null && day.isBefore(_d(widget.firstDate!))) {
      return false;
    }
    final lastDate = widget.lastDate;
    if (lastDate != null) return !day.isAfter(_d(lastDate));
    return widget.mode == AppDateRangePickerMode.deadline ||
        !day.isAfter(_d(DateTime.now()));
  }

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

  Widget _buildSidebar() {
    final now = DateTime.now();
    final today = _d(now);
    final weekStart = today.subtract(Duration(days: today.weekday % 7));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);

    final presets =
        widget.presets?.call(now) ??
        (widget.mode == AppDateRangePickerMode.deadline
            ? [
                ('Tomorrow', today, today.add(const Duration(days: 1))),
                ('2 Days', today, today.add(const Duration(days: 2))),
                ('3 Days', today, today.add(const Duration(days: 3))),
                ('1 Week', today, today.add(const Duration(days: 7))),
                ('2 Weeks', today, today.add(const Duration(days: 14))),
                ('1 Month', today, DateTime(now.year, now.month + 1, now.day)),
                ('2 Months', today, DateTime(now.year, now.month + 2, now.day)),
              ]
            : [
                ('Today', today, today),
                (
                  'Yesterday',
                  today.subtract(const Duration(days: 1)),
                  today.subtract(const Duration(days: 1)),
                ),
                ('This Week', weekStart, weekEnd),
                ('Last 7 Days', today.subtract(const Duration(days: 6)), today),
                ('This Month', monthStart, monthEnd),
                (
                  'Last Month',
                  DateTime(now.year, now.month - 1, 1),
                  DateTime(now.year, now.month, 0),
                ),
                (
                  'Last 30 Days',
                  today.subtract(const Duration(days: 29)),
                  today,
                ),
                (
                  'Last 3 Months',
                  DateTime(now.year, now.month - 2, 1),
                  monthEnd,
                ),
                (
                  'Last 6 Months',
                  DateTime(now.year, now.month - 5, 1),
                  monthEnd,
                ),
              ]);

    return Container(
      width: 155,
      color: _surfaceBg,
      padding: const EdgeInsets.fromLTRB(10, 16, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 8),
            child: const Text(
              'QUICK SELECT',
              style: TextStyle(
                color: _textHint,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
          ...presets
              .where(
                (p) =>
                    widget.firstDate == null && widget.lastDate == null ||
                    _inBounds(p.$2) && _inBounds(p.$3),
              )
              .map((p) {
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
                        fontWeight: active
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    const fromLabel = 'From';
    const toLabel = 'To';
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
          _dateChip(fromLabel, _fmt(_start), !_selectingEnd),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 14,
              color: _textHint,
            ),
          ),
          _dateChip(
            toLabel,
            _end != null
                ? _fmt(_end!)
                : _selectingEnd
                ? 'Pick end...'
                : 'Not selected',
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
    final disabled = !_inBounds(day);
    final isEdge = isStart || isEnd;

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

    Color textColor = _textPri;
    if (disabled) {
      textColor = const Color(0xffCBD5E1);
    }
    if (isEdge) {
      textColor = Colors.white;
    } else if (inRange) {
      textColor = _accent;
    }

    return MouseRegion(
      onEnter: (_) => _onHover(day),
      onExit: (_) => _onHover(null),
      cursor: disabled
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: disabled ? null : () => _onDayTap(day),
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
              '${_fmt(_start)}  to  ${_fmt(_end!)}',
              style: const TextStyle(color: _textSec, fontSize: 11),
            ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: _textSec),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.secondaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _end != null || widget.allowSingleDay
                ? () => Navigator.of(
                    context,
                  ).pop(DateTimeRange(start: _start, end: _end ?? _start))
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
