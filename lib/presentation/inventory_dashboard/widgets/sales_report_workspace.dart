import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import 'stock_catalog_visuals.dart' show catalogControlTheme;

const _ink = AppColors.secondaryColor;
const _muted = Color(0xFF718399);
const _blue = AppColors.primaryColor;
const _line = Color(0xFFE4ECF3);

enum SalesReportDownloadPhase { idle, starting, requested }

/// Presentation only. All export preparation and freshness checks stay on server.
class SalesReportWorkspace extends StatefulWidget {
  final List<Map<String, dynamic>> months;
  final Set<String> selected;
  final Map<String, dynamic>? job;
  final bool loading, busy, metadataCurrent;
  final String? error;
  final String? currentMonth, currentMonthLastDay;
  final bool zonal;
  final bool awaitingMonthlyUpdate;
  final String? scopeLabel;
  final bool awaitingUpdate, dailyLoading, dailyBusy;
  final Map<String, dynamic>? dailyJob;
  final String? dailyError;
  final VoidCallback? onDailyDownload;
  final String? dailyFrom, dailyThrough;
  final ValueChanged<String> onToggle;
  final ValueChanged<List<String>> onPreset;
  final VoidCallback onRefresh, onDownload;
  final bool monthlyPending;
  final bool monthlyChecking, dailyChecking;
  final SalesReportDownloadPhase downloadPhase;
  final String downloadLabel;
  final VoidCallback? onDismissDownloadNotice;

  const SalesReportWorkspace({
    super.key,
    required this.months,
    required this.selected,
    required this.job,
    required this.loading,
    required this.busy,
    required this.metadataCurrent,
    required this.error,
    this.currentMonth,
    this.currentMonthLastDay,
    this.zonal = false,
    this.awaitingMonthlyUpdate = false,
    this.scopeLabel,
    this.dailyLoading = false,
    this.dailyBusy = false,
    this.dailyJob,
    this.dailyError,
    this.onDailyDownload,
    this.awaitingUpdate = false,
    this.dailyFrom,
    this.dailyThrough,
    required this.onToggle,
    required this.onPreset,
    required this.onRefresh,
    required this.onDownload,
    this.monthlyPending = false,
    this.monthlyChecking = false,
    this.dailyChecking = false,
    this.downloadPhase = SalesReportDownloadPhase.idle,
    this.downloadLabel = 'Sales report CSV',
    this.onDismissDownloadNotice,
  });

  @override
  State<SalesReportWorkspace> createState() => _SalesReportWorkspaceState();
}

class _SalesReportWorkspaceState extends State<SalesReportWorkspace> {
  String? _year;

  List<String> get _ordered =>
      widget.months.map((m) => m['month'] as String).toList()..sort(
        (a, b) => '${a.substring(3)}${a.substring(0, 2)}'.compareTo(
          '${b.substring(3)}${b.substring(0, 2)}',
        ),
      );
  List<String> get _selection =>
      _ordered.where(widget.selected.contains).toList();
  bool get _ready =>
      !widget.awaitingMonthlyUpdate &&
      widget.job?['status'] == 'ready' &&
      widget.job?['is_current'] == true;
  bool get _working =>
      !widget.awaitingMonthlyUpdate &&
      const ['queued', 'uploading'].contains(widget.job?['status']);

