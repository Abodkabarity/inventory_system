import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/branch_submission_tracker_excel_exporter.dart';
import '../../../domain/entities/branch_setting.dart';
import '../../../domain/entities/branch_submission_miss.dart';
import 'stock_check_page.dart'
    show StockCheckDateRangePickerDialog, StockCheckDateRangePickerMode;

class BranchSubmissionTrackerPage extends StatefulWidget {
  const BranchSubmissionTrackerPage({super.key});

  @override
  State<BranchSubmissionTrackerPage> createState() =>
      _BranchSubmissionTrackerPageState();
}

class _BranchSubmissionTrackerPageState
    extends State<BranchSubmissionTrackerPage> {
  static final DateTime _trackingActivationAt = DateTime(2026, 7, 12, 23, 59);

  final _client = Supabase.instance.client;
  final _searchController = TextEditingController();

  late DateTimeRange _range;
  List<BranchSubmissionMiss> _rows = [];
  String _status = 'all';
  String _zone = 'all';
  bool _loading = true;
  bool _scanning = false;
  bool _exporting = false;
  String _message = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now());
    _range = DateTimeRange(
      start: today.subtract(const Duration(days: 364)),
      end: today,
    );
    _load(scanFirst: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool scanFirst = false}) async {
    setState(() {
      _loading = true;
      _error = '';
      _message = scanFirst ? 'Scanning branch submissions...' : '';
    });
    try {
      if (scanFirst) {
        await _scanMisses();
      }
      final rows = await _fetchMisses();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _message = rows.isEmpty
            ? 'No missed submissions found in this date range.'
            : 'Tracker updated for ${_displayDate(_range.start)} to ${_displayDate(_range.end)}.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = '';
        _error = e.toString();
      });
    }
  }

  Future<void> _rescan() async {
    setState(() {
      _scanning = true;
      _error = '';
      _message = 'Scanning branches not submitted by deadline...';
    });
    try {
      await _scanMisses();
      final rows = await _fetchMisses();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _message = 'Scan completed. ${rows.length} missed record(s) found.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = '';
        _error = e.toString();
      });
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _scanMisses() async {
    final branches = (await _fetchBranches())
        .where(
          (branch) => branch.isActive && branch.branchName.trim().isNotEmpty,
        )
        .toList();
    final submissions = await _fetchSubmittedRows();
    final submissionByKey = <String, DateTime>{};
    for (final row in submissions) {
      final branch = (row['branch_name'] ?? '').toString();
      final runDate = (row['run_date'] ?? '').toString();
      final submittedAt = DateTime.tryParse(
        (row['submitted_at'] ?? '').toString(),
      );
      if (branch.isEmpty || runDate.isEmpty || submittedAt == null) continue;
      submissionByKey['$runDate|$branch'] = submittedAt;
    }

    final now = DateTime.now();
    final payloads = <Map<String, dynamic>>[];
    var day = _dateOnly(
      _range.start.isBefore(_trackingActivationAt)
          ? _trackingActivationAt
          : _range.start,
    );
    final last = _dateOnly(_range.end);
    if (day.isAfter(last)) return;

    while (!day.isAfter(last)) {
      final weekday = DateFormat('EEEE').format(day);
      for (final branch in branches) {
        if (!branch.orderDays.contains(weekday)) continue;

        final deadline = _deadlineFor(day, branch);
        if (deadline.isBefore(_trackingActivationAt)) continue;
        if (deadline.isAfter(now)) continue;

        final runDate = _dbDate(day);
        final submittedAt = submissionByKey['$runDate|${branch.branchName}'];
        if (submittedAt != null && !submittedAt.isAfter(deadline)) continue;

        final status = submittedAt == null ? 'not_submitted' : 'late_submitted';
        final minutesLate = (submittedAt ?? now).difference(deadline).inMinutes;
        payloads.add({
          'run_date': runDate,
          'branch_name': branch.branchName,
          'zone': branch.zone,
          'zone_manager': branch.zoneManager,
          'zone_manager_email': branch.zoneManagerEmail,
          'area': branch.area,
          'branch_type': branch.branchType,
          'expected_submit_by': deadline.toIso8601String(),
          'submitted_at': submittedAt?.toIso8601String(),
          'status': status,
          'minutes_late': minutesLate < 0 ? 0 : minutesLate,
          'updated_at': now.toIso8601String(),
        });
      }
      day = day.add(const Duration(days: 1));
    }

    for (var i = 0; i < payloads.length; i += 400) {
      final end = (i + 400) > payloads.length ? payloads.length : i + 400;
      await _client
          .from('branch_submission_misses')
          .upsert(payloads.sublist(i, end), onConflict: 'run_date,branch_name');
    }
  }

  Future<List<BranchSetting>> _fetchBranches() async {
    final res = await _client
        .from('branches')
        .select('''
          branch_name,
          email,
          zone,
          zone_manager,
          zone_manager_email,
          is_active,
          order_days,
          submit_start_hour,
          submit_end_hour,
          max_adj_limit,
          order_increase_limit,
          order_edit_limit,
          additional_order_limit,
          area,
          branch_type
        ''')
        .order('branch_name', ascending: true);
    return List<Map<String, dynamic>>.from(
      res,
    ).map(BranchSetting.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchSubmittedRows() async {
    final rows = <Map<String, dynamic>>[];
    var from = 0;
    const size = 1000;
    while (true) {
      final page = await _client
          .from('order_submissions')
          .select('run_date, branch_name, submitted_at, status')
          .gte('run_date', _dbDate(_range.start))
          .lte('run_date', _dbDate(_range.end))
          .eq('status', 'submitted')
          .range(from, from + size - 1);
      final list = List<Map<String, dynamic>>.from(page);
      rows.addAll(list);
      if (list.length < size) break;
      from += size;
    }
    return rows;
  }

  Future<List<BranchSubmissionMiss>> _fetchMisses() async {
    final rows = <BranchSubmissionMiss>[];
    var from = 0;
    const size = 1000;
    while (true) {
      final page = await _client
          .from('branch_submission_misses')
          .select()
          .gte('run_date', _dbDate(_range.start))
          .lte('run_date', _dbDate(_range.end))
          .order('run_date', ascending: false)
          .range(from, from + size - 1);
      final list = List<Map<String, dynamic>>.from(page);
      rows.addAll(list.map(BranchSubmissionMiss.fromMap));
      if (list.length < size) break;
      from += size;
    }
    rows.sort((a, b) {
      final date = b.runDate.compareTo(a.runDate);
      if (date != 0) return date;
      return a.branchName.compareTo(b.branchName);
    });
    return rows;
  }

  DateTime _deadlineFor(DateTime runDate, BranchSetting branch) {
    final isFullDay = branch.submitStartHour == 0 && branch.submitEndHour == 24;
    final deadlineDay = isFullDay
        ? runDate
        : branch.submitStartHour > branch.submitEndHour
        ? runDate
        : runDate.subtract(const Duration(days: 1));
    if (branch.submitEndHour >= 24) {
      return DateTime(deadlineDay.year, deadlineDay.month, deadlineDay.day + 1);
    }
    return DateTime(
      deadlineDay.year,
      deadlineDay.month,
      deadlineDay.day,
      branch.submitEndHour,
    );
  }

  List<BranchSubmissionMiss> get _filteredRows {
    final q = _searchController.text.trim().toLowerCase();
    return _rows.where((row) {
      final matchesStatus = _status == 'all' || row.status == _status;
      final matchesZone = _zone == 'all' || row.zone == _zone;
      final matchesSearch =
          q.isEmpty ||
          row.branchName.toLowerCase().contains(q) ||
          row.zone.toLowerCase().contains(q) ||
          row.area.toLowerCase().contains(q) ||
          row.branchType.toLowerCase().contains(q);
      return matchesStatus && matchesZone && matchesSearch;
    }).toList();
  }

  List<String> get _zones {
    final values =
        _rows
            .map((row) => row.zone)
            .where((zone) => zone.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return values;
  }

  Future<void> _pickDateRange() async {
    final picked = await showDialog<DateTimeRange>(
      context: context,
      builder: (_) => StockCheckDateRangePickerDialog(
        initialRange: _range,
        mode: StockCheckDateRangePickerMode.history,
      ),
    );
    if (picked == null) return;
    setState(() => _range = picked);
    await _load(scanFirst: true);
  }

  Future<void> _export() async {
    final rows = _filteredRows;
    if (rows.isEmpty) return;
    setState(() => _exporting = true);
    try {
      await BranchSubmissionTrackerExcelExporter.export(
        rows: rows,
        from: _range.start,
        to: _range.end,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows;
    final notSubmitted = rows.where((row) => row.isNotSubmitted).length;
    final lateSubmitted = rows.where((row) => row.isLateSubmitted).length;
    final branches = rows.map((row) => row.branchName).toSet().length;
    final maxLate = rows.fold<int>(
      0,
      (max, row) => row.minutesLate > max ? row.minutesLate : max,
    );

    return Column(
      children: [
        _HeaderBar(
          total: rows.length,
          branches: branches,
          notSubmitted: notSubmitted,
          lateSubmitted: lateSubmitted,
          exporting: _exporting,
          onExport: rows.isEmpty ? null : _export,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            child: Column(
              children: [
                _ControlPanel(
                  range: _range,
                  loading: _loading || _scanning,
                  onDateRange: _pickDateRange,
                  onScan: _rescan,
                ),
                if (_message.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _InfoBanner(message: _message),
                ],
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ErrorBanner(error: _error),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        icon: Icons.report_problem_rounded,
                        title: 'Missed records',
                        value: '${rows.length}',
                        color: const Color(0xFFEF4444),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MetricCard(
                        icon: Icons.storefront_rounded,
                        title: 'Branches affected',
                        value: '$branches',
                        color: AppColors.primaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MetricCard(
                        icon: Icons.cancel_schedule_send_rounded,
                        title: 'Not submitted',
                        value: '$notSubmitted',
                        color: const Color(0xFFF97316),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MetricCard(
                        icon: Icons.schedule_send_rounded,
                        title: 'Not submitted by branch',
                        value: '$lateSubmitted',
                        color: const Color(0xFF7C3AED),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MetricCard(
                        icon: Icons.timer_rounded,
                        title: 'Max late',
                        value: _lateLabel(maxLate),
                        color: const Color(0xFF0F766E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _ReportCard(
                  rows: rows,
                  zones: _zones,
                  selectedStatus: _status,
                  selectedZone: _zone,
                  searchController: _searchController,
                  loading: _loading,
                  onStatusChanged: (value) =>
                      setState(() => _status = value ?? 'all'),
                  onZoneChanged: (value) =>
                      setState(() => _zone = value ?? 'all'),
                  onSearchChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  static String _dbDate(DateTime value) =>
      DateFormat('yyyy-MM-dd').format(value);
  static String _displayDate(DateTime value) =>
      DateFormat('dd/MM/yyyy').format(value);
  static String _lateLabel(int minutes) {
    if (minutes <= 0) return '0m';
    final days = minutes ~/ 1440;
    final hours = (minutes % 1440) ~/ 60;
    if (days > 0) return '${days}d ${hours}h';
    return '${hours}h';
  }
}

class _HeaderBar extends StatelessWidget {
  final int total;
  final int branches;
  final int notSubmitted;
  final int lateSubmitted;
  final bool exporting;
  final VoidCallback? onExport;

  const _HeaderBar({
    required this.total,
    required this.branches,
    required this.notSubmitted,
    required this.lateSubmitted,
    required this.exporting,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD9E8F5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.assignment_late_rounded,
              color: Color(0xFF2563EB),
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Branch Submission Tracker',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Track branches that missed the daily order submission deadline, even if they submitted later.',
                  style: TextStyle(
                    color: AppColors.subText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _HeaderStat(label: 'Records', value: '$total'),
          _HeaderStat(label: 'Branches', value: '$branches'),
          _HeaderStat(label: 'Not submitted', value: '$notSubmitted'),
          _HeaderStat(label: 'After deadline', value: '$lateSubmitted'),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: exporting ? null : onExport,
            icon: exporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            label: Text(exporting ? 'Exporting...' : 'Export Report'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final String label;
  final String value;

  const _HeaderStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 82,
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.subText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  final DateTimeRange range;
  final bool loading;
  final VoidCallback onDateRange;
  final VoidCallback onScan;

  const _ControlPanel({
    required this.range,
    required this.loading,
    required this.onDateRange,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD9E8F5)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.manage_search_rounded,
              color: AppColors.primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Submission audit window',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.text,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Default report range is one full year. New tracker records are created only from the activation date forward.',
                  style: TextStyle(
                    color: AppColors.subText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: loading ? null : onDateRange,
            icon: const Icon(Icons.calendar_month_rounded),
            label: Text(
              '${_fmt(range.start)}  to  ${_fmt(range.end)}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.secondaryColor,
              side: const BorderSide(color: Color(0xFFBAE6FD)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: loading ? null : onScan,
            icon: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.sync_rounded),
            label: Text(loading ? 'Scanning...' : 'Scan now'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.secondaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime value) => DateFormat('dd/MM/yyyy').format(value);
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.subText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatefulWidget {
  final List<BranchSubmissionMiss> rows;
  final List<String> zones;
  final String selectedStatus;
  final String selectedZone;
  final TextEditingController searchController;
  final bool loading;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String?> onZoneChanged;
  final ValueChanged<String> onSearchChanged;

  const _ReportCard({
    required this.rows,
    required this.zones,
    required this.selectedStatus,
    required this.selectedZone,
    required this.searchController,
    required this.loading,
    required this.onStatusChanged,
    required this.onZoneChanged,
    required this.onSearchChanged,
  });

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  final Map<String, double> _columnWidths = {
    'runDate': 120,
    'branch': 210,
    'zone': 120,
    'area': 140,
    'expectedBy': 175,
    'submittedAt': 175,
    'status': 190,
    'minutesLate': 120,
    'zoneManager': 190,
    'type': 140,
  };

  @override
  Widget build(BuildContext context) {
    final source = _SubmissionTrackerGridSource(widget.rows);
    final gridHeight = widget.rows.length < 8
        ? 112.0 + (widget.rows.length * 58.0)
        : 620.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD9E8F5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.table_chart_rounded, color: Color(0xFF2563EB)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Missed submission report',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              SizedBox(
                width: 300,
                child: TextField(
                  controller: widget.searchController,
                  onChanged: widget.onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search branch, zone, area...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFD9E8F5)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFD9E8F5)),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),
              _FilterDropDown(
                width: 170,
                label: 'Zone',
                value: widget.selectedZone,
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('All zones'),
                  ),
                  ...widget.zones.map(
                    (zone) => DropdownMenuItem(value: zone, child: Text(zone)),
                  ),
                ],
                onChanged: widget.onZoneChanged,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (widget.loading)
            const Padding(
              padding: EdgeInsets.all(36),
              child: CircularProgressIndicator(color: AppColors.primaryColor),
            )
          else if (widget.rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(42),
              child: Text(
                'No missed submissions match the current filters.',
                style: TextStyle(
                  color: AppColors.subText,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          else
            SizedBox(
              height: gridHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SfDataGridTheme(
                  data: SfDataGridThemeData(
                    headerColor: const Color(0xFFEAF4FF),
                    gridLineColor: const Color(0xFFDCEBFF),
                    filterIconColor: AppColors.secondaryColor,
                    sortIconColor: AppColors.primaryColor,
                    selectionColor: AppColors.primaryColor.withValues(
                      alpha: .08,
                    ),
                  ),
                  child: SfDataGrid(
                    source: source,
                    allowSorting: true,
                    allowMultiColumnSorting: true,
                    allowTriStateSorting: true,
                    allowFiltering: true,
                    allowColumnsResizing: true,
                    columnResizeMode: ColumnResizeMode.onResize,
                    gridLinesVisibility: GridLinesVisibility.both,
                    headerGridLinesVisibility: GridLinesVisibility.both,
                    frozenColumnsCount: 2,
                    rowHeight: 58,
                    headerRowHeight: 56,
                    columnWidthMode: ColumnWidthMode.none,
                    onColumnResizeUpdate: (details) {
                      setState(() {
                        _columnWidths[details.column.columnName] =
                            details.width;
                      });
                      return true;
                    },
                    columns: _columns(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<GridColumn> _columns() {
    GridColumn column(String name, String label) {
      return GridColumn(
        columnName: name,
        width: _columnWidths[name] ?? 140,
        label: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.headerText,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
      );
    }

    return [
      column('runDate', 'Run Date'),
      column('branch', 'Branch'),
      column('zone', 'Zone'),
      column('area', 'Area'),
      column('expectedBy', 'Expected By'),
      column('submittedAt', 'Submitted At'),
      column('status', 'Status'),
      column('minutesLate', 'Delay'),
      column('zoneManager', 'Zone Manager'),
      column('type', 'Type'),
    ];
  }
}

class _FilterDropDown extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  const _FilterDropDown({
    required this.width,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        items: items,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD9E8F5)),
          ),
        ),
      ),
    );
  }
}

class _SubmissionTrackerGridSource extends DataGridSource {
  final List<DataGridRow> _rows;

  _SubmissionTrackerGridSource(List<BranchSubmissionMiss> rows)
    : _rows = rows
          .map(
            (row) => DataGridRow(
              cells: [
                DataGridCell<String>(
                  columnName: 'runDate',
                  value: _date(row.runDate),
                ),
                DataGridCell<String>(
                  columnName: 'branch',
                  value: row.branchName,
                ),
                DataGridCell<String>(columnName: 'zone', value: row.zone),
                DataGridCell<String>(columnName: 'area', value: row.area),
                DataGridCell<String>(
                  columnName: 'expectedBy',
                  value: _dateTime(row.expectedSubmitBy),
                ),
                DataGridCell<String>(
                  columnName: 'submittedAt',
                  value: row.submittedAt == null
                      ? '-'
                      : _dateTime(row.submittedAt!),
                ),
                DataGridCell<String>(
                  columnName: 'status',
                  value: _statusLabel(row.status),
                ),
                DataGridCell<int>(
                  columnName: 'minutesLate',
                  value: row.minutesLate,
                ),
                DataGridCell<String>(
                  columnName: 'zoneManager',
                  value: row.zoneManager,
                ),
                DataGridCell<String>(columnName: 'type', value: row.branchType),
              ],
            ),
          )
          .toList();

  @override
  List<DataGridRow> get rows => _rows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final cells = row.getCells();
    return DataGridRowAdapter(
      color: Colors.white,
      cells: cells.map((cell) {
        if (cell.columnName == 'status') {
          return Center(child: _StatusChip(status: cell.value.toString()));
        }
        final text = cell.columnName == 'minutesLate'
            ? _late(cell.value as int)
            : cell.value.toString();
        return _SubmissionGridCell(
          text,
          strong:
              cell.columnName == 'branch' || cell.columnName == 'minutesLate',
        );
      }).toList(),
    );
  }

  static String _date(DateTime value) => DateFormat('dd/MM/yyyy').format(value);
  static String _dateTime(DateTime value) =>
      DateFormat('dd/MM/yyyy HH:mm').format(value.toLocal());
  static String _statusLabel(String status) => 'Not submitted by branch';
  static String _late(int minutes) {
    final days = minutes ~/ 1440;
    final hours = (minutes % 1440) ~/ 60;
    final mins = minutes % 60;
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = status == 'Not submitted by branch'
        ? const Color(0xFFDC2626)
        : const Color(0xFF7C3AED);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SubmissionGridCell extends StatelessWidget {
  final String text;
  final bool strong;

  const _SubmissionGridCell(this.text, {this.strong = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SelectableText(
        text,
        maxLines: 2,
        style: TextStyle(
          color: AppColors.text,
          fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String message;

  const _InfoBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return _Banner(
      message: message,
      icon: Icons.check_circle_rounded,
      color: const Color(0xFF059669),
      background: const Color(0xFFECFDF5),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String error;

  const _ErrorBanner({required this.error});

  @override
  Widget build(BuildContext context) {
    final missingTable =
        error.contains('branch_submission_misses') ||
        error.contains('PGRST205') ||
        error.contains('schema cache');

    return _Banner(
      message: missingTable
          ? 'Branch Submission Tracker table is not created in Supabase yet. Run supabase/sql/branch_submission_misses.sql once, then refresh this page.'
          : 'Could not load tracker. $error',
      icon: Icons.error_rounded,
      color: const Color(0xFFDC2626),
      background: const Color(0xFFFEF2F2),
    );
  }
}

class _Banner extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color color;
  final Color background;

  const _Banner({
    required this.message,
    required this.icon,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}
