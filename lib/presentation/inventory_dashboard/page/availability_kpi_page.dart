import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/availability_allocation_excel_exporter.dart';
import '../../../core/utils/availability_branch_report_excel_exporter.dart';
import '../../../core/utils/availability_kpi_excel_exporter.dart';
import '../../../data/datasources/remote/availability_kpi_remote_ds.dart';

class AvailabilityKpiPage extends StatefulWidget {
  final String runDate;

  const AvailabilityKpiPage({super.key, required this.runDate});

  @override
  State<AvailabilityKpiPage> createState() => _AvailabilityKpiPageState();
}

class _AvailabilityKpiPageState extends State<AvailabilityKpiPage> {
  late final AvailabilityKpiRemoteDs _remote;
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<AvailabilityBranchSummary> _summaries = const [];
  final Set<String> _loadedSummaryBranches = <String>{};
  final Set<String> _loadingSummaryBranches = <String>{};
  final Map<String, AvailabilityBranchData> _branchData = {};
  List<AvailabilityKpiItem> _allItems = const [];
  List<AvailabilityKpiItem> _items = const [];
  String? _selectedBranch;
  String _source = 'all';
  bool _onlyShortage = false;
  bool _loadingSummary = true;
  bool _loadingItems = false;
  bool _exportingAllocation = false;
  bool _exportingAllBranches = false;
  double _allBranchesExportProgress = 0;
  String _allBranchesExportStatus = '';
  bool _loadingAllocationPreview = false;
  bool _allocationPreviewActive = false;
  Map<String, AvailabilityAllocationImpact> _allocationImpact = const {};
  String _error = '';
  int _totalRows = 0;
  int _requestSerial = 0;
  int _activeReportTab = 0;
  late String _stockDate;

  @override
  void initState() {
    super.initState();
    _remote = AvailabilityKpiRemoteDs(Supabase.instance.client);
    _stockDate = widget.runDate;
    _loadDashboard();
  }

  @override
  void didUpdateWidget(covariant AvailabilityKpiPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runDate != widget.runDate) {
      _stockDate = widget.runDate;
      _loadDashboard();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  AvailabilityBranchSummary? get _selectedSummary {
    final branch = _selectedBranch;
    if (branch == null || !_loadedSummaryBranches.contains(branch)) return null;
    for (final summary in _displaySummaries) {
      if (summary.branchName == branch) return summary;
    }
    return null;
  }

  List<AvailabilityBranchSummary> get _displaySummaries {
    if (!_allocationPreviewActive) return _summaries;
    return _summaries
        .map((summary) {
          final impact = _allocationImpact[summary.branchName];
          return impact == null
              ? summary
              : summary.withAvailabilityRate(impact.projectedRate);
        })
        .toList(growable: false);
  }

  Future<void> _loadDashboard() async {
    final serial = ++_requestSerial;
    _remote.invalidatePurchaseStatuses();
    setState(() {
      _loadingSummary = true;
      _loadingItems = true;
      _allocationPreviewActive = false;
      _loadingAllocationPreview = false;
      _allocationImpact = const {};
      _error = '';
    });

    try {
      final stockDate = await _remote.fetchLatestStockDate(
        fallback: widget.runDate,
      );
      final branches = await _remote.fetchActiveBranches();
      if (!mounted || serial != _requestSerial) return;

      final previousBranch = _selectedBranch;
      final availableBranches = branches.toSet();
      final selected = availableBranches.contains(previousBranch)
          ? previousBranch
          : branches.firstOrNull;

      setState(() {
        _summaries = branches
            .map(AvailabilityBranchSummary.empty)
            .toList(growable: false);
        _loadedSummaryBranches.clear();
        _loadingSummaryBranches.clear();
        _branchData.clear();
        _selectedBranch = selected;
        _stockDate = stockDate;
      });

      if (selected == null) {
        setState(() {
          _items = const [];
          _allItems = const [];
          _totalRows = 0;
          _loadingSummary = false;
          _loadingItems = false;
        });
        return;
      }
      await _loadSelectedBranch(serial: serial);
      await _preloadAllBranches(
        serial: serial,
        branches: branches.where((branch) => branch != selected).toList(),
      );
    } catch (error) {
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _loadingSummary = false;
        _loadingItems = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _loadSelectedBranch({int? serial}) async {
    final branch = _selectedBranch;
    if (branch == null) return;
    final requestSerial = serial ?? _requestSerial;

    setState(() {
      _loadingSummary = true;
      _loadingItems = true;
      _loadingSummaryBranches.add(branch);
      _error = '';
    });

    try {
      var data =
          _branchData[branch] ??
          await _remote.fetchBranchData(runDate: _stockDate, branch: branch);
      data = await _remote.enrichSellingMonths(data);
      if (!mounted ||
          requestSerial != _requestSerial ||
          branch != _selectedBranch) {
        return;
      }

      setState(() {
        _cacheBranchData(branch, data);
        _loadedSummaryBranches.add(branch);
        _loadingSummaryBranches.remove(branch);
        _allItems = data.items;
        _updateVisibleItems();
        _loadingSummary = false;
        _loadingItems = false;
      });
    } catch (error) {
      if (!mounted ||
          requestSerial != _requestSerial ||
          branch != _selectedBranch) {
        return;
      }
      setState(() {
        _loadingSummary = false;
        _loadingItems = false;
        _loadingSummaryBranches.remove(branch);
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _preloadAllBranches({
    required int serial,
    required List<String> branches,
  }) async {
    if (branches.isEmpty || !mounted || serial != _requestSerial) return;
    setState(() => _loadingSummaryBranches.addAll(branches));

    // Preferred path: PostgreSQL returns one already-calculated row per
    // branch. Both report tabs reuse this same in-memory result.
    try {
      final loaded = await _remote.fetchAllBranchSummariesFast(
        runDate: _stockDate,
      );
      if (loaded.isEmpty) {
        throw StateError('The fast branch summary returned no rows.');
      }
      if (!mounted || serial != _requestSerial) return;
      setState(() {
        _loadingSummaryBranches.removeAll(branches);
        for (final branch in branches) {
          final summary = loaded[branch];
          if (summary != null) _cacheBranchSummary(branch, summary);
        }
      });
      return;
    } catch (_) {
      // Older databases may not have the optimized RPC yet. Continue with
      // small indexed batches so the page remains usable during rollout.
    }

    const batchSize = 4;
    for (var start = 0; start < branches.length; start += batchSize) {
      if (!mounted || serial != _requestSerial) return;
      final end = math.min(start + batchSize, branches.length);
      final batch = branches.sublist(start, end);
      try {
        final loaded = await _remote.fetchBranchSummaries(
          runDate: _stockDate,
          branches: batch,
        );
        if (!mounted || serial != _requestSerial) return;
        setState(() {
          _loadingSummaryBranches.removeAll(batch);
          for (final entry in loaded.entries) {
            _cacheBranchSummary(entry.key, entry.value);
          }
        });
      } catch (_) {
        if (!mounted || serial != _requestSerial) return;
        setState(() => _loadingSummaryBranches.removeAll(batch));
      }
    }
  }

  void _cacheBranchData(String branch, AvailabilityBranchData data) {
    _branchData[branch] = data;
    _cacheBranchSummary(branch, data.summary);
  }

  void _cacheBranchSummary(String branch, AvailabilityBranchSummary summary) {
    _loadedSummaryBranches.add(branch);
    final index = _summaries.indexWhere((entry) => entry.branchName == branch);
    if (index < 0) return;
    final updated = List<AvailabilityBranchSummary>.from(_summaries);
    updated[index] = summary;
    _summaries = updated;
  }

  void _loadItems() {
    setState(_updateVisibleItems);
  }

  void _updateVisibleItems() {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _allItems
        .where((item) {
          final matchesSearch =
              query.isEmpty ||
              item.itemCode.toLowerCase().contains(query) ||
              item.itemName.toLowerCase().contains(query) ||
              item.statusName.toLowerCase().contains(query);
          final matchesSource = switch (_source) {
            'pareto' => item.inPareto,
            'consistent' => item.inConsistent && !item.inPareto,
            _ => true,
          };
          final matchesShortage = !_onlyShortage || item.stockShortage > 0;
          return matchesSearch && matchesSource && matchesShortage;
        })
        .toList(growable: false);

    _totalRows = filtered.length;
    _items = filtered;
  }

  void _selectBranch(String branch) {
    if (_selectedBranch == branch) return;
    setState(() {
      _selectedBranch = branch;
      _allItems = const [];
      _items = const [];
      _totalRows = 0;
    });
    _loadSelectedBranch();
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 160), () {
      if (!mounted) return;
      _loadItems();
    });
  }

  Future<void> _exportAllocation() async {
    if (_exportingAllocation) return;
    setState(() => _exportingAllocation = true);
    try {
      final rows = await _remote.fetchAllocation(runDate: _stockDate);
      if (!mounted) return;
      final activeBranches = _summaries
          .map((summary) => summary.branchName.trim())
          .toSet();
      final containsInactiveBranch = rows.any(
        (row) =>
            !activeBranches.contains(row.fromBranch.trim()) ||
            !activeBranches.contains(row.toBranch.trim()),
      );
      if (containsInactiveBranch) {
        throw StateError(
          'The allocation cache contains a branch outside the active Availability list.',
        );
      }
      if (rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No allocation is available: no matching Extra Qty was found for the current shortages.',
            ),
            backgroundColor: Color(0xffD97706),
          ),
        );
        return;
      }
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await AvailabilityAllocationExcelExporter.export(
        stockDate: _stockDate,
        rows: rows,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${rows.length} allocation transfers exported successfully.',
          ),
          backgroundColor: const Color(0xff059669),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Allocation export failed. Run availability_kpi_allocation.sql in Supabase, then retry. $error',
          ),
          backgroundColor: const Color(0xffDC2626),
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingAllocation = false);
    }
  }