  @override
  Widget build(BuildContext context) => Theme(
    data: catalogControlTheme(context),
    child: Stack(
      children: [
        SizedBox.expand(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF0F7FC),
                  Color(0xFFF6F8FC),
                  Color(0xFFF4F7FA),
                ],
              ),
            ),
            child: LayoutBuilder(
              builder: (context, size) {
                final compact = size.maxWidth < 700;
                final sideBySide = size.maxWidth >= 1080;
                final pad = compact ? 16.0 : 28.0;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(pad, compact ? 24 : 28, pad, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _header(compact),
                      const SizedBox(height: 22),
                      _overview(compact),
                      const SizedBox(height: 18),
                      _dailyExport(compact),
                      const SizedBox(height: 24),
                      if (widget.error != null) ...[
                        _error(),
                        const SizedBox(height: 18),
                      ],
                      if (sideBySide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 7, child: _period()),
                            const SizedBox(width: 22),
                            Expanded(flex: 4, child: _export()),
                          ],
                        )
                      else ...[
                        _period(),
                        const SizedBox(height: 20),
                        _export(),
                      ],
                      const SizedBox(height: 20),
                      _footer(),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        if (widget.downloadPhase == SalesReportDownloadPhase.starting) ...[
          const Positioned.fill(
            child: ModalBarrier(dismissible: false, color: Color(0x66122D40)),
          ),
          Positioned.fill(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Material(
                    key: const ValueKey('sales-download-loading'),
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    child: Padding(
                      padding: const EdgeInsets.all(30),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 38,
                            height: 38,
                            child: CircularProgressIndicator(
                              color: _blue,
                              strokeWidth: 3,
                            ),
                          ),
                          const SizedBox(height: 22),
                          const Text(
                            'Starting your download',
                            style: TextStyle(
                              color: _ink,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.downloadLabel,
                            style: const TextStyle(
                              color: _blue,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Please wait while we open your file. Large reports may take a moment.',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 13,
                              height: 1.6,
                            ),
                            textAlign: TextAlign.center,
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
        if (widget.downloadPhase == SalesReportDownloadPhase.requested)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Material(
                  key: const ValueKey('sales-download-requested'),
                  color: _ink,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.open_in_browser_rounded,
                          color: _blue,
                          size: 25,
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Download requested',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                "Large files can take a moment to appear. Check your browser's downloads for progress.",
                                style: TextStyle(
                                  color: Color(0xFFBFD6E4),
                                  fontSize: 12,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Dismiss download notice',
                          onPressed: widget.onDismissDownloadNotice,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _header(bool compact) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(
        width: compact ? 48 : 60,
        height: compact ? 48 : 60,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6EC6EB), Color(0xFF3BA4D3)],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _blue.withValues(alpha: .18),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: const Icon(
          Icons.receipt_long_rounded,
          color: Colors.white,
          size: 29,
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.zonal ? 'ZONE / REPORTS' : 'ANALYTICS / REPORTS',
              style: TextStyle(
                color: _muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.7,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Sales Report',
              style: TextStyle(
                color: _ink,
                fontSize: compact ? 27 : 32,
                fontWeight: FontWeight.w800,
                height: 1.1,
                letterSpacing: -.8,
              ),
            ),
            if (!compact) ...[
              const SizedBox(height: 7),
              Text(
                widget.zonal
                    ? '${(widget.scopeLabel ?? '').isEmpty ? 'Your zones' : widget.scopeLabel} · Sales from your assigned branches only.'
                    : 'Your selected months. One complete sales report.',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      if (!compact) ...[
        _badge(
          widget.metadataCurrent ? 'Auto-updated' : 'Checking updates',
          widget.metadataCurrent ? const Color(0xFF249584) : _muted,
          icon: Icons.cloud_done_outlined,
        ),
        const SizedBox(width: 12),
      ],
      Tooltip(
        message: 'Refresh status',
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: const BorderSide(color: _line),
          ),
          child: IconButton(
            onPressed: widget.busy ? null : widget.onRefresh,
            icon: const Icon(Icons.refresh_rounded, color: _ink, size: 21),
          ),
        ),
      ),
    ],
  );

  Widget _dailyExport(bool compact) {
    final job = widget.dailyJob;
    final working =
        const ['queued', 'uploading'].contains(job?['status']) &&
        !widget.awaitingUpdate;
    final bytes = (job?['byte_size'] as num?)?.toDouble() ?? 0;
    final uploaded = (job?['uploaded_bytes'] as num?)?.toDouble() ?? 0;
    final status = widget.dailyError != null
        ? widget.dailyError!
        : widget.dailyChecking
        ? 'Checking for updates…'
        : widget.dailyLoading
        ? 'Checking the latest sales…'
        : widget.awaitingUpdate
        ? "Waiting for the daily sales update"
        : working
        ? 'Preparing your complete CSV…'
        : '${_dailyRange()} · Invoice dates included';
    final detail = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sales · Last 45 days',
          style: TextStyle(
            color: _ink,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          status,
          style: TextStyle(
            color: widget.dailyError != null ? const Color(0xFFB35C50) : _muted,
            fontSize: 11,
            height: 1.6,
          ),
        ),
        if (working) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 3,
              color: _blue,
              backgroundColor: const Color(0xFFE2EDF4),
              value: bytes > 0 ? (uploaded / bytes).clamp(0, 1) : null,
            ),
          ),
        ],
      ],
    );
    final action = FilledButton.icon(
      key: const ValueKey('sales-daily-download'),
      onPressed:
          widget.dailyLoading ||
              widget.dailyBusy ||
              widget.awaitingUpdate ||
              widget.dailyThrough == null
          ? null
          : widget.onDailyDownload,
      style: FilledButton.styleFrom(
        backgroundColor: _ink,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFE4EDF3),
        disabledForegroundColor: _muted,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      icon: widget.dailyBusy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: _muted),
            )
          : Icon(
              widget.dailyBusy || working
                  ? Icons.cloud_sync_outlined
                  : Icons.download_rounded,
              size: 19,
            ),
      label: Text(
        widget.downloadPhase == SalesReportDownloadPhase.starting
            ? 'Starting download…'
            : widget.dailyChecking
            ? 'Checking for updates…'
            : widget.dailyBusy
            ? 'Preparing 45 days…'
            : 'Download Sales 45 Days',
      ),
    );
    return Container(
      padding: EdgeInsets.all(compact ? 18 : 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEBF6FC), Color(0xFFF9FCFE)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD6EAF5)),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [detail, const SizedBox(height: 16), action],
            )
          : Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.event_note_rounded,
                    color: _blue,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 17),
                Expanded(child: detail),
                const SizedBox(width: 24),
                action,
              ],
            ),
    );
  }

  String _dailyRange() {
    final from = DateTime.tryParse(widget.dailyFrom ?? '');
    final through = DateTime.tryParse(widget.dailyThrough ?? '');
    if (from == null || through == null) return 'Waiting for daily sales';
    return '${DateFormat('dd MMM', 'en_US').format(from)} — ${DateFormat('dd MMM yyyy', 'en_US').format(through)}';
  }

  Widget _overview(bool compact) {
    final entries = [
      _OverviewMetric(
        icon: Icons.checklist_rounded,
        title: 'SELECTED MONTHS',
        value: '${widget.selected.length} months',
        caption: 'Included in your export',
      ),
      _OverviewMetric(
        icon: Icons.calendar_month_outlined,
        title: 'REPORTING PERIOD',
        value: '${widget.months.length} months',
        caption: _ordered.isEmpty
            ? 'Waiting for sales data'
            : '${_shortMonth(_ordered.first)} — ${_shortMonth(_ordered.last)}',
      ),
      _OverviewMetric(
        icon: Icons.file_download_outlined,
        title: 'EXPORT FORMAT',
        value: 'CSV',
        caption: 'All selected months in one file',
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
      ),
      child: compact
          ? Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      indent: 22,
                      endIndent: 22,
                      color: _line,
                    ),
                  entries[i],
                ],
              ],
            )
          : IntrinsicHeight(
              child: Row(
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 22),
                        child: VerticalDivider(width: 1, color: _line),
                      ),
                    Expanded(child: entries[i]),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _period() {
    final years = {
      ..._ordered.map((m) => m.substring(3)),
      if (widget.currentMonth != null) widget.currentMonth!.substring(3),
    }.toList()..sort();
    final year = years.contains(_year) ? _year : years.lastOrNull;
    final yearMonths = _ordered
        .where((month) => month.substring(3) == year)
        .toList();
    final available = {for (final m in widget.months) m['month'] as String: m};
    final lastThree = yearMonths.reversed.take(3).toList();
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _step('01'),
              const SizedBox(width: 11),
              const Expanded(
                child: Text(
                  'Reporting period',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: widget.busy || widget.selected.isEmpty
                    ? null
                    : () => widget.onPreset([]),
                child: const Text('Clear selection'),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6, bottom: 22),
            child: Text(
              'Choose the months to include in your report.',
              style: TextStyle(color: _muted, fontSize: 13),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _preset(
                'Latest month',
                yearMonths.isEmpty ? [] : [yearMonths.last],
              ),
              _preset('Last 3 months', lastThree),
              _preset('All months', yearMonths),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                color: _muted,
                size: 16,
              ),
              const SizedBox(width: 8),
              if (years.length <= 1)
                Text(
                  year ?? 'Calendar',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                )
              else
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    children: years
                        .map(
                          (y) => ChoiceChip(
                            label: Text(y),
                            selected: y == year,
                            showCheckmark: false,
                            selectedColor: const Color(0xFFEAF7FD),
                            backgroundColor: const Color(0xFFF8FAFC),
                            side: BorderSide(
                              color: y == year
                                  ? _blue.withValues(alpha: .45)
                                  : _line,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                            labelStyle: TextStyle(
                              color: y == year
                                  ? const Color(0xFF238DBD)
                                  : _muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                            onSelected: (_) => setState(() => _year = y),
                          ),
                        )
                        .toList(),
                  ),
                ),
              if (years.length <= 1) const Spacer(),
              _badge('${widget.selected.length} selected', _blue),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.loading)
            const SizedBox(
              height: 260,
              child: Center(child: CircularProgressIndicator(color: _blue)),
            )
          else if (year == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 60),
              child: Center(
                child: Text(
                  'No sales months available.',
                  style: TextStyle(color: _muted),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, box) {
                final columns = box.maxWidth >= 620
                    ? 4
                    : box.maxWidth >= 470
                    ? 3
                    : 2;
                const gap = 12.0;
                final tileWidth =
                    (box.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (var n = 1; n <= 12; n++)
                      SizedBox(
                        width: tileWidth,
                        child: _MonthTile(
                          key: ValueKey(
                            'sales-month-${n.toString().padLeft(2, '0')}/$year',
                          ),
                          month: n,
                          year: year,
                          lastDay:
                              '${n.toString().padLeft(2, '0')}/$year' ==
                                  widget.currentMonth
                              ? widget.currentMonthLastDay
                              : null,
                          available: available.containsKey(
                            '${n.toString().padLeft(2, '0')}/$year',
                          ),
                          selected: widget.selected.contains(
                            '${n.toString().padLeft(2, '0')}/$year',
                          ),
                          enabled:
                              !widget.busy &&
                              available.containsKey(
                                '${n.toString().padLeft(2, '0')}/$year',
                              ),
                          onTap: () => widget.onToggle(
                            '${n.toString().padLeft(2, '0')}/$year',
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          const SizedBox(height: 20),
          const Divider(height: 1, color: _line),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: _blue,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.metadataCurrent
                      ? 'Available sales months'
                      : 'Updating available months…',
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ),
              Text(
                'Single CSV export',
                style: const TextStyle(
                  color: _ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _preset(String label, List<String> months) {
    final active =
        months.isNotEmpty &&
        widget.selected.length == months.length &&
        widget.selected.containsAll(months);
    return OutlinedButton(
      onPressed: widget.busy || months.isEmpty
          ? null
          : () => widget.onPreset(months),
      style: OutlinedButton.styleFrom(
        foregroundColor: active ? const Color(0xFF238DBD) : _muted,
        backgroundColor: active
            ? const Color(0xFFEAF7FD)
            : const Color(0xFFF8FAFC),
        side: BorderSide(color: active ? _blue.withValues(alpha: .45) : _line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(label),
    );
  }

  Widget _export() {
    final job = widget.job;
    final bytes = const ['uploading', 'ready'].contains(job?['status'])
        ? (job?['byte_size'] as num?)?.toDouble() ?? 0
        : 0.0;
    final uploaded = (job?['uploaded_bytes'] as num?)?.toDouble() ?? 0;
    final empty = widget.selected.isEmpty;
    final stale = job?['status'] == 'ready' && !_ready;
    final failed = job?['status'] == 'failed';
    final status = widget.monthlyChecking
        ? 'Checking for updates…'
        : widget.awaitingMonthlyUpdate
        ? "Waiting for yesterday's sales"
        : _ready
        ? 'Ready to download'
        : _working || widget.monthlyPending
        ? 'Preparing your file'
        : stale
        ? 'Update available'
        : failed
        ? 'Preparation interrupted'
        : empty
        ? 'Choose your period'
        : 'Ready to prepare';
    final statusColor = _ready
        ? const Color(0xFF259D87)
        : stale || failed
        ? const Color(0xFFCE9142)
        : _blue;
    final canDownload =
        !empty &&
        !widget.awaitingMonthlyUpdate &&
        !widget.busy &&
        !widget.monthlyPending &&
        widget.metadataCurrent;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: _ink.withValues(alpha: .05),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(25),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF17384E),
                  Color(0xFF122D40),
                  Color(0xFF20536C),
                ],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'YOUR EXPORT',
                        style: TextStyle(
                          color: Color(0xFF96CBE2),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.7,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sales report',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.5,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        empty
                            ? 'A complete view of your sales.'
                            : '${widget.selected.length} ${widget.selected.length == 1 ? 'month' : 'months'} · One consolidated file',
                        style: const TextStyle(
                          color: Color(0xFFADC7D7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                const _FileEmblem(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (_ready)
                      const Icon(
                        Icons.verified_outlined,
                        color: Color(0xFF259D87),
                        size: 18,
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'REPORTING PERIOD',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 10,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  _periodTitle(),
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                if (empty)
                  const Text(
                    'Select months from the calendar to build your download.',
                    style: TextStyle(color: _muted, fontSize: 12, height: 1.6),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _selection
                        .map(
                          (m) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F6FA),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _shortMonth(m),
                              style: const TextStyle(
                                color: Color(0xFF57748B),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                if (widget.currentMonth != null &&
                    widget.selected.contains(widget.currentMonth)) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Current month to date · Retail and sales value are unavailable.',
                    style: TextStyle(color: _muted, fontSize: 11, height: 1.5),
                  ),
                ],
                const SizedBox(height: 24),
                const Divider(height: 1, color: _line),
                const SizedBox(height: 22),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _ExportMetric(
                        value: '${widget.selected.length}',
                        label: 'Selected months',
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 43,
                      margin: const EdgeInsets.symmetric(horizontal: 18),
                      color: _line,
                    ),
                    Expanded(
                      child: _ExportMetric(
                        value: bytes > 0
                            ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
                            : 'CSV',
                        label: bytes > 0 ? 'File size' : 'File format',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (_working || widget.monthlyPending) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      color: _blue,
                      backgroundColor: const Color(0xFFEBF3F8),
                      value: bytes > 0 ? (uploaded / bytes).clamp(0, 1) : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    job?['retrying'] == true
                        ? 'Retrying automatically…'
                        : widget.monthlyPending
                        ? 'Your download will start automatically. Keep this page open.'
                        : 'Your file is being prepared on the server.',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    key: const ValueKey('sales-report-primary-action'),
                    onPressed: canDownload ? widget.onDownload : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFEDF3F7),
                      disabledForegroundColor: const Color(0xFF95A7B6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                    icon: widget.busy || widget.monthlyPending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _muted,
                            ),
                          )
                        : Icon(
                            _ready
                                ? Icons.download_rounded
                                : _working
                                ? Icons.cloud_sync_outlined
                                : Icons.file_download_outlined,
                            size: 19,
                          ),
                    label: Text(
                      widget.busy
                          ? _ready
                                ? 'Starting download…'
                                : 'Please wait…'
                          : widget.monthlyChecking
                          ? 'Checking for updates…'
                          : widget.monthlyPending
                          ? widget.awaitingMonthlyUpdate
                                ? 'Waiting for sales update…'
                                : 'Preparing CSV…'
                          : 'Download CSV',
                    ),
                  ),
                ),
                const SizedBox(height: 13),
                Center(
                  child: Text(
                    _ready
                        ? 'Up to date · Direct download'
                        : widget.awaitingMonthlyUpdate
                        ? 'Available after the daily sales update is complete'
                        : empty
                        ? 'Select at least one month to continue'
                        : 'All selected months will be combined into one file',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 10,
                      height: 1.5,
                    ),
                  ),
                ),
                if (job?['prepared_at'] != null) ...[
                  const SizedBox(height: 23),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7FAFC),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          color: _muted,
                          size: 15,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Prepared ${_date(job!['prepared_at'])}',
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 10,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _periodTitle() {
    final selection = _selection;
    if (selection.isEmpty) return 'Choose your months';
    if (selection.length == 1) return _longMonth(selection.first);
    final first = DateFormat('MM/yyyy').parse(selection.first);
    final last = DateFormat('MM/yyyy').parse(selection.last);
    final consecutive =
        (last.year - first.year) * 12 + last.month - first.month + 1 ==
        selection.length;
    if (!consecutive) return '${selection.length} selected months';
    return first.year == last.year
        ? '${DateFormat('MMM', 'en_US').format(first)} — ${DateFormat('MMM yyyy', 'en_US').format(last)}'
        : '${_shortMonth(selection.first)} — ${_shortMonth(selection.last)}';
  }

  Widget _footer() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.verified_user_outlined,
          color: Color(0xFF7E9BB0),
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Always current. Your report refreshes when sales data changes.',
            style: TextStyle(color: _muted, fontSize: 11, height: 1.5),
          ),
        ),
      ],
    ),
  );

  Widget _error() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF5F3),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFF4DCD7)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.info_outline_rounded,
          color: Color(0xFFC76B58),
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Unable to update the report. Please refresh and try again.',
            style: const TextStyle(color: Color(0xFFA95344), fontSize: 12),
          ),
        ),
        TextButton(onPressed: widget.onRefresh, child: const Text('Retry')),
      ],
    ),
  );
}

