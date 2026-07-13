import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final _scrollController = ScrollController();

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
    _scrollController.dispose();
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
            : 'Tracker updated for ${_fmtDate(_range.start)} to ${_fmtDate(_range.end)}.';
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
      _message = 'Scanning missed and late submissions...';
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

        final runDate = _fmtDate(day);
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
          .gte('run_date', _fmtDate(_range.start))
          .lte('run_date', _fmtDate(_range.end))
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
          .gte('run_date', _fmtDate(_range.start))
          .lte('run_date', _fmtDate(_range.end))
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
                        title: 'Late submitted',
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
                  scrollController: _scrollController,
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
  static String _fmtDate(DateTime value) =>
      DateFormat('yyyy-MM-dd').format(value);
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
          _HeaderStat(label: 'Not sent', value: '$notSubmitted'),
          _HeaderStat(label: 'Late', value: '$lateSubmitted'),
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

  static String _fmt(DateTime value) => DateFormat('yyyy-MM-dd').format(value);
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

class _ReportCard extends StatelessWidget {
  final List<BranchSubmissionMiss> rows;
  final List<String> zones;
  final String selectedStatus;
  final String selectedZone;
  final TextEditingController searchController;
  final ScrollController scrollController;
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
    required this.scrollController,
    required this.loading,
    required this.onStatusChanged,
    required this.onZoneChanged,
    required this.onSearchChanged,
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
                  controller: searchController,
                  onChanged: onSearchChanged,
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
                width: 185,
                label: 'Status',
                value: selectedStatus,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All status')),
                  DropdownMenuItem(
                    value: 'not_submitted',
                    child: Text('Not submitted'),
                  ),
                  DropdownMenuItem(
                    value: 'late_submitted',
                    child: Text('Late submitted'),
                  ),
                ],
                onChanged: onStatusChanged,
              ),
              const SizedBox(width: 10),
              _FilterDropDown(
                width: 170,
                label: 'Zone',
                value: selectedZone,
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('All zones'),
                  ),
                  ...zones.map(
                    (zone) => DropdownMenuItem(value: zone, child: Text(zone)),
                  ),
                ],
                onChanged: onZoneChanged,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(36),
              child: CircularProgressIndicator(color: AppColors.primaryColor),
            )
          else if (rows.isEmpty)
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
            Scrollbar(
              controller: scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: scrollController,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1320,
                  child: Column(
                    children: [
                      const _TableHeader(),
                      ...rows.take(500).map(_MissRow.new),
                      if (rows.length > 500)
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            'Showing first 500 row(s). Use filters or export for the full report.',
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.w900,
                            ),
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

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: const BoxDecoration(color: Color(0xFFEAF4FF)),
      child: const Row(
        children: [
          _Cell('Run Date', 110, header: true),
          _Cell('Branch', 190, header: true),
          _Cell('Zone', 105, header: true),
          _Cell('Area', 125, header: true),
          _Cell('Expected By', 170, header: true),
          _Cell('Submitted At', 170, header: true),
          _Cell('Status', 140, header: true),
          _Cell('Late', 95, header: true),
          _Cell('Zone Manager', 170, header: true),
          _Cell('Type', 145, header: true),
        ],
      ),
    );
  }
}

class _MissRow extends StatelessWidget {
  final BranchSubmissionMiss row;

  const _MissRow(this.row);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          _Cell(_date(row.runDate), 110),
          _Cell(row.branchName, 190, strong: true),
          _Cell(row.zone, 105),
          _Cell(row.area, 125),
          _Cell(_dateTime(row.expectedSubmitBy), 170),
          _Cell(
            row.submittedAt == null ? '-' : _dateTime(row.submittedAt!),
            170,
          ),
          SizedBox(
            width: 140,
            child: Center(child: _StatusChip(row: row)),
          ),
          _Cell(_late(row.minutesLate), 95, strong: true),
          _Cell(row.zoneManager, 170),
          _Cell(row.branchType, 145),
        ],
      ),
    );
  }

  static String _date(DateTime value) => DateFormat('yyyy-MM-dd').format(value);
  static String _dateTime(DateTime value) =>
      DateFormat('yyyy-MM-dd HH:mm').format(value.toLocal());
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
  final BranchSubmissionMiss row;

  const _StatusChip({required this.row});

  @override
  Widget build(BuildContext context) {
    final late = row.isLateSubmitted;
    final color = late ? const Color(0xFF7C3AED) : const Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Text(
        late ? 'Late submitted' : 'Not submitted',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String text;
  final double width;
  final bool header;
  final bool strong;

  const _Cell(
    this.text,
    this.width, {
    this.header = false,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      alignment: Alignment.centerLeft,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFFDCEBFF))),
      ),
      child: SelectableText(
        text,
        maxLines: header ? 1 : 2,
        style: TextStyle(
          color: header ? AppColors.headerText : AppColors.text,
          fontWeight: header || strong ? FontWeight.w900 : FontWeight.w700,
          fontSize: header ? 13 : 12.5,
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