  Future<void> _toggleAllocationPreview() async {
    if (_allocationPreviewActive) {
      setState(() {
        _allocationPreviewActive = false;
        _allocationImpact = const {};
      });
      return;
    }
    if (_loadingAllocationPreview) return;
    setState(() => _loadingAllocationPreview = true);
    try {
      final impact = await _remote.fetchAllocationImpact(runDate: _stockDate);
      if (!mounted) return;
      if (impact.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No allocation impact is available for this date.'),
            backgroundColor: Color(0xffD97706),
          ),
        );
        return;
      }
      setState(() {
        _allocationImpact = impact;
        _allocationPreviewActive = true;
      });
    } catch (error) {
      if (!mounted) return;
      final isTimeout = error is PostgrestException && error.code == '57014';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isTimeout
                ? 'Allocation preview exceeded the database time limit. Run availability_kpi_allocation_timeout_fix.sql once in Supabase, then retry.'
                : 'Allocation preview failed. Please retry. If the problem continues, run the latest availability_kpi_allocation.sql in Supabase. $error',
          ),
          backgroundColor: const Color(0xffDC2626),
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingAllocationPreview = false);
    }
  }

  Future<void> _exportAllBranches() async {
    if (_exportingAllBranches || _summaries.isEmpty) return;
    setState(() {
      _exportingAllBranches = true;
      _allBranchesExportProgress = .02;
      _allBranchesExportStatus = 'Starting all-branch export...';
    });
    try {
      final items = await _remote.fetchAllBranchItemsForExport(
        runDate: _stockDate,
        branches: _summaries.map((summary) => summary.branchName),
        onProgress: (progress, message) {
          if (!mounted) return;
          setState(() {
            _allBranchesExportProgress = progress;
            _allBranchesExportStatus = message;
          });
        },
      );
      if (!mounted) return;
      if (items.isEmpty) {
        throw StateError('No Availability items were found to export.');
      }
      setState(() {
        _allBranchesExportProgress = .73;
        _allBranchesExportStatus =
            'Formatting ${items.length} items in Excel...';
      });
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await AvailabilityKpiExcelExporter.export(
        branch: 'All Branches',
        stockDate: _stockDate,
        items: items,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _allBranchesExportProgress = .73 + progress * .25;
            _allBranchesExportStatus =
                'Formatting ${items.length} items in Excel...';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _allBranchesExportProgress = 1;
        _allBranchesExportStatus = 'Download started successfully.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${items.length} items from ${_summaries.length} branches exported.',
          ),
          backgroundColor: const Color(0xff059669),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error.toString();
      final friendlyMessage = message.contains('Failed to fetch')
          ? 'Could not download the all-branch data. Run availability_kpi_export_cache.sql in Supabase, then retry.'
          : message.contains('ensure_availability_kpi_export_cache_v1') ||
                message.contains('availability_kpi_export_cache_v1')
          ? 'The fast export cache is not installed. Run availability_kpi_export_cache.sql in Supabase, then retry.'
          : 'Could not prepare the all-branch Excel file.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyMessage),
          backgroundColor: const Color(0xffDC2626),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _exportingAllBranches = false;
          _allBranchesExportProgress = 0;
          _allBranchesExportStatus = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displaySummaries = _displaySummaries;
    return ColoredBox(
      color: const Color(0xffF4F7FB),
      child: Column(
        children: [
          _Header(
            runDate: _stockDate,
            branchCount: _summaries.length,
            loading: _loadingSummary || _loadingItems,
            exportingAllocation: _exportingAllocation,
            previewActive: _allocationPreviewActive,
            loadingPreview: _loadingAllocationPreview,
            onTogglePreview: _toggleAllocationPreview,
            onExportAllocation: _exportAllocation,
            onRefresh: _loadDashboard,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 1050;
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 26,
                    20,
                    compact ? 16 : 26,
                    32,
                  ),
                  children: [
                    if (_error.isNotEmpty) ...[
                      _ErrorBanner(message: _error, onRetry: _loadDashboard),
                      const SizedBox(height: 16),
                    ],
                    const _MethodCard(),
                    const SizedBox(height: 18),
                    _AvailabilityReportTabs(
                      selectedIndex: _activeReportTab,
                      onChanged: (index) =>
                          setState(() => _activeReportTab = index),
                    ),
                    if (_allocationPreviewActive) ...[
                      const SizedBox(height: 14),
                      _AllocationPreviewBanner(
                        impacts: _allocationImpact,
                        onClose: _toggleAllocationPreview,
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (_activeReportTab == 1)
                      _BranchReport(
                        stockDate: _stockDate,
                        summaries: displaySummaries
                            .where(
                              (summary) => _loadedSummaryBranches.contains(
                                summary.branchName,
                              ),
                            )
                            .toList(growable: false),
                        totalBranches: _summaries.length,
                        loading: _loadingSummaryBranches.isNotEmpty,
                        onOpenBranch: (branch) {
                          setState(() => _activeReportTab = 0);
                          _selectBranch(branch);
                        },
                      )
                    else if (_loadingSummary && _summaries.isEmpty)
                      const _LoadingCard(label: 'Loading branch item list…')
                    else if (_summaries.isEmpty)
                      const _EmptyCard(
                        icon: Icons.query_stats_rounded,
                        title: 'No KPI item data',
                        message:
                            'Refresh the monthly sales data, then open this page again.',
                      )
                    else ...[
                      if (compact)
                        _CompactBranchPicker(
                          summaries: displaySummaries,
                          loadedBranches: _loadedSummaryBranches,
                          selectedBranch: _selectedBranch,
                          onChanged: _selectBranch,
                        )
                      else
                        _BranchOverview(
                          summaries: displaySummaries,
                          loadedBranches: _loadedSummaryBranches,
                          loadingBranches: _loadingSummaryBranches,
                          selectedBranch: _selectedBranch,
                          onSelected: _selectBranch,
                        ),
                      const SizedBox(height: 18),
                      _SummaryCards(summary: _selectedSummary),
                      const SizedBox(height: 18),
                      _Filters(
                        controller: _searchController,
                        source: _source,
                        onlyShortage: _onlyShortage,
                        onSearchChanged: _onSearchChanged,
                        onSourceChanged: (value) {
                          setState(() {
                            _source = value;
                          });
                          _loadItems();
                        },
                        onShortageChanged: (value) {
                          setState(() {
                            _onlyShortage = value;
                          });
                          _loadItems();
                        },
                      ),
                      const SizedBox(height: 14),
                      _MasterTable(
                        branch: _selectedBranch ?? '',
                        stockDate: _stockDate,
                        items: _items,
                        loading: _loadingItems,
                        totalRows: _totalRows,
                        exportingAllBranches: _exportingAllBranches,
                        allBranchesExportProgress: _allBranchesExportProgress,
                        allBranchesExportStatus: _allBranchesExportStatus,
                        onExportAllBranches: _exportAllBranches,
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

class _AllocationPreviewBanner extends StatelessWidget {
  final Map<String, AvailabilityAllocationImpact> impacts;
  final VoidCallback onClose;

  const _AllocationPreviewBanner({
    required this.impacts,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final improved = impacts.values.where((item) => item.rateChange > 0).length;
    final incoming = impacts.values.fold<int>(
      0,
      (total, item) => total + item.incomingQty,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xffFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffFDBA74)),
      ),
      child: Row(
        children: [
          const Icon(Icons.science_outlined, color: Color(0xffC2410C)),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Allocation Preview',
                  style: TextStyle(
                    color: Color(0xff9A3412),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Projected rates after all allocation arrives. Current stock is unchanged. '
                  '$improved branches improve from $incoming incoming units.',
                  style: const TextStyle(
                    color: Color(0xff7C2D12),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Exit Preview'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xff9A3412),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String runDate;
  final int branchCount;
  final bool loading;
  final bool exportingAllocation;
  final bool previewActive;
  final bool loadingPreview;
  final VoidCallback onTogglePreview;
  final VoidCallback onExportAllocation;
  final VoidCallback onRefresh;

  const _Header({
    required this.runDate,
    required this.branchCount,
    required this.loading,
    required this.exportingAllocation,
    required this.previewActive,
    required this.loadingPreview,
    required this.onTogglePreview,
    required this.onExportAllocation,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(34, 25, 26, 23),
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
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Colors.white.withValues(alpha: .22)),
            ),
            child: const Icon(
              Icons.monitor_heart_rounded,
              color: Colors.white,
              size: 31,
            ),
          ),
          const SizedBox(width: 17),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Availability KPI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 29,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.4,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Selected branch items • 7-day stock coverage • Stock date: $runDate',
                  maxLines: 2,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .84),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _HeaderPill(label: 'Branches', value: '$branchCount'),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: loading || loadingPreview ? null : onTogglePreview,
            icon: loadingPreview
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.secondaryColor,
                    ),
                  )
                : Icon(
                    previewActive
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
            label: Text(
              loadingPreview
                  ? 'Calculating Preview'
                  : previewActive
                  ? 'Exit Preview'
                  : 'Preview Allocation',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: previewActive
                  ? const Color(0xffFEF3C7)
                  : Colors.white,
              foregroundColor: previewActive
                  ? const Color(0xff92400E)
                  : AppColors.secondaryColor,
              disabledBackgroundColor: Colors.white60,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: loading || exportingAllocation
                ? null
                : onExportAllocation,
            icon: exportingAllocation
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.secondaryColor,
                    ),
                  )
                : const Icon(Icons.compare_arrows_rounded),
            label: Text(
              exportingAllocation
                  ? 'Preparing Allocation'
                  : 'Export Allocation',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.secondaryColor,
              disabledBackgroundColor: Colors.white60,
              disabledForegroundColor: AppColors.secondaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: loading ? null : onRefresh,
            icon: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
            label: Text(loading ? 'Updating' : 'Refresh'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xff10B981),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.white24,
              padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 17),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  final String label;
  final String value;

  const _HeaderPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: .2)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .72),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodCard extends StatelessWidget {
  const _MethodCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xffEFF6FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffBFDBFE)),
      ),
      child: Wrap(
        spacing: 20,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const _MethodStep(
            number: '1',
            title: 'Top sellers',
            detail:
                'Items that make up 60% of branch sales in the last 3 completed months',
          ),
          const Icon(Icons.add_rounded, color: Color(0xff2563EB)),
          const _MethodStep(
            number: '2',
            title: 'Regular sellers',
            detail: 'Items sold in at least 80% of the months studied',
          ),
          const Icon(Icons.arrow_forward_rounded, color: Color(0xff2563EB)),
          const _MethodStep(
            number: '3',
            title: '7-day stock need',
            detail:
                '70% from 3-month history + 30% from the latest 45-day trend',
          ),
          TextButton.icon(
            onPressed: () => _showCalculationDialog(context),
            icon: const Icon(Icons.help_outline_rounded),
            label: const Text('Explain calculation'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.secondaryColor,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showCalculationDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(26),
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.secondaryColor.withValues(alpha: .1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.calculate_rounded,
                        color: AppColors.secondaryColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'How Availability Is Calculated',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const _CalculationRow(
                  number: '1',
                  title: 'Items Included',
                  detail:
                      'An item is included when it is a top seller in the group that makes 60% of branch sales value during the last 3 completed months, or when it was sold in at least 80% of the months studied. Only Normal Purchase items are included. After Store Stock is calculated, an item is excluded only when Store Stock is more than 4 and its 7-day coverage is below 100%.',
                ),
                const _CalculationRow(
                  number: '2',
                  title: 'Stock Needed for 7 Days',
                  detail:
                      'We calculate two weekly averages, then combine them. The last 3 completed months represent stable sales history. The latest 45 days represent the current sales trend. The 45-day period ends on the latest sales date available in the system.',
                  formula:
                      '1. 3-Month Weekly Average = Total units in the last 3 completed months ÷ 3 ÷ 4.33\n\n'
                      '2. 45-Day Weekly Average = Units sold in the latest 45 days ÷ 6.43\n\n'
                      '3. 7-Day Need = (3-Month Weekly Average × 70%) + (45-Day Weekly Average × 30%)',
                  example:
                      'Example\n'
                      'April 15 + May 2 + June 0 = 17 units\n'
                      '3-Month Weekly Average = 17 ÷ 3 ÷ 4.33 = 1.31\n'
                      'Latest 45 days = 1 unit ÷ 6.43 = 0.16\n'
                      '7-Day Need = (1.31 × 70%) + (0.16 × 30%) = 0.97 units, or about 1 unit.\n\n'
                      'Max Adj exception: DECREASE qty above zero replaces this calculation and is treated as 30-day demand. DECREASE qty of zero removes the item from the KPI list.',
                ),
                const _CalculationRow(
                  number: '3',
                  title: 'Item Coverage',
                  detail:
                      'Current branch stock is branch_stock plus total_final_reorder_today from daily_order. This total is divided by the stock needed for 7 days. Purchase Status IDs 1, 2, 5, 7, 8 and 34 are treated as 100% covered. Otherwise, coverage cannot be more than 100%, and a difference of 0.16 units or less is ignored.',
                  formula: 'Current stock ÷ 7-day need',
                ),
                const _CalculationRow(
                  number: '4',
                  title: 'Branch Availability',
                  detail:
                      'We add the 7-day coverage percentage of every item, then divide by the number of items. Every item has the same weight.',
                  formula: 'Total item coverage ÷ item count',
                  last: true,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _CalculationRow extends StatelessWidget {
  final String number;
  final String title;
  final String detail;
  final String? formula;
  final String? example;
  final bool last;

  const _CalculationRow({
    required this.number,
    required this.title,
    required this.detail,
    this.formula,
    this.example,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xff2563EB),
                child: Text(
                  number,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (!last)
                Expanded(
                  child: Container(width: 2, color: const Color(0xffDBEAFE)),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xff0F172A),
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    detail,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      color: Color(0xff475569),
                      height: 1.6,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (formula != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xffF1F5F9),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: SelectableText(
                        formula!,
                        style: const TextStyle(
                          color: Color(0xff1E3A8A),
                          fontWeight: FontWeight.w900,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                  if (example != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.secondaryColor.withValues(alpha: .06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.secondaryColor.withValues(alpha: .2),
                        ),
                      ),
                      child: SelectableText(
                        example!,
                        style: const TextStyle(
                          color: Color(0xff334155),
                          height: 1.55,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MethodStep extends StatelessWidget {
  final String number;
  final String title;
  final String detail;

  const _MethodStep({
    required this.number,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xff2563EB),
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xff0F172A),
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              detail,
              style: const TextStyle(
                color: Color(0xff64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BranchOverview extends StatefulWidget {
  final List<AvailabilityBranchSummary> summaries;
  final Set<String> loadedBranches;
  final Set<String> loadingBranches;
  final String? selectedBranch;
  final ValueChanged<String> onSelected;

  const _BranchOverview({
    required this.summaries,
    required this.loadedBranches,
    required this.loadingBranches,
    required this.selectedBranch,
    required this.onSelected,
  });

  @override
  State<_BranchOverview> createState() => _BranchOverviewState();
}

class _BranchOverviewState extends State<_BranchOverview> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollBy(double direction) {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final distance = math.max(position.viewportDimension * .82, 440);
    final target = (position.pixels + (distance * direction))
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.storefront_rounded,
                color: AppColors.primaryColor,
              ),
              const SizedBox(width: 9),
              const Text(
                'Branch availability overview',
                style: TextStyle(
                  color: Color(0xff0F172A),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                '${widget.loadedBranches.length} of ${widget.summaries.length} branches loaded • A–Z',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: () => _scrollBy(-1),
                tooltip: 'Previous branches',
                icon: const Icon(Icons.chevron_left_rounded),
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.primaryColor,
                  backgroundColor: AppColors.primaryColor.withValues(
                    alpha: .09,
                  ),
                  side: BorderSide(
                    color: AppColors.primaryColor.withValues(alpha: .3),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () => _scrollBy(1),
                tooltip: 'Next branches',
                icon: const Icon(Icons.chevron_right_rounded),
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.primaryColor,
                  backgroundColor: AppColors.primaryColor.withValues(
                    alpha: .09,
                  ),
                  side: BorderSide(
                    color: AppColors.primaryColor.withValues(alpha: .3),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          SizedBox(
            height: 150,
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              trackVisibility: true,
              thickness: 7,
              radius: const Radius.circular(99),
              scrollbarOrientation: ScrollbarOrientation.bottom,
              child: ListView.separated(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 14),
                physics: const ClampingScrollPhysics(),
                itemCount: widget.summaries.length,
                separatorBuilder: (_, _) => const SizedBox(width: 11),
                itemBuilder: (context, index) {
                  final summary = widget.summaries[index];
                  return _BranchTile(
                    summary: summary,
                    loaded: widget.loadedBranches.contains(summary.branchName),
                    loading: widget.loadingBranches.contains(
                      summary.branchName,
                    ),
                    selected: widget.selectedBranch == summary.branchName,
                    onTap: () => widget.onSelected(summary.branchName),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchTile extends StatelessWidget {
  final AvailabilityBranchSummary summary;
  final bool loaded;
  final bool loading;
  final bool selected;
  final VoidCallback onTap;

  const _BranchTile({
    required this.summary,
    required this.loaded,
    required this.loading,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = loaded
        ? _rateColor(summary.availabilityRate)
        : AppColors.primaryColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 208,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryColor.withValues(alpha: .08)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.primaryColor : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      summary.branchName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff0F172A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (loading && !loaded)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.primaryColor,
                      ),
                    )
                  else
                    Text(
                      loaded ? '${_fmt(summary.availabilityRate)}%' : '—',
                      style: TextStyle(
                        color: loaded ? color : AppColors.subText,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: loading && !loaded
                      ? null
                      : (summary.availabilityRate / 100)
                            .clamp(0, loaded ? 1 : 0)
                            .toDouble(),
                  minHeight: 8,
                  color: color,
                  backgroundColor: AppColors.primaryColor.withValues(
                    alpha: .12,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                loaded
                    ? '${summary.masterItems} KPI items  •  ${summary.shortageItems} below 7-day need'
                    : loading
                    ? 'Calculating branch KPI…'
                    : 'Waiting to load…',
                style: const TextStyle(
                  color: Color(0xff64748B),
                  fontSize: 11.5,
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

class _CompactBranchPicker extends StatelessWidget {
  final List<AvailabilityBranchSummary> summaries;
  final Set<String> loadedBranches;
  final String? selectedBranch;
  final ValueChanged<String> onChanged;

  const _CompactBranchPicker({
    required this.summaries,
    required this.loadedBranches,
    required this.selectedBranch,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: _cardDecoration(),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: selectedBranch,
          icon: const Icon(Icons.expand_more_rounded),
          items: summaries
              .map(
                (summary) => DropdownMenuItem(
                  value: summary.branchName,
                  child: Text(
                    loadedBranches.contains(summary.branchName)
                        ? '${summary.branchName}  •  ${_fmt(summary.availabilityRate)}%'
                        : summary.branchName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  final AvailabilityBranchSummary? summary;

  const _SummaryCards({required this.summary});

  @override
  Widget build(BuildContext context) {
    final value = summary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 850;
        final cards = [
          _KpiCard(
            title: 'Availability rate',
            value: value == null ? '—' : '${_fmt(value.availabilityRate)}%',
            subtitle: 'Average 7-day coverage of all KPI items',
            icon: Icons.speed_rounded,
            color: value == null
                ? const Color(0xff64748B)
                : _rateColor(value.availabilityRate),
          ),
          _KpiCard(
            title: 'KPI item list',
            value: value == null ? '—' : '${value.masterItems}',
            subtitle: value == null
                ? 'Top sellers + regularly sold items'
                : '${value.paretoItems} top sellers • ${value.consistentItems} regular sellers',
            icon: Icons.fact_check_rounded,
            color: const Color(0xff2563EB),
          ),
          _KpiCard(
            title: 'Fully covered',
            value: value == null ? '—' : '${value.fullyAvailableItems}',
            subtitle: value == null
                ? 'Enough stock for one week'
                : '${value.shortageItems} items below one week',
            icon: Icons.verified_rounded,
            color: const Color(0xff10B981),
          ),
          _KpiCard(
            title: 'Weekly shortage',
            value: value == null ? '—' : _fmt(value.stockShortage),
            subtitle: value == null
                ? 'Units needed to reach 100%'
                : '${_fmt(value.coveredWeeklyNeed)} / ${_fmt(value.weeklyNeed)} need covered',
            icon: Icons.trending_down_rounded,
            color: const Color(0xffEF4444),
          ),
        ];

        if (narrow) {
          return Wrap(spacing: 12, runSpacing: 12, children: cards);
        }
        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              Expanded(child: cards[i]),
              if (i != cards.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 205),
      padding: const EdgeInsets.all(17),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .11),
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
                  title,
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff94A3B8),
                    fontSize: 10.5,
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
}

class _Filters extends StatelessWidget {
  final TextEditingController controller;
  final String source;
  final bool onlyShortage;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSourceChanged;
  final ValueChanged<bool> onShortageChanged;

  const _Filters({
    required this.controller,
    required this.source,
    required this.onlyShortage,
    required this.onSearchChanged,
    required this.onSourceChanged,
    required this.onShortageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 340,
            child: TextField(
              controller: controller,
              onChanged: onSearchChanged,
              decoration: _inputDecoration(
                hint: 'Search item code or item name…',
                icon: Icons.search_rounded,
              ),
            ),
          ),
          SizedBox(
            width: 245,
            child: DropdownButtonFormField<String>(
              initialValue: source,
              isExpanded: true,
              decoration: _inputDecoration(
                hint: 'Reason for selection',
                icon: Icons.filter_alt_outlined,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'all',
                  child: Text('All selected items'),
                ),
                DropdownMenuItem(
                  value: 'pareto',
                  child: Text('Top seller — 60% of branch sales value'),
                ),
                DropdownMenuItem(
                  value: 'consistent',
                  child: Text('Items sold regularly'),
                ),
              ],
              onChanged: (value) {
                if (value != null) onSourceChanged(value);
              },
            ),
          ),
          FilterChip(
            selected: onlyShortage,
            onSelected: onShortageChanged,
            avatar: Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: onlyShortage ? Colors.white : const Color(0xffDC2626),
            ),
            label: const Text('Stock below 7-day need'),
            labelStyle: TextStyle(
              color: onlyShortage ? Colors.white : const Color(0xff991B1B),
              fontWeight: FontWeight.w800,
            ),
            selectedColor: const Color(0xffDC2626),
            backgroundColor: const Color(0xffFEF2F2),
            side: const BorderSide(color: Color(0xffFECACA)),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityReportTabs extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _AvailabilityReportTabs({
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xffE8EEF5),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ReportTabButton(
              selected: selectedIndex == 0,
              icon: Icons.inventory_2_outlined,
              label: 'Item Details',
              onTap: () => onChanged(0),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ReportTabButton(
              selected: selectedIndex == 1,
              icon: Icons.analytics_outlined,
              label: 'Branch Report',
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportTabButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ReportTabButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: selected
                ? Border.all(
                    color: AppColors.primaryColor.withValues(alpha: .3),
                  )
                : null,
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x140F172A),
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
                size: 20,
                color: selected
                    ? AppColors.primaryColor
                    : const Color(0xff64748B),
              ),
              const SizedBox(width: 9),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? AppColors.secondaryColor
                      : const Color(0xff64748B),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BranchReport extends StatefulWidget {
  final String stockDate;
  final List<AvailabilityBranchSummary> summaries;
  final int totalBranches;
  final bool loading;
  final ValueChanged<String> onOpenBranch;

  const _BranchReport({
    required this.stockDate,
    required this.summaries,
    required this.totalBranches,
    required this.loading,
    required this.onOpenBranch,
  });

  @override
  State<_BranchReport> createState() => _BranchReportState();
}

class _BranchReportState extends State<_BranchReport> {
  final _searchController = TextEditingController();
  late final _BranchReportGridSource _source;
  String _band = 'all';
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _source = _BranchReportGridSource(
      const [],
      onOpenBranch: widget.onOpenBranch,
    );
    _applyReportFilters();
  }

  @override
  void didUpdateWidget(covariant _BranchReport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.summaries, widget.summaries)) {
      _applyReportFilters();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyReportFilters() {
    final query = _searchController.text.trim().toLowerCase();
    final filtered =
        widget.summaries
            .where((summary) {
              final matchesSearch =
                  query.isEmpty ||
                  summary.branchName.toLowerCase().contains(query);
              final matchesBand = switch (_band) {
                'at_least_97' => summary.availabilityRate >= 97,
                'below_97' => summary.availabilityRate < 97,
                'below_95' => summary.availabilityRate < 95,
                'below_90' => summary.availabilityRate < 90,
                _ => true,
              };
              return matchesSearch && matchesBand;
            })
            .toList(growable: false)
          ..sort((a, b) {
            final rate = b.availabilityRate.compareTo(a.availabilityRate);
            return rate != 0 ? rate : a.branchName.compareTo(b.branchName);
          });
    _source.update(filtered);
  }

  Future<void> _export() async {
    final visible = _source.visibleSummaries;
    if (visible.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await AvailabilityBranchReportExcelExporter.export(
        stockDate: widget.stockDate,
        branches: visible,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${visible.length} filtered branches exported.'),
          backgroundColor: const Color(0xff059669),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Branch report export failed: $error'),
          backgroundColor: const Color(0xffDC2626),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loaded = widget.summaries.length;
    final atLeast97 = widget.summaries
        .where((summary) => summary.availabilityRate >= 97)
        .length;
    final below97 = loaded - atLeast97;
    final below90 = widget.summaries
        .where((summary) => summary.availabilityRate < 90)
        .length;
    final average = loaded == 0
        ? 0
        : widget.summaries.fold<num>(
                0,
                (sum, summary) => sum + summary.availabilityRate,
              ) /
              loaded;
    final visibleRows = _source.visibleSummaries.length;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          spacing: 14,
          children: [
            _BranchMetricCard(
              label: 'Average Availability',
              value: '${_fmt(average)}%',
              detail: '$loaded of ${widget.totalBranches} branches loaded',
              icon: Icons.speed_rounded,
              color: AppColors.primaryColor,
            ),
            _BranchMetricCard(
              label: '97% and Above',
              value: '$atLeast97',
              detail: loaded == 0
                  ? '0% of loaded branches'
                  : '${_fmt(atLeast97 / loaded * 100)}% of loaded branches',
              icon: Icons.verified_rounded,
              color: const Color(0xff059669),
            ),
            _BranchMetricCard(
              label: 'Below 97%',
              value: '$below97',
              detail: loaded == 0
                  ? '0% of loaded branches'
                  : '${_fmt(below97 / loaded * 100)}% of loaded branches',
              icon: Icons.trending_down_rounded,
              color: const Color(0xffD97706),
            ),
            _BranchMetricCard(
              label: 'Below 90%',
              value: '$below90',
              detail: 'Branches needing immediate attention',
              icon: Icons.warning_amber_rounded,
              color: const Color(0xffDC2626),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: _cardDecoration(),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom: BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.account_tree_outlined,
                              color: AppColors.primaryColor,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: SelectableText(
                                'Branch Availability Report',
                                style: TextStyle(
                                  color: Color(0xff0F172A),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            SelectableText(
                              '$visibleRows of $loaded loaded branches',
                              style: const TextStyle(
                                color: Color(0xff64748B),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: () {
                                _source.clearAllFilters();
                                setState(() {});
                              },
                              icon: const Icon(
                                Icons.filter_alt_off_outlined,
                                size: 18,
                              ),
                              label: const Text('Clear column filters'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primaryColor,
                                side: const BorderSide(
                                  color: AppColors.primaryColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              onPressed: visibleRows == 0 || _exporting
                                  ? null
                                  : _export,
                              icon: _exporting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.file_download_outlined,
                                      size: 19,
                                    ),
                              label: Text(
                                _exporting ? 'Exporting...' : 'Export Excel',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xff059669),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          spacing: 10,
                          children: [
                            SizedBox(
                              width: 330,
                              child: TextField(
                                controller: _searchController,
                                onChanged: (_) => setState(_applyReportFilters),
                                decoration: InputDecoration(
                                  hintText: 'Search branch...',
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  isDense: true,
                                  filled: true,
                                  fillColor: const Color(0xffF8FAFC),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: AppColors.border,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            _BranchBandChip(
                              label: 'All',
                              selected: _band == 'all',
                              onSelected: () => _setBand('all'),
                            ),
                            _BranchBandChip(
                              label: '97% and Above',
                              selected: _band == 'at_least_97',
                              onSelected: () => _setBand('at_least_97'),
                            ),
                            _BranchBandChip(
                              label: 'Below 97%',
                              selected: _band == 'below_97',
                              onSelected: () => _setBand('below_97'),
                            ),
                            _BranchBandChip(
                              label: 'Below 95%',
                              selected: _band == 'below_95',
                              onSelected: () => _setBand('below_95'),
                            ),
                            _BranchBandChip(
                              label: 'Below 90%',
                              selected: _band == 'below_90',
                              onSelected: () => _setBand('below_90'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (widget.loading)
                    LinearProgressIndicator(
                      minHeight: 4,
                      color: AppColors.primaryColor,
                      backgroundColor: AppColors.primaryColor.withValues(
                        alpha: .1,
                      ),
                    ),
                  SizedBox(
                    height: 650,
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: Theme.of(context).colorScheme.copyWith(
                          primary: AppColors.primaryColor,
                          secondary: AppColors.primaryColor,
                        ),
                      ),
                      child: SfDataGridTheme(
                        data: SfDataGridThemeData(
                          headerColor: const Color(0xffCFE4EC),
                          gridLineColor: const Color(0xffC4D0DA),
                          selectionColor: AppColors.primaryColor.withValues(
                            alpha: .1,
                          ),
                          rowHoverColor: AppColors.rowHover,
                          sortIconColor: AppColors.secondaryColor,
                          filterIconColor: AppColors.secondaryColor,
                          filterIconHoverColor: AppColors.primaryColor,
                        ),
                        child: SfDataGrid(
                          source: _source,
                          allowFiltering: true,
                          allowSorting: true,
                          allowMultiColumnSorting: true,
                          allowTriStateSorting: true,
                          allowColumnsResizing: true,
                          columnResizeMode: ColumnResizeMode.onResize,
                          gridLinesVisibility: GridLinesVisibility.both,
                          headerGridLinesVisibility:
                              GridLinesVisibility.vertical,
                          columnWidthMode: ColumnWidthMode.none,
                          rowHeight: 58,
                          headerRowHeight: 70,
                          selectionMode: SelectionMode.single,
                          navigationMode: GridNavigationMode.cell,
                          onFilterChanged: (_) => setState(() {}),
                          onColumnSortChanged: (_, _) => setState(() {}),
                          columns: _branchReportColumns,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_exporting)
                Positioned.fill(
                  child: _ExportLoadingOverlay(rowCount: visibleRows),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _setBand(String value) {
    setState(() {
      _band = value;
      _applyReportFilters();
    });
  }
}

class _BranchMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;

  const _BranchMetricCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 315,
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  label,
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SelectableText(
                  detail,
                  maxLines: 2,
                  style: const TextStyle(
                    color: Color(0xff94A3B8),
                    fontSize: 11.5,
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
}

class _BranchBandChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _BranchBandChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      onSelected: (_) => onSelected(),
      label: Text(label),
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.secondaryColor,
        fontWeight: FontWeight.w800,
      ),
      selectedColor: AppColors.primaryColor,
      backgroundColor: Colors.white,
      side: const BorderSide(color: AppColors.border),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }
}

final List<GridColumn> _branchReportColumns = [
  _availabilityColumn('branch', 'Branch', 260, alignLeft: true),
  _availabilityColumn('availability', 'Availability\nRate', 185),
  _availabilityColumn('performance', 'Performance\nBand', 185),
  _availabilityColumn('items', 'KPI\nItems', 145),
  _availabilityColumn('covered', 'Fully Covered\nItems', 185),
  _availabilityColumn('below_need', 'Below 7-Day\nNeed', 185),
  _availabilityColumn('top_sellers', 'Top Seller\nItems', 175),
  _availabilityColumn('regular', 'Regular Seller\nItems', 185),
  _availabilityColumn('weekly_need', 'Total 7-Day\nNeed', 180),
  _availabilityColumn('stock', 'Current Branch\nStock', 195),
  _availabilityColumn('missing', 'Units\nMissing', 165),
];

class _BranchReportGridSource extends DataGridSource {
  final ValueChanged<String> onOpenBranch;
  List<DataGridRow> _rows = const [];
  final Map<DataGridRow, AvailabilityBranchSummary> _summaryByRow = {};
  final Map<DataGridRow, int> _indexByRow = {};

  _BranchReportGridSource(
    List<AvailabilityBranchSummary> summaries, {
    required this.onOpenBranch,
  }) {
    update(summaries);
  }

  void update(List<AvailabilityBranchSummary> summaries) {
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
                columnName: 'availability',
                value: summary.availabilityRate,
              ),
              DataGridCell<String>(
                columnName: 'performance',
                value: _branchPerformanceBand(summary.availabilityRate),
              ),
              DataGridCell<int>(
                columnName: 'items',
                value: summary.masterItems,
              ),
              DataGridCell<int>(
                columnName: 'covered',
                value: summary.fullyAvailableItems,
              ),
              DataGridCell<int>(
                columnName: 'below_need',
                value: summary.shortageItems,
              ),
              DataGridCell<int>(
                columnName: 'top_sellers',
                value: summary.paretoItems,
              ),
              DataGridCell<int>(
                columnName: 'regular',
                value: summary.consistentItems,
              ),
              DataGridCell<num>(
                columnName: 'weekly_need',
                value: summary.weeklyNeed,
              ),
              DataGridCell<num>(
                columnName: 'stock',
                value: summary.branchStock,
              ),
              DataGridCell<num>(
                columnName: 'missing',
                value: summary.stockShortage,
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

  void clearAllFilters() => clearFilters();

  List<AvailabilityBranchSummary> get visibleSummaries {
    final visibleRows = effectiveRows.isEmpty && filterConditions.isEmpty
        ? _rows
        : effectiveRows;
    return visibleRows
        .map((row) => _summaryByRow[row])
        .whereType<AvailabilityBranchSummary>()
        .toList(growable: false);
  }

  @override
  List<DataGridRow> get rows => _rows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final summary = _summaryByRow[row]!;
    final rowColor = (_indexByRow[row] ?? 0).isOdd
        ? const Color(0xffFAFCFD)
        : Colors.white;
    return DataGridRowAdapter(
      color: rowColor,
      cells: row
          .getCells()
          .map((cell) {
            late final Widget child;
            switch (cell.columnName) {
              case 'branch':
                child = InkWell(
                  onTap: () => onOpenBranch(summary.branchName),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.storefront_outlined,
                        size: 18,
                        color: AppColors.primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SelectableText(
                          summary.branchName,
                          maxLines: 2,
                          style: const TextStyle(
                            color: AppColors.secondaryColor,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.open_in_new_rounded,
                        size: 15,
                        color: Color(0xff94A3B8),
                      ),
                    ],
                  ),
                );
                break;
              case 'availability':
                final color = _rateColor(summary.availabilityRate);
                child = Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SelectableText(
                      '${_fmt(summary.availabilityRate)}%',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 9),
                    SizedBox(
                      width: 58,
                      child: LinearProgressIndicator(
                        minHeight: 5,
                        value: (summary.availabilityRate / 100)
                            .clamp(0, 1)
                            .toDouble(),
                        color: color,
                        backgroundColor: color.withValues(alpha: .12),
                      ),
                    ),
                  ],
                );
                break;
              case 'performance':
                final color = _rateColor(summary.availabilityRate);
                child = Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: color.withValues(alpha: .25)),
                  ),
                  child: SelectableText(
                    _branchPerformanceBand(summary.availabilityRate),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                );
                break;
              case 'missing':
                child = SelectableText(
                  _fmt(summary.stockShortage),
                  style: TextStyle(
                    color: summary.stockShortage > 0
                        ? const Color(0xffDC2626)
                        : const Color(0xff059669),
                    fontWeight: FontWeight.w900,
                  ),
                );
                break;
              default:
                child = SelectableText(
                  cell.value is num ? _fmt(cell.value as num) : '${cell.value}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontWeight: FontWeight.w700,
                  ),
                );
            }
            return Container(
              alignment: cell.columnName == 'branch'
                  ? Alignment.centerLeft
                  : Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: child,
            );
          })
          .toList(growable: false),
    );
  }
}

String _branchPerformanceBand(num rate) {
  if (rate >= 97) return '97% and Above';
  if (rate >= 95) return '95% to 96.9%';
  if (rate >= 90) return '90% to 94.9%';
  return 'Below 90%';
}

class _MasterTable extends StatefulWidget {
  final String branch;
  final String stockDate;
  final List<AvailabilityKpiItem> items;
  final bool loading;
  final int totalRows;
  final bool exportingAllBranches;
  final double allBranchesExportProgress;
  final String allBranchesExportStatus;
  final VoidCallback onExportAllBranches;

  const _MasterTable({
    required this.branch,
    required this.stockDate,
    required this.items,
    required this.loading,
    required this.totalRows,
    required this.exportingAllBranches,
    required this.allBranchesExportProgress,
    required this.allBranchesExportStatus,
    required this.onExportAllBranches,
  });

  @override
  State<_MasterTable> createState() => _MasterTableState();
}

class _MasterTableState extends State<_MasterTable> {
  late final _AvailabilityKpiGridSource _source;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _source = _AvailabilityKpiGridSource(widget.items);
  }

  @override
  void didUpdateWidget(covariant _MasterTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items)) _source.update(widget.items);
  }

  Future<void> _export() async {
    final visible = _source.visibleItems;
    if (visible.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      // Give Flutter time to paint the export overlay before XLSX generation,
      // which is CPU intensive on the web UI isolate.
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await AvailabilityKpiExcelExporter.export(
        branch: widget.branch,
        stockDate: widget.stockDate,
        items: visible,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Text('${visible.length} filtered items exported.'),
            ],
          ),
          backgroundColor: const Color(0xff059669),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Excel export failed: $error'),
          backgroundColor: const Color(0xffDC2626),
        ),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleRows = _source.visibleItems.length;
    return Container(
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 13, 14, 13),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Icon(
                      Icons.table_chart_rounded,
                      color: AppColors.primaryColor,
                    ),
                    SizedBox(
                      width: 470,
                      child: SelectableText(
                        '${widget.branch} • Items included in Availability KPI',
                        maxLines: 1,
                        style: const TextStyle(
                          color: Color(0xff0F172A),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    SelectableText(
                      '$visibleRows of ${widget.totalRows} items',
                      style: const TextStyle(
                        color: Color(0xff64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: widget.loading
                          ? null
                          : () {
                              _source.clearAllFilters();
                              setState(() {});
                            },
                      icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                      label: const Text('Clear column filters'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryColor,
                        side: const BorderSide(color: AppColors.primaryColor),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed:
                          widget.loading ||
                              visibleRows == 0 ||
                              _exporting ||
                              widget.exportingAllBranches
                          ? null
                          : _export,
                      icon: _exporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.file_download_outlined, size: 19),
                      label: Text(_exporting ? 'Exporting...' : 'Export Excel'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xff059669),
                        foregroundColor: Colors.white,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed:
                          widget.loading ||
                              _exporting ||
                              widget.exportingAllBranches
                          ? null
                          : widget.onExportAllBranches,
                      icon: widget.exportingAllBranches
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.file_download_done_rounded),
                      label: Text(
                        widget.exportingAllBranches
                            ? 'Preparing All Branches...'
                            : 'Export All Branches',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.secondaryColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.loading)
                const SizedBox(
                  height: 260,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (widget.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(
                    child: SelectableText(
                      'No items match the selected filters.',
                      style: TextStyle(
                        color: Color(0xff64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 660,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xffAEBFCC)),
                    ),
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: Theme.of(context).colorScheme.copyWith(
                          primary: AppColors.primaryColor,
                          secondary: AppColors.primaryColor,
                        ),
                        checkboxTheme: CheckboxThemeData(
                          fillColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? AppColors.primaryColor
                                : null,
                          ),
                        ),
                      ),
                      child: SfDataGridTheme(
                        data: SfDataGridThemeData(
                          headerColor: const Color(0xffCFE4EC),
                          gridLineColor: const Color(0xffC4D0DA),
                          selectionColor: AppColors.primaryColor.withValues(
                            alpha: .1,
                          ),
                          rowHoverColor: AppColors.rowHover,
                          sortIconColor: AppColors.secondaryColor,
                          filterIconColor: AppColors.secondaryColor,
                          filterIconHoverColor: AppColors.primaryColor,
                          currentCellStyle: const DataGridCurrentCellStyle(
                            borderColor: AppColors.primaryColor,
                            borderWidth: 1.5,
                          ),
                        ),
                        child: SfDataGrid(
                          source: _source,
                          allowFiltering: true,
                          allowSorting: true,
                          allowMultiColumnSorting: true,
                          allowTriStateSorting: true,
                          allowColumnsResizing: true,
                          columnResizeMode: ColumnResizeMode.onResize,
                          gridLinesVisibility: GridLinesVisibility.both,
                          headerGridLinesVisibility:
                              GridLinesVisibility.vertical,
                          columnWidthMode: ColumnWidthMode.none,
                          frozenColumnsCount: 0,
                          rowHeight: 62,
                          headerRowHeight: 72,
                          selectionMode: SelectionMode.single,
                          navigationMode: GridNavigationMode.cell,
                          onFilterChanged: (_) => setState(() {}),
                          onColumnSortChanged: (_, _) => setState(() {}),
                          columns: _availabilityColumns(
                            _lastStudyMonthForTable(
                              widget.items,
                              widget.stockDate,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_exporting || widget.exportingAllBranches)
            Positioned.fill(
              child: _ExportLoadingOverlay(
                rowCount: visibleRows,
                allBranches: widget.exportingAllBranches,
                progress: widget.exportingAllBranches
                    ? widget.allBranchesExportProgress
                    : null,
                status: widget.exportingAllBranches
                    ? widget.allBranchesExportStatus
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _ExportLoadingOverlay extends StatelessWidget {
  final int rowCount;
  final bool allBranches;
  final double? progress;
  final String? status;

  const _ExportLoadingOverlay({
    required this.rowCount,
    this.allBranches = false,
    this.progress,
    this.status,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xff0F172A).withValues(alpha: .32),
      child: Center(
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x330F172A),
                blurRadius: 30,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xff059669).withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.table_view_rounded,
                  color: Color(0xff059669),
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                allBranches ? 'Exporting All Branches' : 'Preparing Excel file',
                style: const TextStyle(
                  color: Color(0xff0F172A),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                status ?? 'Formatting $rowCount filtered items...',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xff64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress?.clamp(0, 1),
                  minHeight: 7,
                  color: const Color(0xff10B981),
                  backgroundColor: const Color(0xffD1FAE5),
                ),
              ),
              if (progress != null) ...[
                const SizedBox(height: 9),
                Text(
                  '${(progress! * 100).round()}%',
                  style: const TextStyle(
                    color: AppColors.secondaryColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                'The download will start automatically',
                style: TextStyle(color: Color(0xff94A3B8), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<GridColumn> _availabilityColumns(int lastStudyMonth) => [
  _availabilityColumn('item_code', 'Item Code', 175),
  _availabilityColumn('item_name', 'Item Name', 340),
  _availabilityColumn('selection', 'Selection Reason', 235),
  _availabilityColumn('sales', '3-Month\nUnits Sold', 190),
  _availabilityColumn('notes', 'Notes', 310, alignLeft: true),
  _availabilityColumn('retail', 'Retail\nPrice', 165),
  _availabilityColumn('sales_value', 'Retail Sales\nValue', 190),
  _availabilityColumn('share', 'Branch Sales\nShare', 195),
  _availabilityColumn('months', 'Months Sold\n(1-$lastStudyMonth)', 190),
  _availabilityColumn('consistency', 'Selling\nConsistency', 190),
  _availabilityColumn('weekly_need', '7-Day\nNeed', 170),
  _availabilityColumn('stock', 'Branch\nStock', 170),
  _availabilityColumn('store_stock', 'Store\nStock', 175),
  _availabilityColumn('shortage', 'Units\nMissing', 165),
  _availabilityColumn('extra_qty', 'Total Extra Qty\nAll Branches', 205),
  _availabilityColumn('coverage', '7-Day\nCoverage', 185),
  _availabilityColumn('status', 'Purchase\nStatus', 220),
];

int _lastStudyMonthForTable(List<AvailabilityKpiItem> items, String stockDate) {
  for (final item in items) {
    final asOfDate = item.asOfDate;
    if (asOfDate != null) return asOfDate.month;
  }
  return DateTime.tryParse(stockDate)?.month ?? DateTime.now().month;
}

String _soldMonthText(AvailabilityKpiItem item) {
  if (item.sellingMonthNumbers.isNotEmpty) {
    return item.sellingMonthNumbers.join(', ');
  }
  if (item.sellingMonths == item.totalMonths && item.totalMonths > 0) {
    final lastMonth = item.asOfDate?.month ?? DateTime.now().month;
    return List<int>.generate(lastMonth, (index) => index + 1).join(', ');
  }
  return '${item.sellingMonths} / ${item.totalMonths}';
}

GridColumn _availabilityColumn(
  String name,
  String title,
  double width, {
  bool alignLeft = false,
}) => GridColumn(
  columnName: name,
  width: _columnWidthForHeader(title, width),
  minimumWidth: 105,
  label: Container(
    padding: EdgeInsets.fromLTRB(alignLeft ? 16 : 12, 10, 12, 10),
    alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
    child: SelectableText(
      title,
      maxLines: 2,
      textAlign: alignLeft ? TextAlign.left : TextAlign.center,
      style: const TextStyle(
        color: AppColors.secondaryColor,
        fontSize: 12.5,
        height: 1.15,
        letterSpacing: .1,
        fontWeight: FontWeight.w800,
      ),
    ),
  ),
);

double _columnWidthForHeader(String title, double requestedWidth) {
  final longestLine = title
      .split('\n')
      .map((line) => line.trim().length)
      .fold<int>(0, math.max);
  // Text width + sorting/filter actions + comfortable horizontal padding.
  final titleBasedWidth = (longestLine * 8.5) + 76;
  return math.max(requestedWidth, titleBasedWidth);
}

class _AvailabilityKpiGridSource extends DataGridSource {
  List<DataGridRow> _rows = const [];
  final Map<DataGridRow, AvailabilityKpiItem> _itemByRow = {};
  final Map<DataGridRow, int> _indexByRow = {};

  _AvailabilityKpiGridSource(List<AvailabilityKpiItem> items) {
    update(items);
  }

  void update(List<AvailabilityKpiItem> items) {
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
                columnName: 'item_code',
                value: item.itemCode,
              ),
              DataGridCell<String>(
                columnName: 'item_name',
                value: item.itemName,
              ),
              DataGridCell<String>(
                columnName: 'selection',
                value: _selectionLabel(item),
              ),
              DataGridCell<num>(columnName: 'sales', value: item.recentSales),
              DataGridCell<String>(
                columnName: 'notes',
                value: item.decreaseDemand30Days == null
                    ? ''
                    : 'Branch decrease • Demand 30 days: ${_fmt(item.decreaseDemand30Days!)}',
              ),
              DataGridCell<num>(columnName: 'retail', value: item.retail),
              DataGridCell<num>(
                columnName: 'sales_value',
                value: item.recentSalesValue,
              ),
              DataGridCell<num>(
                columnName: 'share',
                value: item.recentSalesShare,
              ),
              DataGridCell<String>(
                columnName: 'months',
                value: _soldMonthText(item),
              ),
              DataGridCell<num>(
                columnName: 'consistency',
                value: item.monthConsistency,
              ),
              DataGridCell<num>(
                columnName: 'weekly_need',
                value: item.weeklyNeed,
              ),
              DataGridCell<num>(columnName: 'stock', value: item.branchStock),
              DataGridCell<num>(
                columnName: 'store_stock',
                value: item.storeStock,
              ),
              DataGridCell<num>(
                columnName: 'shortage',
                value: item.stockShortage,
              ),
              DataGridCell<num?>(
                columnName: 'extra_qty',
                value: item.availabilityRate < 100
                    ? item.extraQtyMoreThanMonth
                    : null,
              ),
              DataGridCell<num>(
                columnName: 'coverage',
                value: item.availabilityRate,
              ),
              DataGridCell<String>(
                columnName: 'status',
                value: item.availabilityRate < 100 ? item.statusName : '',
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

  void clearAllFilters() => clearFilters();

  List<AvailabilityKpiItem> get visibleItems {
    final visibleRows = effectiveRows.isEmpty && filterConditions.isEmpty
        ? _rows
        : effectiveRows;
    return visibleRows
        .map((row) => _itemByRow[row])
        .whereType<AvailabilityKpiItem>()
        .toList(growable: false);
  }

  @override
  List<DataGridRow> get rows => _rows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final item = _itemByRow[row]!;
    final rowColor = (_indexByRow[row] ?? 0).isOdd
        ? const Color(0xffFAFCFD)
        : Colors.white;
    return DataGridRowAdapter(
      color: rowColor,
      cells: row
          .getCells()
          .map((cell) {
            final alignLeft =
                cell.columnName == 'item_name' || cell.columnName == 'notes';
            late final Widget child;
            switch (cell.columnName) {
              case 'coverage':
                final color = _rateColor(item.availabilityRate);
                child = Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        '${_fmt(item.availabilityRate)}%',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        minHeight: 5,
                        value: (item.availabilityRate / 100)
                            .clamp(0, 1)
                            .toDouble(),
                        color: color,
                        backgroundColor: color.withValues(alpha: .12),
                      ),
                    ],
                  ),
                );
                break;
              case 'selection':
                child = _SourceBadge(item: item);
                break;
              case 'notes':
                final hasDecrease = item.decreaseDemand30Days != null;
                child = hasDecrease
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xffFFF7ED),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xffFDBA74)),
                        ),
                        child: SelectableText(
                          'Branch decrease • Demand 30 days: ${_fmt(item.decreaseDemand30Days!)}',
                          maxLines: 2,
                          style: const TextStyle(
                            color: Color(0xff9A3412),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : const SelectableText(
                        '—',
                        style: TextStyle(color: Color(0xff94A3B8)),
                      );
                break;
              case 'status':
                final showStatus =
                    item.availabilityRate < 100 && item.statusName.isNotEmpty;
                child = Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: showStatus
                        ? const Color(0xffEFF6FF)
                        : const Color(0xffF8FAFC),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: showStatus
                          ? const Color(0xffBFDBFE)
                          : const Color(0xffCBD5E1),
                    ),
                  ),
                  child: SelectableText(
                    showStatus ? item.statusName : '—',
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: showStatus
                          ? AppColors.secondaryColor
                          : const Color(0xff64748B),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                );
                break;
              case 'consistency':
                child = _ConsistencyBadge(rate: item.monthConsistency);
                break;
              case 'share':
                child = SelectableText('${_fmt(item.recentSalesShare)}%');
                break;
              case 'months':
                child = Tooltip(
                  message:
                      'Sold in ${item.sellingMonths} of ${item.totalMonths} studied months',
                  child: SelectableText(
                    _soldMonthText(item),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                );
                break;
              case 'shortage':
                child = SelectableText(
                  _fmt(item.stockShortage),
                  style: TextStyle(
                    color: item.stockShortage > 0
                        ? const Color(0xffDC2626)
                        : const Color(0xff059669),
                    fontWeight: FontWeight.w900,
                  ),
                );
                break;
              case 'extra_qty':
                final hasExtra = item.extraQtyMoreThanMonth > 0;
                child = Tooltip(
                  message: hasExtra
                      ? 'Total extra quantity for this item across all branches'
                      : item.availabilityRate >= 100
                      ? 'Item is already fully covered'
                      : 'No extra quantity found in any branch',
                  child: SelectableText(
                    item.availabilityRate < 100
                        ? hasExtra
                              ? _fmt(item.extraQtyMoreThanMonth)
                              : '0'
                        : '—',
                    style: TextStyle(
                      color: hasExtra
                          ? const Color(0xff0369A1)
                          : const Color(0xff64748B),
                      fontWeight: hasExtra ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                );
                break;
              default:
                child = SelectableText(
                  cell.value is num ? _fmt(cell.value as num) : '${cell.value}',
                  maxLines: cell.columnName == 'item_name' ? 2 : 1,
                  style: TextStyle(
                    color: const Color(0xff0F172A),
                    fontWeight:
                        {
                          'item_code',
                          'item_name',
                          'retail',
                          'sales_value',
                          'weekly_need',
                          'stock',
                          'store_stock',
                        }.contains(cell.columnName)
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                );
            }
            return Container(
              alignment: alignLeft ? Alignment.centerLeft : Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: child,
            );
          })
          .toList(growable: false),
    );
  }
}

String _selectionLabel(AvailabilityKpiItem item) {
  return item.inPareto
      ? 'Top seller — 60% of branch sales value'
      : 'Sold regularly';
}

class _SourceBadge extends StatelessWidget {
  final AvailabilityKpiItem item;

  const _SourceBadge({required this.item});

  @override
  Widget build(BuildContext context) {
    final label = item.inPareto ? 'Top seller • Branch 60%' : 'Sold regularly';
    final color = item.inPareto
        ? AppColors.primaryColor
        : const Color(0xff0F766E);
    return Tooltip(message: _selectionLabel(item), child: _badge(label, color));
  }
}

class _ConsistencyBadge extends StatelessWidget {
  final num rate;

  const _ConsistencyBadge({required this.rate});

  @override
  Widget build(BuildContext context) {
    final color = rate >= 80
        ? const Color(0xff059669)
        : rate >= 60
        ? const Color(0xffD97706)
        : const Color(0xff64748B);
    return _badge('${_fmt(rate)}%', color);
  }
}

class _LoadingCard extends StatelessWidget {
  final String label;

  const _LoadingCard({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 240,
      decoration: _cardDecoration(),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 14),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(46),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Icon(icon, size: 46, color: const Color(0xff94A3B8)),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xff64748B)),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xffFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xffDC2626)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xff991B1B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: const Color(0xffE2E8F0)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: .035),
        blurRadius: 16,
        offset: const Offset(0, 7),
      ),
    ],
  );
}

InputDecoration _inputDecoration({
  required String hint,
  required IconData icon,
}) {
  return InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon),
    isDense: true,
    filled: true,
    fillColor: const Color(0xffF8FAFC),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Color(0xffCBD5E1)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Color(0xffCBD5E1)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Color(0xff2563EB), width: 1.5),
    ),
  );
}

Widget _badge(String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withValues(alpha: .22)),
    ),
    child: SelectableText(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900),
    ),
  );
}

Color _rateColor(num rate) {
  if (rate >= 95) return const Color(0xff059669);
  if (rate >= 80) return const Color(0xffD97706);
  return const Color(0xffDC2626);
}

String _fmt(num value) {
  if (value % 1 == 0) return value.toInt().toString();
  return value.toStringAsFixed(1);
}

String _friendlyError(Object error) {
  final message = error.toString();
  if (message.contains('No stock snapshot found')) {
    return message.replaceFirst('Bad state: ', '');
  }
  if (message.contains('57014') || message.contains('statement timeout')) {
    return 'The selected branch stock lookup timed out. Run the latest availability_kpi_quick_fix.sql once to add the daily_order lookup index, then retry.';
  }
  if (message.contains('get_availability_branch_summary_fast')) {
    return 'The fast single-branch Availability function is not installed. Run the latest availability_kpi_quick_fix.sql, then reload the app.';
  }
  if (message.contains('get_availability_') ||
      message.contains('availability_branch_master')) {
    return 'Availability database functions are not installed yet. Run the Availability KPI SQL migration in Supabase and retry.';
  }
  return 'Could not load Availability KPI data. $message';
}