String _shortMonth(String month) =>
    DateFormat('MMM yyyy', 'en_US').format(DateFormat('MM/yyyy').parse(month));
String _longMonth(String month) =>
    DateFormat('MMMM yyyy', 'en_US').format(DateFormat('MM/yyyy').parse(month));
String _date(Object? value) {
  final date = DateTime.tryParse('$value');
  return date == null
      ? '—'
      : '${DateFormat('dd MMM, HH:mm', 'en_US').format(date.toUtc().add(const Duration(hours: 4)))} UAE';
}

Widget _surface({required Widget child}) => Container(
  width: double.infinity,
  padding: const EdgeInsets.all(24),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: _line),
    boxShadow: [
      BoxShadow(
        color: _ink.withValues(alpha: .025),
        blurRadius: 20,
        offset: const Offset(0, 6),
      ),
    ],
  ),
  child: child,
);
Widget _step(String value) => Container(
  width: 29,
  height: 29,
  decoration: BoxDecoration(
    color: const Color(0xFFEDF7FC),
    borderRadius: BorderRadius.circular(9),
  ),
  alignment: Alignment.center,
  child: Text(
    value,
    style: const TextStyle(
      color: Color(0xFF389BC6),
      fontSize: 11,
      fontWeight: FontWeight.w800,
    ),
  ),
);
Widget _badge(String label, Color color, {IconData? icon}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
  decoration: BoxDecoration(
    color: color.withValues(alpha: .08),
    borderRadius: BorderRadius.circular(8),
  ),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 6),
      ],
      Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  ),
);

