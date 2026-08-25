import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/fill_rate_kpi_excel_exporter_stub.dart'
    if (dart.library.html) '../../../core/utils/fill_rate_kpi_excel_exporter.dart';
import '../../../data/datasources/remote/fill_rate_kpi_remote_ds.dart';

class FillRateKpiPage extends StatefulWidget {
  final FillRateReport? previewReport;

  const FillRateKpiPage({super.key, this.previewReport});

  @override
  State<FillRateKpiPage> createState() => _FillRateKpiPageState();
}

class _FillRateKpiPageState extends State<FillRateKpiPage> {
  static const _allBranches = 'ALL BRANCHES';
  static const _pageSize = 200;

  FillRateKpiRemoteDs? _remote;
  final _searchController = TextEditingController();

  late DateTime _from;
  late DateTime _to;
  FillRateReport? _report;
  FillRateReport? _allReport;
  List<FillRateSummary> _allSummaries = const [];
  List<FillRateItem> _items = const [];
  String _selectedBranch = _allBranches;
  String _fulfillmentFilter = 'All';
  int _activeTab = 0;
  int _pageOffset = 0;
  int _totalItems = 0;
  bool _loading = true;
  bool _loadingItems = false;
  bool _exporting = false;
  double _exportProgress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    final yesterday = DateUtils.dateOnly(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    _from = yesterday;
    _to = yesterday;
    final preview = widget.previewReport;
    if (preview != null) {
      _report = preview;
      _allReport = preview;
      _allSummaries = preview.summaries;
      _items = preview.items;
      _totalItems = preview.items.isEmpty ? 0 : preview.items.first.totalCount;
      _loading = false;
      return;
    }
    _remote = FillRateKpiRemoteDs(Supabase.instance.client);
    _loadReport();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot reload preserves State, including report rows fetched before a
    // database-function update. Refresh automatically so the development UI
    // always reflects the latest server-side purchase statuses.
    if (widget.previewReport == null && _remote != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_loading) _loadReport();
      });
    }
  }

  FillRateSummary get _selectedSummary =>
      _report?.total ?? FillRateSummary.empty(_selectedBranch);

  List<FillRateItem> get _visibleItems {
    final search = _searchController.text.trim().toLowerCase();
    return _items
        .where((item) {
          if (_fulfillmentFilter != 'All' &&
              item.fulfillmentStatus != _fulfillmentFilter) {
            return false;
          }
          if (search.isEmpty) return true;
          return item.itemCode.toLowerCase().contains(search) ||
              item.itemName.toLowerCase().contains(search) ||
              item.branchName.toLowerCase().contains(search) ||
              item.purchaseStatus.toLowerCase().contains(search);
        })
        .toList(growable: false);
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _error = null;
      _pageOffset = 0;
    });
    try {
      final report = await _remote!.fetchReport(
        from: _from,
        to: _to,
        branch: _selectedBranch,
        detailLimit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _items = report.items;
        _totalItems = report.items.isEmpty ? 0 : report.items.first.totalCount;
        if (_selectedBranch == _allBranches) {
          _allReport = report;
          _allSummaries = report.summaries;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _selectBranch(String branch) async {
    if (branch == _selectedBranch && _report != null) return;
    setState(() {
      _selectedBranch = branch;
      _activeTab = 0;
      _fulfillmentFilter = 'All';
      _searchController.clear();
    });
    await _loadReport();
  }

  Future<void> _loadItemsPage(int offset) async {
    if (_loadingItems || offset < 0 || offset >= _totalItems) return;
    setState(() => _loadingItems = true);
    try {
      final page = await _remote!.fetchItemsPage(
        from: _from,
        to: _to,
        branch: _selectedBranch,
        offset: offset,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _totalItems = page.totalCount;
        _pageOffset = offset;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load product page: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingItems = false);
    }
  }

  Future<void> _pickDates() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateUtils.dateOnly(
        DateTime.now().subtract(const Duration(days: 1)),
      ),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: 'Select Fill Rate period',
    );
    if (picked == null) return;
    setState(() {
      _from = picked.start;
      _to = picked.end;
      _selectedBranch = _allBranches;
      _allReport = null;
      _allSummaries = const [];
    });
    await _loadReport();
  }

  Future<void> _export() async {
    final report = _report;
    if (report == null || _exporting) return;
    setState(() {
      _exporting = true;
      _exportProgress = 0;
    });
    try {
      final items = await _remote!.fetchAllItems(
        from: _from,
        to: _to,
        branch: _selectedBranch,
        onProgress: (value) {
          if (mounted) setState(() => _exportProgress = value * .8);
        },
      );
      if (mounted) setState(() => _exportProgress = .9);
      await FillRateKpiExcelExporter.export(
        from: _from,
        to: _to,
        branch: _selectedBranch,
        report: report,
        items: items,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${items.length} product rows.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return ColoredBox(
      color: const Color(0xffF4F7FB),
      child: Column(
        children: [
          _Header(
            from: _from,
            to: _to,
            branchCount: math.max(0, _allSummaries.length - 1),
            loading: _loading,
            exporting: _exporting,
            exportProgress: _exportProgress,
            onDates: _pickDates,
            onRefresh: _loadReport,
            onExport: _export,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 1050;
                if (_loading && report == null) {
                  return const _LoadingCard();
                }
                if (_error != null && report == null) {
                  return _ErrorView(message: _error!, onRetry: _loadReport);
                }
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 14 : 20,
                    14,
                    compact ? 14 : 20,
                    28,
                  ),
                  children: [
                    if (_error != null) ...[
                      _ErrorBanner(message: _error!, onRetry: _loadReport),
                      const SizedBox(height: 16),
                    ],
                    const _MethodCard(),
                    const SizedBox(height: 12),
                    _ReportTabs(
                      selectedIndex: _activeTab,
                      onChanged: (value) => setState(() => _activeTab = value),
                    ),
                    const SizedBox(height: 12),
                    if (_activeTab == 1)
                      _ManagementReport(
                        report: _allReport ?? report,
                        summaries: _allSummaries.isEmpty
                            ? (report?.summaries ?? const [])
                            : _allSummaries,
                        onOpenBranch: _selectBranch,
                      )
                    else ...[
                      _BranchOverview(
                        summaries: _allSummaries.isEmpty
                            ? (report?.summaries ?? const [])
                            : _allSummaries,
                        selectedBranch: _selectedBranch,
                        onSelected: _selectBranch,
                      ),
                      const SizedBox(height: 12),
                      _SummaryCards(
                        branch: _selectedBranch,
                        summary: _selectedSummary,
                      ),
                      const SizedBox(height: 12),
                      _ProductFilters(
                        controller: _searchController,
                        fulfillment: _fulfillmentFilter,
                        onSearchChanged: (_) => setState(() {}),
                        onFulfillmentChanged: (value) =>
                            setState(() => _fulfillmentFilter = value),
                      ),
                      const SizedBox(height: 10),
                      _ProductTable(
                        branch: _selectedBranch,
                        items: _visibleItems,
                        pageOffset: _pageOffset,
                        pageSize: _pageSize,
                        totalItems: _totalItems,
                        loading: _loading || _loadingItems,
                        onRefresh: _loadReport,
                        onPrevious: _pageOffset == 0
                            ? null
                            : () => _loadItemsPage(
                                math.max(0, _pageOffset - _pageSize),
                              ),
                        onNext: _pageOffset + _pageSize >= _totalItems
                            ? null
                            : () => _loadItemsPage(_pageOffset + _pageSize),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final DateTime from;
  final DateTime to;
  final int branchCount;
  final bool loading;
  final bool exporting;
  final double exportProgress;
  final VoidCallback onDates;
  final VoidCallback onRefresh;
  final VoidCallback onExport;

  const _Header({
    required this.from,
    required this.to,
    required this.branchCount,
    required this.loading,
    required this.exporting,
    required this.exportProgress,
    required this.onDates,
    required this.onRefresh,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 15, 24, 15),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xff172554), Color(0xff1D4ED8), Color(0xff0EA5E9)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: .22)),
            ),
            child: const Icon(
              Icons.local_shipping_rounded,
              color: Colors.white,
              size: 25,
            ),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fill Rate KPI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.3,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'STORE refill fulfillment • Branch and product performance',
                  style: TextStyle(
                    color: Color(0xffDBEAFE),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _HeaderBadge(
            icon: Icons.storefront_rounded,
            label: '$branchCount branches',
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: loading ? null : onDates,
            icon: const Icon(Icons.calendar_month_rounded, size: 19),
            label: Text('${_shortDate(from)}  →  ${_shortDate(to)}'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white54,
              side: BorderSide(color: Colors.white.withValues(alpha: .45)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
          ),
          const SizedBox(width: 10),
          IconButton.filled(
            onPressed: loading ? null : onRefresh,
            tooltip: 'Refresh report',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: .16),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: loading || exporting ? null : onExport,
            icon: exporting
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.file_download_outlined, size: 20),
            label: Text(
              exporting
                  ? 'Exporting ${(exportProgress * 100).round()}%'
                  : 'Export Excel',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff059669),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeaderBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: .2)),
    ),
    child: Row(
      children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _MethodCard extends StatelessWidget {
  const _MethodCard();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
    decoration: BoxDecoration(
      color: const Color(0xffEFF6FF),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xffBFDBFE)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.calculate_outlined, color: Color(0xff1D4ED8), size: 20),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How Fill Rate is calculated',
                style: TextStyle(
                  color: Color(0xff1E3A8A),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Required qty uses the approved branch edit when available; otherwise it uses Reorder Qty. Zero or negative values are excluded. '
                'Only Approved transfers from STORE matching the same date, branch and item are counted. '
                'Unit Fill Rate = total transferred quantity capped at each item\'s effective Reorder Qty ÷ total effective Reorder Qty × 100. Transfers above the effective Reorder Qty are ignored.',
                style: TextStyle(
                  color: Color(0xff334E7D),
                  height: 1.32,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ReportTabs extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _ReportTabs({required this.selectedIndex, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(5),
    decoration: BoxDecoration(
      color: const Color(0xffE8EEF7),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Row(
      children: [
        Expanded(
          child: _ReportTabButton(
            selected: selectedIndex == 0,
            icon: Icons.inventory_2_outlined,
            title: 'Branch Products',
            subtitle: 'Select a branch and review every refill product',
            onTap: () => onChanged(0),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _ReportTabButton(
            selected: selectedIndex == 1,
            icon: Icons.assessment_outlined,
            title: 'Management Report',
            subtitle: 'Compare ALL BRANCHES and open any branch',
            onTap: () => onChanged(1),
          ),
        ),
      ],
    ),
  );
}

class _ReportTabButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ReportTabButton({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? Colors.white : Colors.transparent,
    borderRadius: BorderRadius.circular(11),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          border: selected ? Border.all(color: const Color(0xffCBD5E1)) : null,
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x120F172A),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected
                  ? AppColors.primaryColor
                  : const Color(0xff64748B),
              size: 23,
            ),
            const SizedBox(width: 11),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xff0F172A)
                        : const Color(0xff475569),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _BranchOverview extends StatelessWidget {
  final List<FillRateSummary> summaries;
  final String selectedBranch;
  final ValueChanged<String> onSelected;

  const _BranchOverview({
    required this.summaries,
    required this.selectedBranch,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (summaries.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 11, 15, 9),
            child: Row(
              children: [
                const Icon(
                  Icons.storefront_outlined,
                  color: AppColors.primaryColor,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Branch',
                        style: TextStyle(
                          color: Color(0xff0F172A),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'ALL BRANCHES shows the company result. Select a branch to open its products.',
                        style: TextStyle(
                          color: Color(0xff64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xffEFF6FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${math.max(0, summaries.length - 1)} branches',
                    style: const TextStyle(
                      color: Color(0xff1D4ED8),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 146,
            child: ListView.separated(
              padding: const EdgeInsets.all(10),
              scrollDirection: Axis.horizontal,
              itemCount: summaries.length,
              separatorBuilder: (_, _) => const SizedBox(width: 11),
              itemBuilder: (context, index) {
                final summary = summaries[index];
                return _BranchCard(
                  summary: summary,
                  selected: selectedBranch == summary.branchName,
                  allBranches: summary.branchName == 'ALL BRANCHES',
                  onTap: () => onSelected(summary.branchName),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  final FillRateSummary summary;
  final bool selected;
  final bool allBranches;
  final VoidCallback onTap;

  const _BranchCard({
    required this.summary,
    required this.selected,
    required this.allBranches,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = _rateColor(summary.unitFillRate);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: allBranches ? 238 : 210,
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            gradient: allBranches && selected
                ? const LinearGradient(
                    colors: [Color(0xff172554), Color(0xff1D4ED8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: allBranches && selected
                ? null
                : selected
                ? const Color(0xffEFF6FF)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? allBranches
                        ? const Color(0xff1D4ED8)
                        : const Color(0xff60A5FA)
                  : const Color(0xffDCE3EC),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x161D4ED8),
                      blurRadius: 14,
                      offset: Offset(0, 5),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    allBranches ? Icons.apartment_rounded : Icons.store_rounded,
                    color: allBranches && selected
                        ? Colors.white
                        : AppColors.primaryColor,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      summary.branchName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: allBranches && selected
                            ? Colors.white
                            : const Color(0xff0F172A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check_circle_rounded,
                      color: allBranches
                          ? Colors.white
                          : const Color(0xff2563EB),
                      size: 18,
                    ),
                ],
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_fmt(summary.unitFillRate)}%',
                        style: TextStyle(
                          color: allBranches && selected ? Colors.white : color,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      'Unit Fill',
                      style: TextStyle(
                        color: allBranches && selected
                            ? const Color(0xffBFDBFE)
                            : const Color(0xff64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: (summary.unitFillRate / 100).clamp(0, 1).toDouble(),
                  minHeight: 5,
                  color: allBranches && selected ? Colors.white : color,
                  backgroundColor: allBranches && selected
                      ? Colors.white.withValues(alpha: .18)
                      : color.withValues(alpha: .12),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${summary.suppliedItems} supplied of ${summary.totalItems} products',
                style: TextStyle(
                  color: allBranches && selected
                      ? const Color(0xffDBEAFE)
                      : const Color(0xff64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  final String branch;
  final FillRateSummary summary;

  const _SummaryCards({required this.branch, required this.summary});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1050;
        final width = compact
            ? (constraints.maxWidth - 12) / 2
            : (constraints.maxWidth - 48) / 5;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _RateSummaryCard(width: width, branch: branch, summary: summary),
            _SummaryMetricCard(
              width: width,
              label: 'Required Products',
              value: _integer(summary.totalItems),
              detail: '${_fmt(summary.requiredQty)} units requested',
              icon: Icons.shopping_cart_checkout_rounded,
              color: const Color(0xff2563EB),
            ),
            _SummaryMetricCard(
              width: width,
              label: 'Fully Supplied',
              value: _integer(summary.fullySupplied),
              detail: _share(summary.fullySupplied, summary.totalItems),
              icon: Icons.verified_rounded,
              color: const Color(0xff059669),
            ),
            _SummaryMetricCard(
              width: width,
              label: 'Partially Supplied',
              value: _integer(summary.partiallySupplied),
              detail: _share(summary.partiallySupplied, summary.totalItems),
              icon: Icons.timelapse_rounded,
              color: const Color(0xffD97706),
            ),
            _SummaryMetricCard(
              width: width,
              label: 'Not Supplied',
              value: _integer(summary.notSupplied),
              detail: _share(summary.notSupplied, summary.totalItems),
              icon: Icons.remove_shopping_cart_rounded,
              color: const Color(0xffDC2626),
            ),
          ],
        );
      },
    );
  }
}

class _RateSummaryCard extends StatelessWidget {
  final double width;
  final String branch;
  final FillRateSummary summary;

  const _RateSummaryCard({
    required this.width,
    required this.branch,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final color = _rateColor(summary.unitFillRate);
    return Container(
      width: width,
      height: 146,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xff0F172A), Color(0xff1E3A8A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(17),
        boxShadow: const [
          BoxShadow(
            color: Color(0x241E3A8A),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            branch,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xffBFDBFE),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${_fmt(summary.unitFillRate)}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Text(
            'Unit Fill Rate',
            style: TextStyle(
              color: Color(0xffDBEAFE),
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Text(
                'Line Fill ${_fmt(summary.lineFillRate)}%',
                style: const TextStyle(
                  color: Color(0xffCBD5E1),
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
}

class _SummaryMetricCard extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;

  const _SummaryMetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 146,
    padding: const EdgeInsets.all(13),
    decoration: _cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xff334155),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          detail,
          style: const TextStyle(color: Color(0xff64748B), fontSize: 11),
        ),
      ],
    ),
  );
}

class _ProductFilters extends StatelessWidget {
  final TextEditingController controller;
  final String fulfillment;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onFulfillmentChanged;

  const _ProductFilters({
    required this.controller,
    required this.fulfillment,
    required this.onSearchChanged,
    required this.onFulfillmentChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: _cardDecoration(),
    child: Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 360,
          child: TextField(
            controller: controller,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search product on this page...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        controller.clear();
                        onSearchChanged('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: const Color(0xffF8FAFC),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xffCBD5E1)),
              ),
            ),
          ),
        ),
        _FilterChip(
          label: 'All Products',
          color: AppColors.primaryColor,
          selected: fulfillment == 'All',
          onTap: () => onFulfillmentChanged('All'),
        ),
        _FilterChip(
          label: 'Fully Supplied',
          color: const Color(0xff059669),
          selected: fulfillment == 'Fully Supplied',
          onTap: () => onFulfillmentChanged('Fully Supplied'),
        ),
        _FilterChip(
          label: 'Partially Supplied',
          color: const Color(0xffD97706),
          selected: fulfillment == 'Partially Supplied',
          onTap: () => onFulfillmentChanged('Partially Supplied'),
        ),
        _FilterChip(
          label: 'Not Supplied',
          color: const Color(0xffDC2626),
          selected: fulfillment == 'Not Supplied',
          onTap: () => onFulfillmentChanged('Not Supplied'),
        ),
      ],
    ),
  );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => FilterChip(
    selected: selected,
    onSelected: (_) => onTap(),
    label: Text(label),
    showCheckmark: false,
    selectedColor: color,
    backgroundColor: Colors.white,
    side: BorderSide(color: selected ? color : const Color(0xffCBD5E1)),
    labelStyle: TextStyle(
      color: selected ? Colors.white : const Color(0xff475569),
      fontWeight: FontWeight.w800,
    ),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  );
}

class _ProductTable extends StatefulWidget {
  final String branch;
  final List<FillRateItem> items;
  final int pageOffset;
  final int pageSize;
  final int totalItems;
  final bool loading;
  final VoidCallback onRefresh;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _ProductTable({
    required this.branch,
    required this.items,
    required this.pageOffset,
    required this.pageSize,
    required this.totalItems,
    required this.loading,
    required this.onRefresh,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  State<_ProductTable> createState() => _ProductTableState();
}

class _ProductTableState extends State<_ProductTable> {
  late _ProductGridSource _source;

  @override
  void initState() {
    super.initState();
    _source = _ProductGridSource(widget.items);
  }

  @override
  void didUpdateWidget(covariant _ProductTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) _source.update(widget.items);
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.totalItems == 0 ? 0 : widget.pageOffset + 1;
    final last = math.min(
      widget.totalItems,
      widget.pageOffset + widget.pageSize,
    );
    return Container(
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 11, 12, 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      color: AppColors.primaryColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.branch} • Refill Products',
                            style: const TextStyle(
                              color: Color(0xff0F172A),
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Excel filters are in every header. Drag a header edge to resize. * = edited quantity.',
                            style: TextStyle(
                              color: Color(0xff64748B),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '$first–$last of ${widget.totalItems} products',
                      style: const TextStyle(
                        color: Color(0xff475569),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 9),
                    IconButton.outlined(
                      onPressed: widget.loading ? null : widget.onRefresh,
                      tooltip: 'Refresh latest report data',
                      icon: const Icon(Icons.refresh_rounded, size: 19),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _source.clearFilters,
                      icon: const Icon(Icons.filter_alt_off_rounded, size: 17),
                      label: const Text('Clear filters'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.outlined(
                      onPressed: widget.onPrevious,
                      tooltip: 'Previous products',
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    const SizedBox(width: 7),
                    IconButton.outlined(
                      onPressed: widget.onNext,
                      tooltip: 'Next products',
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              SizedBox(
                height: 520,
                child: widget.items.isEmpty
                    ? const _EmptyProducts()
                    : SfDataGridTheme(
                        data: SfDataGridThemeData(
                          headerColor: const Color(0xffE8F1FB),
                          gridLineColor: const Color(0xffD9E2EC),
                          gridLineStrokeWidth: .7,
                          sortIconColor: AppColors.primaryColor,
                          filterIconColor: AppColors.primaryColor,
                          filterIconHoverColor: const Color(0xff0EA5E9),
                          rowHoverColor: const Color(0xffEFF6FF),
                        ),
                        child: SfDataGrid(
                          source: _source,
                          columns: _productColumns,
                          allowFiltering: true,
                          allowSorting: true,
                          allowMultiColumnSorting: true,
                          allowTriStateSorting: true,
                          allowColumnsResizing: true,
                          columnResizeMode: ColumnResizeMode.onResize,
                          gridLinesVisibility: GridLinesVisibility.both,
                          headerGridLinesVisibility: GridLinesVisibility.both,
                          rowHeight: 50,
                          headerRowHeight: 54,
                          frozenColumnsCount: 3,
                          columnWidthMode: ColumnWidthMode.none,
                          isScrollbarAlwaysShown: true,
                          navigationMode: GridNavigationMode.cell,
                          selectionMode: SelectionMode.single,
                        ),
                      ),
              ),
            ],
          ),
          if (widget.loading)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.white70,
                child: const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

final List<GridColumn> _productColumns = [
  _gridColumn('branch', 'Branch', 210, alignLeft: true),
  _gridColumn('code', 'Item Code', 145, alignLeft: true),
  _gridColumn('name', 'Product Name', 310, alignLeft: true),
  _gridColumn('date', 'Order Date', 130),
  _gridColumn('required', 'Reorder\nQty', 125),
  _gridColumn('transfer', 'Transfer from\nStore', 155),
  _gridColumn('fill_rate', 'Fill Rate', 150),
  _gridColumn('result', 'Fulfillment Status', 190),
  _gridColumn('purchase', 'Purchase Status', 225),
];

GridColumn _gridColumn(
  String name,
  String label,
  double width, {
  bool alignLeft = false,
}) => GridColumn(
  columnName: name,
  width: width,
  label: Container(
    alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 13),
    child: Text(
      label,
      textAlign: alignLeft ? TextAlign.left : TextAlign.center,
      style: const TextStyle(
        color: Color(0xff1E3A5F),
        fontSize: 12,
        fontWeight: FontWeight.w900,
      ),
    ),
  ),
);

class _ProductGridSource extends DataGridSource {
  List<DataGridRow> _rows = const [];
  final Map<DataGridRow, FillRateItem> _itemByRow = {};
  final Map<DataGridRow, int> _indexByRow = {};

  _ProductGridSource(List<FillRateItem> items) {
    update(items);
  }

  void update(List<FillRateItem> items) {
    _itemByRow.clear();
    _indexByRow.clear();
    _rows = items
        .asMap()
        .entries
        .map((entry) {
          final item = entry.value;
          final row = DataGridRow(
            cells: [
              DataGridCell<String>(
                columnName: 'branch',
                value: item.branchName,
              ),
              DataGridCell<String>(columnName: 'code', value: item.itemCode),
              DataGridCell<String>(columnName: 'name', value: item.itemName),
              DataGridCell<String>(
                columnName: 'date',
                value: _isoDate(item.date),
              ),
              DataGridCell<num>(
                columnName: 'required',
                value: item.requiredQty,
              ),
              DataGridCell<num>(
                columnName: 'transfer',
                value: item.transferredQty,
              ),
              DataGridCell<num>(columnName: 'fill_rate', value: item.fillRate),
              DataGridCell<String>(
                columnName: 'result',
                value: item.fulfillmentStatus,
              ),
              DataGridCell<String>(
                columnName: 'purchase',
                value: item.purchaseStatus,
              ),
            ],
          );
          _itemByRow[row] = item;
          _indexByRow[row] = entry.key;
          return row;
        })
        .toList(growable: false);
    notifyListeners();
  }

  @override
  List<DataGridRow> get rows => _rows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final item = _itemByRow[row]!;
    final rowColor = (_indexByRow[row] ?? 0).isOdd
        ? const Color(0xffFAFCFE)
        : Colors.white;
    return DataGridRowAdapter(
      color: rowColor,
      cells: row
          .getCells()
          .map((cell) {
            Widget child;
            switch (cell.columnName) {
              case 'code':
                child = SelectableText(
                  '${cell.value}',
                  style: const TextStyle(
                    color: Color(0xff1D4ED8),
                    fontWeight: FontWeight.w900,
                  ),
                );
              case 'name':
                child = Tooltip(
                  message: item.itemName,
                  child: Text(
                    item.itemName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff0F172A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              case 'required':
                child = Text(
                  _fmt(item.requiredQty),
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontWeight: FontWeight.w900,
                  ),
                );
              case 'fill_rate':
                final color = _rateColor(item.fillRate);
                child = Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 45,
                      child: LinearProgressIndicator(
                        value: (item.fillRate / 100).clamp(0, 1).toDouble(),
                        minHeight: 6,
                        color: color,
                        backgroundColor: color.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_fmt(item.fillRate)}%',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                );
              case 'result':
                child = _StatusPill(
                  label: item.fulfillmentStatus,
                  color: _fulfillmentColor(item.fulfillmentStatus),
                );
              case 'purchase':
                child = _StatusPill(
                  label: item.purchaseStatus,
                  color: _purchaseColor(item.purchaseStatus),
                );
              default:
                child = Text(
                  cell.value is num ? _fmt(cell.value as num) : '${cell.value}',
                  textAlign: cell.columnName == 'branch'
                      ? TextAlign.left
                      : TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff334155),
                    fontWeight: FontWeight.w700,
                  ),
                );
            }
            return Container(
              alignment:
                  cell.columnName == 'code' ||
                      cell.columnName == 'name' ||
                      cell.columnName == 'branch'
                  ? Alignment.centerLeft
                  : Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: child,
            );
          })
          .toList(growable: false),
    );
  }
}

class _ManagementReport extends StatelessWidget {
  final FillRateReport? report;
  final List<FillRateSummary> summaries;
  final ValueChanged<String> onOpenBranch;

  const _ManagementReport({
    required this.report,
    required this.summaries,
    required this.onOpenBranch,
  });

  @override
  Widget build(BuildContext context) {
    if (report == null || summaries.isEmpty) {
      return const _EmptyProducts();
    }
    final total = summaries.firstWhere(
      (row) => row.branchName == 'ALL BRANCHES',
      orElse: () => FillRateSummary.empty('ALL BRANCHES'),
    );
    final branches = summaries
        .where((row) => row.branchName != 'ALL BRANCHES')
        .toList(growable: false);
    final average = branches.isEmpty
        ? 0
        : branches.fold<num>(0, (sum, row) => sum + row.unitFillRate) /
              branches.length;
    final atLeast90 = branches.where((row) => row.unitFillRate >= 90).length;
    final below70 = branches.where((row) => row.unitFillRate < 70).length;
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth < 900
                ? (constraints.maxWidth - 12) / 2
                : (constraints.maxWidth - 36) / 4;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ManagementMetric(
                  width: width,
                  label: 'ALL BRANCHES Unit Fill',
                  value: '${_fmt(total.unitFillRate)}%',
                  detail: 'Company-wide quantity fulfillment',
                  color: _rateColor(total.unitFillRate),
                  icon: Icons.apartment_rounded,
                ),
                _ManagementMetric(
                  width: width,
                  label: 'Average Branch Rate',
                  value: '${_fmt(average)}%',
                  detail: '${branches.length} branches in comparison',
                  color: const Color(0xff2563EB),
                  icon: Icons.analytics_outlined,
                ),
                _ManagementMetric(
                  width: width,
                  label: '90% and Above',
                  value: '$atLeast90',
                  detail: 'Branches meeting the target band',
                  color: const Color(0xff059669),
                  icon: Icons.verified_rounded,
                ),
                _ManagementMetric(
                  width: width,
                  label: 'Below 70%',
                  value: '$below70',
                  detail: 'Branches needing immediate attention',
                  color: const Color(0xffDC2626),
                  icon: Icons.warning_amber_rounded,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        _BranchReportTable(summaries: summaries, onOpenBranch: onOpenBranch),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) {
            final status = _StatusBreakdown(statuses: report!.statuses);
            final daily = _DailyTrend(rows: report!.daily);
            if (constraints.maxWidth < 1050) {
              return Column(
                children: [daily, const SizedBox(height: 18), status],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: daily),
                const SizedBox(width: 18),
                Expanded(child: status),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ManagementMetric extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final String detail;
  final Color color;
  final IconData icon;

  const _ManagementMetric({
    required this.width,
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: const EdgeInsets.all(17),
    decoration: _cardDecoration(),
    child: Row(
      children: [
        Container(
          width: 47,
          height: 47,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xff334155),
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xff64748B), fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _BranchReportTable extends StatefulWidget {
  final List<FillRateSummary> summaries;
  final ValueChanged<String> onOpenBranch;

  const _BranchReportTable({
    required this.summaries,
    required this.onOpenBranch,
  });

  @override
  State<_BranchReportTable> createState() => _BranchReportTableState();
}

class _BranchReportTableState extends State<_BranchReportTable> {
  late _BranchGridSource _source;

  @override
  void initState() {
    super.initState();
    _source = _BranchGridSource(
      widget.summaries,
      onOpenBranch: widget.onOpenBranch,
    );
  }

  @override
  void didUpdateWidget(covariant _BranchReportTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.summaries != widget.summaries) {
      _source.update(widget.summaries);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: _cardDecoration(),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(15, 11, 15, 10),
          child: Row(
            children: [
              const Icon(
                Icons.account_tree_outlined,
                color: AppColors.primaryColor,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fill Rate by Branch',
                      style: TextStyle(
                        color: Color(0xff0F172A),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'ALL BRANCHES is the company total. Click any branch name to review its products.',
                      style: TextStyle(color: Color(0xff64748B), fontSize: 11),
                    ),
                  ],
                ),
              ),
              Text(
                '${widget.summaries.length} report rows',
                style: const TextStyle(
                  color: Color(0xff64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        SizedBox(
          height: 540,
          child: SfDataGridTheme(
            data: SfDataGridThemeData(
              headerColor: const Color(0xffE8F1FB),
              gridLineColor: const Color(0xffD9E2EC),
              gridLineStrokeWidth: .7,
              sortIconColor: AppColors.primaryColor,
              filterIconColor: AppColors.primaryColor,
              filterIconHoverColor: const Color(0xff0EA5E9),
              rowHoverColor: const Color(0xffEFF6FF),
            ),
            child: SfDataGrid(
              source: _source,
              columns: _branchColumns,
              allowFiltering: true,
              allowSorting: true,
              allowMultiColumnSorting: true,
              allowTriStateSorting: true,
              allowColumnsResizing: true,
              columnResizeMode: ColumnResizeMode.onResize,
              gridLinesVisibility: GridLinesVisibility.both,
              headerGridLinesVisibility: GridLinesVisibility.both,
              rowHeight: 50,
              headerRowHeight: 54,
              frozenColumnsCount: 1,
              isScrollbarAlwaysShown: true,
              navigationMode: GridNavigationMode.cell,
              selectionMode: SelectionMode.single,
            ),
          ),
        ),
      ],
    ),
  );
}

final List<GridColumn> _branchColumns = [
  _gridColumn('branch', 'Branch', 245, alignLeft: true),
  _gridColumn('unit', 'Unit Fill\nRate', 170),
  _gridColumn('line', 'Line Fill\nRate', 160),
  _gridColumn('required', 'Required\nProducts', 145),
  _gridColumn('supplied', 'Supplied\nProducts', 145),
  _gridColumn('full', 'Fully\nSupplied', 135),
  _gridColumn('partial', 'Partially\nSupplied', 145),
  _gridColumn('not', 'Not\nSupplied', 135),
  _gridColumn('required_qty', 'Required\nUnits', 145),
  _gridColumn('supplied_qty', 'Supplied\nUnits', 145),
];

class _BranchGridSource extends DataGridSource {
  final ValueChanged<String> onOpenBranch;
  List<DataGridRow> _rows = const [];
  final Map<DataGridRow, FillRateSummary> _summaryByRow = {};
  final Map<DataGridRow, int> _indexByRow = {};

  _BranchGridSource(
    List<FillRateSummary> summaries, {
    required this.onOpenBranch,
  }) {
    update(summaries);
  }

  void update(List<FillRateSummary> summaries) {
    _summaryByRow.clear();
    _indexByRow.clear();
    _rows = summaries
        .asMap()
        .entries
        .map((entry) {
          final summary = entry.value;
          final row = DataGridRow(
            cells: [
              DataGridCell<String>(
                columnName: 'branch',
                value: summary.branchName,
              ),
              DataGridCell<num>(
                columnName: 'unit',
                value: summary.unitFillRate,
              ),
              DataGridCell<num>(
                columnName: 'line',
                value: summary.lineFillRate,
              ),
              DataGridCell<int>(
                columnName: 'required',
                value: summary.totalItems,
              ),
              DataGridCell<int>(
                columnName: 'supplied',
                value: summary.suppliedItems,
              ),
              DataGridCell<int>(
                columnName: 'full',
                value: summary.fullySupplied,
              ),
              DataGridCell<int>(
                columnName: 'partial',
                value: summary.partiallySupplied,
              ),
              DataGridCell<int>(columnName: 'not', value: summary.notSupplied),
              DataGridCell<num>(
                columnName: 'required_qty',
                value: summary.requiredQty,
              ),
              DataGridCell<num>(
                columnName: 'supplied_qty',
                value: summary.suppliedQty,
              ),
            ],
          );
          _summaryByRow[row] = summary;
          _indexByRow[row] = entry.key;
          return row;
        })
        .toList(growable: false);
    notifyListeners();
  }

  @override
  List<DataGridRow> get rows => _rows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final summary = _summaryByRow[row]!;
    final isAll = summary.branchName == 'ALL BRANCHES';
    final rowColor = isAll
        ? const Color(0xffEFF6FF)
        : (_indexByRow[row] ?? 0).isOdd
        ? const Color(0xffFAFCFE)
        : Colors.white;
    return DataGridRowAdapter(
      color: rowColor,
      cells: row
          .getCells()
          .map((cell) {
            Widget child;
            switch (cell.columnName) {
              case 'branch':
                child = InkWell(
                  onTap: () => onOpenBranch(summary.branchName),
                  child: Row(
                    children: [
                      Icon(
                        isAll
                            ? Icons.apartment_rounded
                            : Icons.storefront_outlined,
                        color: AppColors.primaryColor,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          summary.branchName,
                          maxLines: 2,
                          style: TextStyle(
                            color: const Color(0xff0F172A),
                            fontWeight: isAll
                                ? FontWeight.w900
                                : FontWeight.w800,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.open_in_new_rounded,
                        size: 14,
                        color: Color(0xff94A3B8),
                      ),
                    ],
                  ),
                );
              case 'unit':
              case 'line':
                final value = cell.value as num;
                final color = _rateColor(value);
                child = Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 58,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${_fmt(value)}%',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 38,
                      child: LinearProgressIndicator(
                        value: (value / 100).clamp(0, 1).toDouble(),
                        minHeight: 5,
                        color: color,
                        backgroundColor: color.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ],
                );
              case 'not':
                child = Text(
                  '${cell.value}',
                  style: const TextStyle(
                    color: Color(0xffDC2626),
                    fontWeight: FontWeight.w900,
                  ),
                );
              case 'partial':
                child = Text(
                  '${cell.value}',
                  style: const TextStyle(
                    color: Color(0xffD97706),
                    fontWeight: FontWeight.w900,
                  ),
                );
              case 'full':
                child = Text(
                  '${cell.value}',
                  style: const TextStyle(
                    color: Color(0xff059669),
                    fontWeight: FontWeight.w900,
                  ),
                );
              default:
                child = Text(
                  cell.value is num ? _fmt(cell.value as num) : '${cell.value}',
                  style: const TextStyle(
                    color: Color(0xff334155),
                    fontWeight: FontWeight.w700,
                  ),
                );
            }
            return Container(
              alignment: cell.columnName == 'branch'
                  ? Alignment.centerLeft
                  : Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: child,
            );
          })
          .toList(growable: false),
    );
  }
}

class _DailyTrend extends StatelessWidget {
  final List<FillRateDaily> rows;

  const _DailyTrend({required this.rows});

  @override
  Widget build(BuildContext context) => _InsightCard(
    icon: Icons.show_chart_rounded,
    title: 'Daily Fill Rate Trend',
    subtitle: 'Company performance across the selected date range',
    child: rows.isEmpty
        ? const _MiniEmpty()
        : Column(
            children: rows
                .take(12)
                .map((row) {
                  final color = _rateColor(row.unitFillRate);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 11),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 88,
                          child: Text(
                            _shortDate(row.date),
                            style: const TextStyle(
                              color: Color(0xff475569),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: (row.unitFillRate / 100)
                                .clamp(0, 1)
                                .toDouble(),
                            minHeight: 9,
                            color: color,
                            backgroundColor: color.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                        const SizedBox(width: 11),
                        SizedBox(
                          width: 58,
                          child: Text(
                            '${_fmt(row.unitFillRate)}%',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                })
                .toList(growable: false),
          ),
  );
}

class _StatusBreakdown extends StatefulWidget {
  final List<FillRateStatus> statuses;

  const _StatusBreakdown({required this.statuses});

  @override
  State<_StatusBreakdown> createState() => _StatusBreakdownState();
}

class _StatusBreakdownState extends State<_StatusBreakdown> {
  bool _availableAndEmptyOnly = false;

  @override
  Widget build(BuildContext context) {
    final focused = FillRateFocusedMetrics.fromStatuses(widget.statuses);

    return _InsightCard(
      icon: _availableAndEmptyOnly
          ? Icons.fact_check_outlined
          : Icons.category_outlined,
      title: _availableAndEmptyOnly
          ? 'Combined Fill Rate — Available & Empty Statuses'
          : 'Purchase Status Distribution',
      subtitle: _availableAndEmptyOnly
          ? '${focused.includedItems} products included • ${focused.excludedItems} supplier-status products excluded'
          : 'Product count and percentage of all required refill products',
      action: FilledButton.tonalIcon(
        onPressed: () =>
            setState(() => _availableAndEmptyOnly = !_availableAndEmptyOnly),
        icon: Icon(
          _availableAndEmptyOnly
              ? Icons.list_alt_rounded
              : Icons.filter_alt_rounded,
          size: 17,
        ),
        label: Text(
          _availableAndEmptyOnly
              ? 'Show all statuses'
              : 'Calculate Available + Empty Fill Rate',
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
        ),
      ),
      child: widget.statuses.isEmpty
          ? const _MiniEmpty()
          : _availableAndEmptyOnly
          ? _AvailableEmptyAnalysis(
              included: focused.includedItems,
              excluded: focused.excludedItems,
              lineFillRate: focused.lineFillRate,
              unitFillRate: focused.unitFillRate,
              requiredQty: focused.requiredQty,
              suppliedQty: focused.suppliedQty,
            )
          : _AllPurchaseStatuses(statuses: widget.statuses),
    );
  }
}

class _AllPurchaseStatuses extends StatelessWidget {
  final List<FillRateStatus> statuses;

  const _AllPurchaseStatuses({required this.statuses});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 390),
    child: ListView.separated(
      shrinkWrap: true,
      itemCount: statuses.length,
      separatorBuilder: (_, _) => const Divider(height: 13),
      itemBuilder: (context, index) {
        final status = statuses[index];
        return _PurchaseStatusShareRow(
          name: status.name,
          count: status.totalItems,
          percentage: status.share,
          color: _purchaseColor(status.name),
        );
      },
    ),
  );
}

class _AvailableEmptyAnalysis extends StatelessWidget {
  final int included;
  final int excluded;
  final num lineFillRate;
  final num unitFillRate;
  final num requiredQty;
  final num suppliedQty;

  const _AvailableEmptyAnalysis({
    required this.included,
    required this.excluded,
    required this.lineFillRate,
    required this.unitFillRate,
    required this.requiredQty,
    required this.suppliedQty,
  });

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xffEFF6FF),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xffBFDBFE)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.filter_alt_outlined,
              color: Color(0xff2563EB),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'The same combined group is used for both Fill Rate results',
                    style: TextStyle(
                      color: Color(0xff1E3A8A),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$included products are included. Purchase Status: AVAILABLE + AVAILABLE N.E + EMPTY / NOT ASSIGNED. All other purchase statuses are excluded.',
                    style: const TextStyle(
                      color: Color(0xff334E7D),
                      fontSize: 11,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _FocusedFillRateCard(
              label: 'Combined Unit Fill Rate',
              value: unitFillRate,
              detail:
                  '${_fmt(suppliedQty)} of ${_fmt(requiredQty)} units supplied',
              icon: Icons.local_shipping_outlined,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _FocusedFillRateCard(
              label: 'Combined Line Fill Rate',
              value: lineFillRate,
              detail: '$included included product lines',
              icon: Icons.checklist_rounded,
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _FocusedFormulaExplanation(
              title: 'UNIT — quantity fulfillment for the included statuses',
              formula:
                  '${_fmt(suppliedQty)} supplied units ÷ ${_fmt(requiredQty)} required units × 100',
              result: '${_fmt(unitFillRate)}%',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _FocusedFormulaExplanation(
              title:
                  'LINE — product-line fulfillment for the included statuses',
              formula:
                  'Average fulfillment percentage across all $included included product lines',
              result: '${_fmt(lineFillRate)}%',
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xffFFF7ED),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xffFED7AA)),
        ),
        child: Text(
          'Excluded from both Fill Rate results: $excluded products with supplier-related statuses such as Out of Stock, Pending Agreement, Allocate, and similar statuses.',
          style: const TextStyle(
            color: Color(0xff9A3412),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class _FocusedFillRateCard extends StatelessWidget {
  final String label;
  final num value;
  final String detail;
  final IconData icon;

  const _FocusedFillRateCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final color = _rateColor(value);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xff172554), Color(0xff1E3A8A)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_fmt(value)}%',
                  style: TextStyle(
                    color: color,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Text(
                  'INCLUDES: AVAILABLE + AVAILABLE N.E + EMPTY / NOT ASSIGNED',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xff93C5FD),
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xffBFDBFE), fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusedFormulaExplanation extends StatelessWidget {
  final String title;
  final String formula;
  final String result;

  const _FocusedFormulaExplanation({
    required this.title,
    required this.formula,
    required this.result,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    decoration: BoxDecoration(
      color: const Color(0xffF8FAFC),
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: const Color(0xffE2E8F0)),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.calculate_outlined,
          color: Color(0xff475569),
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xff334155),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formula,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xff64748B),
                  fontSize: 10,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          result,
          style: const TextStyle(
            color: Color(0xff0F172A),
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );
}

class _PurchaseStatusShareRow extends StatelessWidget {
  final String name;
  final int count;
  final num percentage;
  final Color color;

  const _PurchaseStatusShareRow({
    required this.name,
    required this.count,
    required this.percentage,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xff334155),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      Text(
        '$count products',
        style: const TextStyle(color: Color(0xff64748B), fontSize: 11),
      ),
      const SizedBox(width: 10),
      SizedBox(
        width: 58,
        child: Text(
          '${_fmt(percentage)}%',
          textAlign: TextAlign.right,
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ),
    ],
  );
}

class _InsightCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;

  const _InsightCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: _cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.primaryColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xff0F172A),
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xff64748B),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (action != null) ...[const SizedBox(width: 10), action!],
          ],
        ),
        const SizedBox(height: 17),
        child,
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 205),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: .24)),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900),
    ),
  );
}

class _EmptyProducts extends StatelessWidget {
  const _EmptyProducts();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, color: Color(0xff94A3B8), size: 40),
          SizedBox(height: 10),
          Text(
            'No products match the selected filters.',
            style: TextStyle(
              color: Color(0xff64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MiniEmpty extends StatelessWidget {
  const _MiniEmpty();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: Text(
        'No data for this period.',
        style: TextStyle(color: Color(0xff64748B)),
      ),
    ),
  );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(color: AppColors.primaryColor),
        SizedBox(height: 14),
        Text(
          'Building Fill Rate report...',
          style: TextStyle(
            color: Color(0xff475569),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xffFEF2F2),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: const Color(0xffFECACA)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: Color(0xffDC2626)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Color(0xff991B1B)),
          ),
        ),
        TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Retry'),
        ),
      ],
    ),
  );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      constraints: const BoxConstraints(maxWidth: 600),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xffDC2626),
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}

BoxDecoration _cardDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(17),
  border: Border.all(color: const Color(0xffDCE3EC)),
  boxShadow: const [
    BoxShadow(color: Color(0x080F172A), blurRadius: 12, offset: Offset(0, 4)),
  ],
);

Color _rateColor(num value) {
  if (value >= 95) return const Color(0xff059669);
  if (value >= 80) return const Color(0xff2563EB);
  if (value >= 60) return const Color(0xffD97706);
  return const Color(0xffDC2626);
}

Color _fulfillmentColor(String status) {
  if (status == 'Fully Supplied') return const Color(0xff059669);
  if (status == 'Partially Supplied') return const Color(0xffD97706);
  return const Color(0xffDC2626);
}

Color _purchaseColor(String status) {
  final value = status.toUpperCase();
  if (value.contains('AVAILABLE') && !value.contains('NOT')) {
    return const Color(0xff059669);
  }
  if (value.contains('OUT OF STOCK') || value == 'OOS') {
    return const Color(0xffDC2626);
  }
  if (value.contains('ALLOCATE')) return const Color(0xff2563EB);
  if (value.contains('PENDING')) return const Color(0xffD97706);
  return const Color(0xff64748B);
}

String _share(int count, int total) => total == 0
    ? '0% of required products'
    : '${_fmt(count / total * 100)}% of required products';
String _integer(num value) => value.toInt().toString();
String _fmt(num value) =>
    value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(2);
String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _shortDate(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String _friendlyError(Object error) {
  final value = '$error';
  if (value.contains('get_fill_rate_') || value.contains('PGRST202')) {
    return 'Fill Rate database functions are not installed. Run supabase/sql/fill_rate_kpi.sql in Supabase, then retry.';
  }
  return 'Could not load Fill Rate KPI. $value';
}