class _MonthTile extends StatelessWidget {
  final int month;
  final String year;
  final String? lastDay;
  final bool available, selected, enabled;
  final VoidCallback onTap;
  const _MonthTile({
    super.key,
    required this.month,
    required this.year,
    this.lastDay,
    required this.available,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    enabled: enabled,
    label:
        '${DateFormat('MMMM', 'en_US').format(DateTime(2000, month))} $year, ${available
            ? 'Available'
            : _lastDayLabel != null
            ? 'Export not available yet'
            : 'No sales data'}${_lastDayLabel == null ? '' : ', $_lastDayLabel'}',
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: selected
                  ? [const Color(0xFFECF8FE), const Color(0xFFF5FBFE)]
                  : [
                      !available ? const Color(0xFFFAFBFC) : Colors.white,
                      !available
                          ? const Color(0xFFFAFBFC)
                          : const Color(0xFFFCFDFE),
                    ],
            ),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? _blue
                  : !available
                  ? const Color(0xFFF0F3F6)
                  : _line,
              width: selected ? 1.4 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _blue.withValues(alpha: .08),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    month.toString().padLeft(2, '0'),
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFF359CC9)
                          : const Color(0xFFA9B9C6),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : !available
                        ? Icons.remove_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected
                        ? _blue
                        : !available
                        ? const Color(0xFFD1DCE4)
                        : const Color(0xFFCEDBE5),
                    size: 19,
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Text(
                DateFormat('MMMM', 'en_US').format(DateTime(2000, month)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: !available ? const Color(0xFFA9B7C2) : _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _lastDayLabel ??
                    (!available
                        ? 'No sales data'
                        : selected
                        ? 'Selected'
                        : 'Available'),
                style: TextStyle(
                  color: _lastDayLabel != null
                      ? const Color(0xFF389BC6)
                      : !available
                      ? const Color(0xFFB6C1CA)
                      : _muted,
                  fontSize: 10,
                ),
              ),
              if (_lastDayLabel != null && !available) ...[
                const SizedBox(height: 4),
                const Text(
                  'Export not available yet',
                  style: TextStyle(color: _muted, fontSize: 9),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  String? get _lastDayLabel {
    final date = DateTime.tryParse(lastDay ?? '');
    if (date == null || date.year.toString() != year || date.month != month) {
      return null;
    }
    return 'Latest sale: ${DateFormat('dd MMM', 'en_US').format(date)}';
  }
}

class _OverviewMetric extends StatelessWidget {
  final IconData icon;
  final String title, value, caption;
  const _OverviewMetric({
    required this.icon,
    required this.title,
    required this.value,
    required this.caption,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
    child: Row(
      children: [
        Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F8FC),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: _blue, size: 21),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                value,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  letterSpacing: -.7,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                caption,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 10,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ExportMetric extends StatelessWidget {
  final String value, label;
  const _ExportMetric({required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          value,
          style: const TextStyle(
            color: _ink,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -.7,
          ),
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
    ],
  );
}

class _FileEmblem extends StatelessWidget {
  const _FileEmblem();
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 67,
    height: 78,
    child: Stack(
      children: [
        Positioned(
          left: 11,
          top: 6,
          child: Transform.rotate(
            angle: .12,
            child: Container(
              width: 47,
              height: 62,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
        ),
        Positioned(
          left: 5,
          top: 1,
          child: Container(
            width: 47,
            height: 62,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F6FD),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.bar_chart_rounded,
                  color: Color(0xFF409CC5),
                  size: 21,
                ),
                const SizedBox(height: 7),
                Container(height: 3, width: 25, color: const Color(0xFFB3DAEC)),
                const SizedBox(height: 4),
                Container(height: 3, width: 18, color: const Color(0xFFD1E9F4)),
              ],
            ),
          ),
        ),
        Positioned(
          right: 1,
          bottom: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: _blue,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF20536C), width: 2),
            ),
            child: const Text(
              'CSV',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
