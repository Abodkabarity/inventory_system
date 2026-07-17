import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/allocation_result_row.dart';
import '../../../domain/entities/branch_allocation_task.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';
import 'stock_check_page.dart';

class AllocationPage extends StatefulWidget {
  final String runDate;

  const AllocationPage({super.key, required this.runDate});

  @override
  State<AllocationPage> createState() => _AllocationPageState();
}

class _AllocationPageState extends State<AllocationPage> {
  final Set<String> _donorBranches = {};
  final Set<String> _receiverBranches = {};
  final Set<String> _priorityBranches = {};
  final Set<String> _categories = {};
  final Set<String> _itemStatuses = {};
  final Set<String> _donorStockCovers = {};
  final Set<String> _receiverStockCovers = {};
  int? _minimumDemandFor30Days;
  final TextEditingController _allocationSearchController =
      TextEditingController();
  final TextEditingController _sentAllocationSearchController =
      TextEditingController();
  String _allocationSearch = '';
  String _sentAllocationSearch = '';
  String _sentAllocationStatusFilter = 'all';
  bool _donorsInitialized = false;
  bool _receiversInitialized = false;
  bool _categoriesInitialized = false;
  bool _itemStatusesInitialized = false;
  List<String> getBranchNames(List<Map<String, dynamic>> branches) {
    return branches
        .map((e) => (e['branch_name'] ?? '').toString())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    context.read<InventoryBloc>().add(LoadAllocationFilters(widget.runDate));
    context.read<InventoryBloc>().add(
      LoadSentBranchAllocations(widget.runDate),
    );
  }

  @override
  void didUpdateWidget(covariant AllocationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runDate == widget.runDate) return;

    _donorBranches.clear();
    _receiverBranches.clear();
    _priorityBranches.clear();
    _categories.clear();
    _itemStatuses.clear();
    _donorStockCovers.clear();
    _receiverStockCovers.clear();
    _minimumDemandFor30Days = null;
    _donorsInitialized = false;
    _receiversInitialized = false;
    _categoriesInitialized = false;
    _itemStatusesInitialized = false;
    context.read<InventoryBloc>().add(LoadAllocationFilters(widget.runDate));
    context.read<InventoryBloc>().add(
      LoadSentBranchAllocations(widget.runDate),
    );
  }

  @override
  void dispose() {
    _allocationSearchController.dispose();
    _sentAllocationSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, state) {
        if (!state.isAllocationFiltersLoading) {
          _selectDefaults(state);
        }
        final pullStockCoverOptions = _pullStockCoverOptions(
          state.allocationStockCoverOptions,
        );
        final supplyStockCoverOptions = _supplyStockCoverOptions(
          state.allocationStockCoverOptions,
        );
        _donorStockCovers.removeWhere(
          (value) => !pullStockCoverOptions.contains(value),
        );
        _receiverStockCovers.removeWhere(
          (value) => !supplyStockCoverOptions.contains(value),
        );
        final visibleResults = _filterResults(state.allocationResults);

        return Container(
          color: const Color(0xffF4F7FB),
          child: Column(
            children: [
              _Header(
                runDate: widget.runDate,
                resultsCount: state.allocationResults.length,
                isLoading: state.isAllocationLoading,
                isSending: state.isAllocationSending,
                loadedRows: state.allocationLoadedRows,
                onRun: () => _run(context),
                onImport: () => _import(context),
                onSend: state.allocationResults.isEmpty
                    ? null
                    : () => _sendAllocation(context),
                onExport: state.allocationResults.isEmpty
                    ? null
                    : () => context.read<InventoryBloc>().add(
                        ExportAllocationResults(),
                      ),
                onShortageExport: state.allocationSourceRows.isEmpty
                    ? null
                    : () => context.read<InventoryBloc>().add(
                        ExportAllocationShortage(),
                      ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(28, 18, 28, 28),
                  children: [
                    if (state.isAllocationFiltersLoading)
                      const _AllocationFiltersLoadingCard()
                    else
                      _FiltersCard(
                        branches: state.allocationBranches,
                        categories: state.allocationCategories,
                        itemStatuses: state.allocationItemStatuses,
                        pullStockCoverOptions: pullStockCoverOptions,
                        supplyStockCoverOptions: supplyStockCoverOptions,
                        donorBranches: _donorBranches,
                        receiverBranches: _receiverBranches,
                        priorityBranches: _priorityBranches,
                        selectedCategories: _categories,
                        selectedItemStatuses: _itemStatuses,
                        donorStockCovers: _donorStockCovers,
                        receiverStockCovers: _receiverStockCovers,
                        minimumDemandFor30Days: _minimumDemandFor30Days,
                        onDemandChanged: (value) {
                          setState(() => _minimumDemandFor30Days = value);
                        },
                        onChanged: () => setState(() {}),
                      ),
                    const SizedBox(height: 18),
                    if (state.allocationError.isNotEmpty)
                      _ErrorBanner(message: state.allocationError),
                    if (state.allocationMessage.isNotEmpty)
                      _SuccessBanner(message: state.allocationMessage),
                    _SummaryStrip(results: visibleResults),
                    const SizedBox(height: 18),
                    _ResultsTable(
                      rows: visibleResults,
                      totalRows: state.allocationResults.length,
                      searchValue: _allocationSearch,
                      searchController: _allocationSearchController,
                      onSearchChanged: (value) {
                        setState(() => _allocationSearch = value);
                      },
                    ),
                    if (state.sentBranchAllocations.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _SentAllocationStatusCard(
                        rows: state.sentBranchAllocations,
                        searchController: _sentAllocationSearchController,
                        query: _sentAllocationSearch,
                        statusFilter: _sentAllocationStatusFilter,
                        onQueryChanged: (value) {
                          setState(() => _sentAllocationSearch = value);
                        },
                        onStatusChanged: (value) {
                          setState(() => _sentAllocationStatusFilter = value);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _run(BuildContext context) {
    const noSelection = '__NO_ALLOCATION_SELECTION__';

    List<String> effectiveSelection(Set<String> selected, List<String> source) {
      if (source.isEmpty) return [];
      if (selected.length == source.length) return [];
      if (selected.isEmpty) return [noSelection];
      return selected.toList();
    }

    context.read<InventoryBloc>().add(
      RunAllocation(
        runDate: widget.runDate,
        donorBranches: effectiveSelection(
          _donorBranches,
          getBranchNames(
            context.read<InventoryBloc>().state.allocationBranches,
          ),
        ),
        receiverBranches: effectiveSelection(
          _receiverBranches,
          getBranchNames(
            context.read<InventoryBloc>().state.allocationBranches,
          ),
        ),
        priorityBranches: _priorityBranches.toList(),
        categories: effectiveSelection(
          _categories,
          context.read<InventoryBloc>().state.allocationCategories,
        ),
        itemStatuses: effectiveSelection(
          _itemStatuses,
          context.read<InventoryBloc>().state.allocationItemStatuses,
        ),
        donorStockCovers: _donorStockCovers.toList(),
        receiverStockCovers: _receiverStockCovers.toList(),
        minimumDemandFor30Days: _minimumDemandFor30Days,
      ),
    );
  }

  Future<void> _sendAllocation(BuildContext context) async {
    final draft = await _askAllocationBatchTitle(context, widget.runDate);
    if (!context.mounted || draft == null) return;

    context.read<InventoryBloc>().add(
      SendAllocationToBranches(
        runDate: widget.runDate,
        batchTitle: draft.title,
        expiresAt: draft.expiresAt,
      ),
    );
  }

  Future<_AllocationSendDraft?> _askAllocationBatchTitle(
    BuildContext context,
    String runDate,
  ) async {
    final controller = TextEditingController(text: 'Allocation $runDate');
    var expiresAt = DateTime.now()
        .add(const Duration(days: 7))
        .copyWith(hour: 23, minute: 59, second: 59, millisecond: 0);
    String error = '';

    final result = await showDialog<_AllocationSendDraft>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void finish() {
              final value = controller.text.trim();
              if (value.isEmpty) {
                setDialogState(() => error = 'Batch title is required');
                return;
              }
              if (!expiresAt.isAfter(DateTime.now())) {
                setDialogState(() => error = 'Choose a future deadline');
                return;
              }
              Navigator.pop(
                dialogContext,
                _AllocationSendDraft(title: value, expiresAt: expiresAt),
              );
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
              contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
              actionsPadding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
              title: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xffDBEAFE),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.drive_file_rename_outline_rounded,
                      color: Color(0xff2563EB),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Name Allocation Batch',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This title will appear for the branch instead of a random batch number.',
                      style: TextStyle(
                        color: Color(0xff64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Batch title',
                        hintText: 'Example: Dubai allocation 01-07',
                        errorText: error.isEmpty ? null : error,
                        prefixIcon: const Icon(Icons.title_rounded),
                        filled: true,
                        fillColor: const Color(0xffF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onSubmitted: (_) => finish(),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Allocation completion deadline',
                      style: TextStyle(
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDialog<DateTimeRange>(
                          context: dialogContext,
                          builder: (_) => StockCheckDateRangePickerDialog(
                            initialRange: DateTimeRange(
                              start: DateTime(now.year, now.month, now.day),
                              end: expiresAt,
                            ),
                            mode: StockCheckDateRangePickerMode.deadline,
                          ),
                        );
                        if (picked == null) return;
                        final end = picked.end;
                        setDialogState(() {
                          expiresAt = DateTime(
                            end.year,
                            end.month,
                            end.day,
                            23,
                            59,
                            59,
                          );
                          error = '';
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF5EEAD4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.timer_rounded,
                              color: Color(0xFF0F766E),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Deadline ${_fmtAllocationDeadline(expiresAt)}',
                                style: const TextStyle(
                                  color: Color(0xFF0F766E),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.edit_calendar_rounded,
                              color: Color(0xFF0F766E),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: finish,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Send Allocation'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff0F766E),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
    return result;
  }

  void _import(BuildContext context) {
    context.read<InventoryBloc>().add(
      ImportAllocationFile(priorityBranches: _priorityBranches.toList()),
    );
  }

  void _selectDefaults(InventoryState state) {
    if (!_donorsInitialized && state.allocationBranches.isNotEmpty) {
      _donorBranches.addAll(getBranchNames(state.allocationBranches));
      _donorsInitialized = true;
    }

    if (!_receiversInitialized && state.allocationBranches.isNotEmpty) {
      _receiverBranches.addAll(getBranchNames(state.allocationBranches));
      _receiversInitialized = true;
    }

    if (!_categoriesInitialized && state.allocationCategories.isNotEmpty) {
      _categories.addAll(state.allocationCategories);
      _categoriesInitialized = true;
    }

    if (!_itemStatusesInitialized && state.allocationItemStatuses.isNotEmpty) {
      _itemStatuses.addAll(state.allocationItemStatuses);
      _itemStatusesInitialized = true;
    }
  }

  List<AllocationResultRow> _filterResults(List<AllocationResultRow> rows) {
    final query = _allocationSearch.trim().toLowerCase();
    if (query.isEmpty) return rows;

    return rows.where((row) {
      return row.fromBranch.toLowerCase().contains(query) ||
          row.toBranch.toLowerCase().contains(query) ||
          row.itemCode.toLowerCase().contains(query) ||
          row.itemName.toLowerCase().contains(query);
    }).toList();
  }

  List<String> _pullStockCoverOptions(List<String> options) {
    return _sortedStockCoverOptions(options).where((option) {
      return !_isNoDemandStockCover(option) && _stockCoverDays(option) >= 30;
    }).toList();
  }

  List<String> _supplyStockCoverOptions(List<String> options) {
    return _sortedStockCoverOptions(options).where((option) {
      return !_isNoDemandStockCover(option) && _stockCoverDays(option) < 30;
    }).toList();
  }

  List<String> _sortedStockCoverOptions(List<String> options) {
    final sorted = options
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    sorted.sort(_compareStockCoverLabels);
    return sorted;
  }

  num _stockCoverDays(String label) {
    return _stockCoverDaysValue(label);
  }
}

bool _isNoDemandStockCover(String label) {
  return label.trim().toLowerCase() == 'no demand';
}

int _stockCoverGroup(String label) {
  final text = label.trim().toLowerCase();
  if (text.contains('no stock')) return 0;
  if (text.contains('less than')) return 1;
  if (text.contains('day')) return 2;
  if (text.contains('week')) return 3;
  if (text.contains('month')) return 4;
  if (text.contains('year')) return 5;
  return 9;
}

num _stockCoverUnitValue(String label) {
  final text = label.trim().toLowerCase();
  if (text.contains('no stock')) return 0;
  if (text.contains('less than')) return 0.5;
  return num.tryParse(
        RegExp(r'\d+(\.\d+)?').firstMatch(text)?.group(0) ?? '',
      ) ??
      0;
}

num _stockCoverDaysValue(String label) {
  final text = label.trim().toLowerCase();
  final value = _stockCoverUnitValue(label);

  if (text.contains('no stock')) return 0;
  if (text.contains('less than')) return value;
  if (text.contains('day')) return value;
  if (text.contains('week')) return value * 7;
  if (text.contains('month')) return value * 30;
  if (text.contains('year')) return value * 365;
  return value;
}

int _compareStockCoverLabels(String a, String b) {
  final groupCompare = _stockCoverGroup(a).compareTo(_stockCoverGroup(b));
  if (groupCompare != 0) return groupCompare;

  final valueCompare = _stockCoverUnitValue(
    a,
  ).compareTo(_stockCoverUnitValue(b));
  if (valueCompare != 0) return valueCompare;

  return a.toLowerCase().compareTo(b.toLowerCase());
}

class _AllocationSendDraft {
  final String title;
  final DateTime expiresAt;

  const _AllocationSendDraft({required this.title, required this.expiresAt});
}

String _fmtAllocationDeadline(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

class _Header extends StatelessWidget {
  final String runDate;
  final int resultsCount;
  final bool isLoading;
  final bool isSending;
  final int loadedRows;
  final VoidCallback onRun;
  final VoidCallback onImport;
  final VoidCallback? onSend;
  final VoidCallback? onExport;
  final VoidCallback? onShortageExport;

  const _Header({
    required this.runDate,
    required this.resultsCount,
    required this.isLoading,
    required this.isSending,
    required this.loadedRows,
    required this.onRun,
    required this.onImport,
    required this.onSend,
    required this.onExport,
    required this.onShortageExport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(34, 28, 34, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xff0EA5E9), Color(0xff2563EB)],
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
              color: Colors.white.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: .22)),
            ),
            child: const Icon(
              Icons.account_tree_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Allocation',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Move extra stock from high-extra branches to branches with shortage. Run date: $runDate',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .88),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _MetricPill(label: 'Result Rows', value: loadedRows.toString()),
          const SizedBox(width: 10),
          _MetricPill(label: 'Transfers', value: resultsCount.toString()),
          const SizedBox(width: 14),
          ElevatedButton.icon(
            onPressed: isLoading ? null : onImport,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Import'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xffF59E0B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: isLoading ? null : onRun,
            icon: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.play_arrow_rounded),
            label: Text(isLoading ? 'Running' : 'Run Allocation'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff0F766E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: isLoading || isSending ? null : onSend,
            icon: isSending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(isSending ? 'Sending' : 'Send'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xff14B8A6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: isLoading ? null : onExport,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Export'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xff1D4ED8),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: isLoading ? null : onShortageExport,
            icon: const Icon(Icons.report_problem_rounded),
            label: const Text('Allocation Shortage'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xffDC2626),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;

  const _MetricPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .22)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .78),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltersCard extends StatelessWidget {
  final List<Map<String, dynamic>> branches;
  final List<String> categories;
  final List<String> itemStatuses;
  final List<String> pullStockCoverOptions;
  final List<String> supplyStockCoverOptions;
  final Set<String> donorBranches;
  final Set<String> receiverBranches;
  final Set<String> priorityBranches;
  final Set<String> selectedCategories;
  final Set<String> selectedItemStatuses;
  final Set<String> donorStockCovers;
  final Set<String> receiverStockCovers;
  final int? minimumDemandFor30Days;
  final ValueChanged<int?> onDemandChanged;
  final VoidCallback onChanged;

  const _FiltersCard({
    required this.branches,
    required this.categories,
    required this.itemStatuses,
    required this.pullStockCoverOptions,
    required this.supplyStockCoverOptions,
    required this.donorBranches,
    required this.receiverBranches,
    required this.priorityBranches,
    required this.selectedCategories,
    required this.selectedItemStatuses,
    required this.donorStockCovers,
    required this.receiverStockCovers,
    required this.minimumDemandFor30Days,
    required this.onDemandChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Allocation Controls',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xff0F172A),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Leave any branch/category filter empty to include all.',
            style: TextStyle(color: Color(0xff64748B), fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _BranchSelectBox(
                  title: 'Pull From Branches',
                  subtitle: 'Branches that have extra stock',
                  icon: Icons.call_made_rounded,
                  color: const Color(0xff0EA5E9),
                  options: branches,
                  selected: donorBranches,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _BranchSelectBox(
                  title: 'Supply To Branches',
                  subtitle: 'Branches that need stock',
                  icon: Icons.call_received_rounded,
                  color: const Color(0xff22C55E),
                  options: branches,
                  selected: receiverBranches,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _BranchSelectBox(
                  title: 'Priority Branches',
                  subtitle: 'Receive stock before others',
                  icon: Icons.star_rounded,
                  color: const Color(0xffF59E0B),
                  options: branches,
                  selected: priorityBranches,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _SelectBox(
                  title: 'Categories',
                  subtitle: 'One or more product categories',
                  icon: Icons.category_rounded,
                  color: const Color(0xff8B5CF6),
                  options: categories,
                  selected: selectedCategories,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SelectBox(
                  title: 'Item Status',
                  subtitle: 'Filter by item_purchase_type',
                  icon: Icons.verified_rounded,
                  color: const Color(0xff14B8A6),
                  options: itemStatuses,
                  selected: selectedItemStatuses,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _SelectBox(
                  title: 'Pull Stock Cover',
                  subtitle: 'Only branches above one month',
                  icon: Icons.inventory_2_rounded,
                  color: const Color(0xff0EA5E9),
                  options: pullStockCoverOptions,
                  selected: donorStockCovers,
                  emptyLabel: 'Off',
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _SelectBox(
                  title: 'Supply Stock Cover',
                  subtitle: 'Only branches below one month',
                  icon: Icons.low_priority_rounded,
                  color: const Color(0xff22C55E),
                  options: supplyStockCoverOptions,
                  selected: receiverStockCovers,
                  emptyLabel: 'Off',
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _DemandFilterBox(
                  value: minimumDemandFor30Days,
                  onChanged: onDemandChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AllocationFiltersLoadingCard extends StatelessWidget {
  const _AllocationFiltersLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .05),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xff0EA5E9).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: Color(0xff0EA5E9),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Loading allocation filters',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xff0F172A),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Fetching branches, categories, and item status options...',
                      style: TextStyle(color: Color(0xff64748B), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: const [
              Expanded(child: _LoadingPill()),
              SizedBox(width: 14),
              Expanded(child: _LoadingPill()),
              SizedBox(width: 14),
              Expanded(child: _LoadingPill()),
              SizedBox(width: 14),
              Expanded(child: _LoadingPill()),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoadingPill extends StatelessWidget {
  const _LoadingPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xffF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xffE2E8F0),
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 10,
                  width: 110,
                  decoration: BoxDecoration(
                    color: const Color(0xffE2E8F0),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 8,
                  width: 150,
                  decoration: BoxDecoration(
                    color: const Color(0xffEEF2F7),
                    borderRadius: BorderRadius.circular(99),
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

class _DemandFilterBox extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;

  const _DemandFilterBox({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xffF97316);
    final label = value == null ? 'Off' : '>= $value';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final result = await showDialog<int>(
          context: context,
          builder: (_) => _DemandFilterDialog(initialValue: value),
        );
        if (result == null || result == -1) return;
        onChanged(result == 0 ? null : result);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: .22)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.trending_up_rounded, color: color),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Demand 30D',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xff0F172A),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Supply branches with demand above',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Color(0xff64748B)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemandFilterDialog extends StatelessWidget {
  final int? initialValue;

  const _DemandFilterDialog({required this.initialValue});

  @override
  Widget build(BuildContext context) {
    Widget option(String title, String subtitle, int value) {
      final selected = value == 0
          ? initialValue == null
          : initialValue == value;
      return ListTile(
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: const Color(0xffF97316),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        onTap: () => Navigator.pop(context, value),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xffF97316).withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.trending_up_rounded,
                      color: Color(0xffF97316),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Demand 30D Filter',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Optional receiver demand threshold',
                          style: TextStyle(color: Color(0xff64748B)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, -1),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              option('Off', 'Keep the default allocation behavior', 0),
              option('Demand 2+', 'Only supply branches with demand >= 2', 2),
              option('Demand 3+', 'Only supply branches with demand >= 3', 3),
              option('Demand 4+', 'Only supply branches with demand >= 4', 4),
              option('Demand 5+', 'Only supply branches with demand >= 5', 5),
            ],
          ),
        ),
      ),
    );
  }
}

class BranchFilter {
  final String? area;
  final String? branchType;

  const BranchFilter({this.area, this.branchType});
}

String _branchName(Map<String, dynamic> branch) {
  return (branch['branch_name'] ?? '').toString().trim();
}

String _branchArea(Map<String, dynamic> branch) {
  return (branch['area'] ?? '').toString().trim();
}

String _branchType(Map<String, dynamic> branch) {
  return (branch['branch_type'] ?? branch['brancy_type'] ?? '')
      .toString()
      .trim();
}

String _branchKey(String value) => value.trim().toLowerCase();

class _SelectBox extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<String> options;
  final Set<String> selected;
  final String? emptyLabel;
  final VoidCallback onChanged;

  const _SelectBox({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.options,
    required this.selected,
    this.emptyLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final label = selected.isEmpty
        ? emptyLabel ??
              (title == 'Priority Branches' ? 'No priority' : 'None selected')
        : selected.length == options.length
        ? 'All selected'
        : '${selected.length} selected';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final result = await showDialog<Set<String>>(
          context: context,
          builder: (_) => _MultiSelectDialog(
            title: title,
            options: options,
            initialSelected: selected,
            color: color,
          ),
        );

        if (result == null) return;
        selected
          ..clear()
          ..addAll(result);
        onChanged();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: .22)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(13),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xff0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xff64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _MultiSelectDialog extends StatefulWidget {
  final String title;
  final List<String> options;
  final Set<String> initialSelected;
  final Color color;

  const _MultiSelectDialog({
    required this.title,
    required this.options,
    required this.initialSelected,
    required this.color,
  });

  @override
  State<_MultiSelectDialog> createState() => _MultiSelectDialogState();
}

class _MultiSelectDialogState extends State<_MultiSelectDialog> {
  late final Set<String> _selected = {...widget.initialSelected};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final isStockCoverDialog = widget.title.toLowerCase().contains(
      'stock cover',
    );
    final sortedOptions = [...widget.options]
      ..sort((a, b) {
        if (isStockCoverDialog) return _compareStockCoverLabels(a, b);
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    final filtered = sortedOptions
        .where((e) => e.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: SizedBox(
        width: 520,
        height: 620,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: AppColors.secondaryColor,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selected
                          ..clear()
                          ..addAll(widget.options);
                      });
                    },
                    child: const Text(
                      'Select All',
                      style: TextStyle(
                        color: AppColors.secondaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Search branch, area, or type...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: const Color(0xffF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final item = filtered[index];
                  final checked = _selected.contains(item);

                  return CheckboxListTile(
                    value: checked,
                    activeColor: widget.color,
                    title: Text(
                      item,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onChanged: (_) {
                      setState(() {
                        checked ? _selected.remove(item) : _selected.add(item);
                      });
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Text('Apply (${_selected.length})'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchSelectBox extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<Map<String, dynamic>> options;
  final Set<String> selected;
  final VoidCallback onChanged;

  const _BranchSelectBox({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final label = selected.isEmpty
        ? title == 'Priority Branches'
              ? 'No priority'
              : 'None selected'
        : selected.length == options.length
        ? 'All selected'
        : '${selected.length} selected';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final result = await showDialog<Set<String>>(
          context: context,
          builder: (_) => _BranchMultiSelectDialog(
            title: title,
            options: options,
            initialSelected: selected,
            color: color,
          ),
        );

        if (result == null) return;

        selected
          ..clear()
          ..addAll(result);

        onChanged();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: .22)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(13),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xff0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xff64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _BranchMultiSelectDialog extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> options;
  final Set<String> initialSelected;
  final Color color;

  const _BranchMultiSelectDialog({
    required this.title,
    required this.options,
    required this.initialSelected,
    required this.color,
  });

  @override
  State<_BranchMultiSelectDialog> createState() =>
      _BranchMultiSelectDialogState();
}

class _BranchMultiSelectDialogState extends State<_BranchMultiSelectDialog> {
  late final Set<String> _selected = {...widget.initialSelected};

  String _query = '';

  @override
  Widget build(BuildContext context) {
    final sortedOptions = [...widget.options]
      ..sort((a, b) => _branchName(a).compareTo(_branchName(b)));
    final query = _branchKey(_query);
    final filtered = sortedOptions.where((branch) {
      if (query.isEmpty) return true;
      final searchable = [
        _branchName(branch),
        _branchArea(branch),
        _branchType(branch),
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
    final selectedPreview = _selected.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: SizedBox(
        width: 920.w,
        height: 1000.h,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 18, 16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.hub_rounded, color: widget.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Color(0xff0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_selected.length} selected from ${sortedOptions.length} branches',
                          style: const TextStyle(
                            color: Color(0xff64748B),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _TinyActionButton(
                    label: 'All',
                    onPressed: () {
                      setState(() {
                        _selected
                          ..clear()
                          ..addAll(
                            sortedOptions
                                .map(_branchName)
                                .where((e) => e.isNotEmpty),
                          );
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  _TinyActionButton(
                    label: 'Clear',
                    onPressed: () => setState(_selected.clear),
                    foreground: const Color(0xffEF4444),
                    background: const Color(0xffFEF2F2),
                    border: const Color(0xffFECACA),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        color: Color(0xff0EA5E9),
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Quick select by area and branch type',
                        style: TextStyle(
                          color: Color(0xff0F172A),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _GroupChip(
                        label: 'Online Branches',
                        color: const Color(0xff2563EB),
                        onPressed: () => _selectBranchGroup(type: 'Online'),
                      ),
                      _GroupChip(
                        label: 'Retail Branches',
                        color: const Color(0xff16A34A),
                        onPressed: () => _selectBranchGroup(type: 'Retail'),
                      ),
                      _GroupChip(
                        label: 'Al Ain Branches',
                        color: const Color(0xffF59E0B),
                        onPressed: () => _selectBranchGroup(area: 'Al Ain'),
                      ),
                      _GroupChip(
                        label: 'Abu Dhabi Branches',
                        color: const Color(0xffF59E0B),
                        onPressed: () => _selectBranchGroup(area: 'Abu Dhabi'),
                      ),
                      _GroupChip(
                        label: 'Dubai Branches',
                        color: const Color(0xffF59E0B),
                        onPressed: () => _selectBranchGroup(area: 'Dubai'),
                      ),
                      _GroupChip(
                        label: 'Online Abu Dhabi',
                        color: const Color(0xff7C3AED),
                        onPressed: () => _selectBranchGroup(
                          type: 'Online',
                          area: 'Abu Dhabi',
                        ),
                      ),
                      _GroupChip(
                        label: 'Online Al Ain',
                        color: const Color(0xff7C3AED),
                        onPressed: () =>
                            _selectBranchGroup(type: 'Online', area: 'Al Ain'),
                      ),
                      _GroupChip(
                        label: 'Retail Abu Dhabi',
                        color: const Color(0xff0F766E),
                        onPressed: () => _selectBranchGroup(
                          type: 'Retail',
                          area: 'Abu Dhabi',
                        ),
                      ),
                      _GroupChip(
                        label: 'Retail Dubai',
                        color: const Color(0xff0F766E),
                        onPressed: () =>
                            _selectBranchGroup(type: 'Retail', area: 'Dubai'),
                      ),
                      _GroupChip(
                        label: 'All Branches',
                        color: const Color(0xff0EA5E9),
                        onPressed: () {
                          setState(() {
                            _selected
                              ..clear()
                              ..addAll(
                                widget.options
                                    .map(_branchName)
                                    .where((e) => e.isNotEmpty),
                              );
                          });
                        },
                      ),
                    ],
                  ),
                  if (_selected.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _SelectedBranchesPreview(
                      selected: selectedPreview,
                      color: widget.color,
                      onRemove: (branch) {
                        setState(() {
                          _selected.remove(branch);
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                onChanged: (value) {
                  setState(() {
                    _query = value;
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search branch, area, or type...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: const Color(0xffF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final branch = filtered[index];

                  final name = _branchName(branch);

                  final area = _branchArea(branch);

                  final type = _branchType(branch);

                  final checked = _selected.contains(name);

                  return CheckboxListTile(
                    value: checked,
                    activeColor: widget.color,
                    title: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      [
                        if (area.isNotEmpty) area,
                        if (type.isNotEmpty) type,
                      ].join(' - '),
                    ),
                    onChanged: (_) {
                      setState(() {
                        checked ? _selected.remove(name) : _selected.add(name);
                      });
                    },
                  );
                },
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(18),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Text('Apply (${_selected.length})'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectBranchGroup({String? area, String? type}) {
    final selected = widget.options
        .where((branch) {
          final areaOk =
              area == null ||
              _branchKey(_branchArea(branch)).contains(_branchKey(area));
          final typeOk =
              type == null ||
              _branchKey(_branchType(branch)).contains(_branchKey(type));
          return areaOk && typeOk;
        })
        .map(_branchName)
        .where((e) => e.isNotEmpty);

    setState(() => _selected.addAll(selected));
  }
}

class _SelectedBranchesPreview extends StatelessWidget {
  final List<String> selected;
  final Color color;
  final ValueChanged<String> onRemove;

  const _SelectedBranchesPreview({
    required this.selected,
    required this.color,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final visible = selected.take(12).toList();
    final remaining = selected.length - visible.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.done_all_rounded, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                'Selected branches (${selected.length})',
                style: const TextStyle(
                  color: Color(0xff0F172A),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...visible.map(
                (branch) => InputChip(
                  label: Text(branch),
                  onDeleted: () => onRemove(branch),
                  deleteIcon: const Icon(Icons.close_rounded, size: 16),
                  labelStyle: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: color.withValues(alpha: .25)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (remaining > 0)
                Chip(
                  label: Text('+$remaining more'),
                  labelStyle: const TextStyle(
                    color: Color(0xff64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                  backgroundColor: const Color(0xffF8FAFC),
                  side: const BorderSide(color: Color(0xffE2E8F0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TinyActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color foreground;
  final Color background;
  final Color border;

  const _TinyActionButton({
    required this.label,
    required this.onPressed,
    this.foreground = const Color(0xff2563EB),
    this.background = const Color(0xffEFF6FF),
    this.border = const Color(0xffBFDBFE),
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor: background,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}

class _GroupChip extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _GroupChip({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      avatar: Icon(Icons.checklist_rounded, size: 18, color: color),
      onPressed: onPressed,
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w900),
      backgroundColor: color.withValues(alpha: .08),
      side: BorderSide(color: color.withValues(alpha: .24)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  final List<AllocationResultRow> results;

  const _SummaryStrip({required this.results});

  @override
  Widget build(BuildContext context) {
    final totalQty = results.fold<num>(0, (sum, row) => sum + row.qty);
    final fromBranches = results.map((e) => e.fromBranch).toSet().length;
    final toBranches = results.map((e) => e.toBranch).toSet().length;

    return Row(
      children: [
        _SummaryCard(
          label: 'Transfers',
          value: results.length.toString(),
          icon: Icons.swap_horiz_rounded,
          color: const Color(0xff2563EB),
        ),
        const SizedBox(width: 14),
        _SummaryCard(
          label: 'Total Qty',
          value: _formatQty(totalQty),
          icon: Icons.inventory_2_rounded,
          color: const Color(0xff16A34A),
        ),
        const SizedBox(width: 14),
        _SummaryCard(
          label: 'From Branches',
          value: fromBranches.toString(),
          icon: Icons.call_made_rounded,
          color: const Color(0xff0EA5E9),
        ),
        const SizedBox(width: 14),
        _SummaryCard(
          label: 'To Branches',
          value: toBranches.toString(),
          icon: Icons.call_received_rounded,
          color: const Color(0xffF59E0B),
        ),
      ],
    );
  }
}

class _AllocationSearchBar extends StatelessWidget {
  final String value;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _AllocationSearchBar({
    required this.value,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffD7E7F7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'Search allocation by branch, item code, or item name...',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: value.trim().isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xffE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xff0F172A),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SentAllocationStatusCard extends StatelessWidget {
  final List<BranchAllocationTask> rows;
  final TextEditingController searchController;
  final String query;
  final String statusFilter;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onStatusChanged;

  const _SentAllocationStatusCard({
    required this.rows,
    required this.searchController,
    required this.query,
    required this.statusFilter,
    required this.onQueryChanged,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final byBranch = <String, List<BranchAllocationTask>>{};
    for (final row in rows) {
      byBranch.putIfAbsent(row.fromBranch, () => []).add(row);
    }

    final pendingBranches = byBranch.entries
        .where((entry) => entry.value.any((task) => task.isSenderPending))
        .length;
    final confirmedBranches = byBranch.entries
        .where(
          (entry) =>
              entry.value.isNotEmpty &&
              entry.value.every((task) => task.isBatchFinished),
        )
        .length;
    final pendingItems = rows.where((task) => task.isSenderPending).length;
    final filteredRows = _filteredRows(rows);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffD7E2F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xffE0F2FE),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.send_and_archive_rounded,
                  color: Color(0xff0284C7),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sent Allocation Follow-up',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xff0F172A),
                      ),
                    ),
                    Text(
                      'Track which branches confirmed their outgoing allocation.',
                      style: TextStyle(
                        color: Color(0xff64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusMiniCard(
                label: 'Branches',
                value: byBranch.length.toString(),
                color: const Color(0xff0284C7),
              ),
              const SizedBox(width: 8),
              _StatusMiniCard(
                label: 'Confirmed',
                value: confirmedBranches.toString(),
                color: const Color(0xff059669),
              ),
              const SizedBox(width: 8),
              _StatusMiniCard(
                label: 'Pending',
                value: '$pendingBranches / $pendingItems items',
                color: const Color(0xffD97706),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 430,
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    labelColor: Color(0xff0284C7),
                    unselectedLabelColor: Color(0xff64748B),
                    indicatorColor: Color(0xff0284C7),
                    labelStyle: TextStyle(fontWeight: FontWeight.w900),
                    tabs: [
                      Tab(text: 'Branch Progress'),
                      Tab(text: 'Allocation Details'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _BranchProgressList(byBranch: byBranch),
                        Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 44,
                                    child: TextField(
                                      controller: searchController,
                                      onChanged: onQueryChanged,
                                      decoration: InputDecoration(
                                        hintText:
                                            'Search branch, item code, item name, or note...',
                                        prefixIcon: const Icon(
                                          Icons.search_rounded,
                                        ),
                                        filled: true,
                                        fillColor: const Color(0xffF8FAFC),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xffD7E2F0),
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          borderSide: const BorderSide(
                                            color: Color(0xffD7E2F0),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _StatusFilterButton(
                                  label: 'All',
                                  value: 'all',
                                  current: statusFilter,
                                  onChanged: onStatusChanged,
                                ),
                                _StatusFilterButton(
                                  label: 'Not Done',
                                  value: 'pending',
                                  current: statusFilter,
                                  onChanged: onStatusChanged,
                                ),
                                _StatusFilterButton(
                                  label: 'Confirmed',
                                  value: 'confirmed',
                                  current: statusFilter,
                                  onChanged: onStatusChanged,
                                ),
                                _StatusFilterButton(
                                  label: 'No Send',
                                  value: 'no_send',
                                  current: statusFilter,
                                  onChanged: onStatusChanged,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: _AllocationDetailsTable(
                                rows: filteredRows,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<BranchAllocationTask> _filteredRows(List<BranchAllocationTask> source) {
    final q = query.trim().toLowerCase();
    return source.where((row) {
      final matchesSearch =
          q.isEmpty ||
          row.fromBranch.toLowerCase().contains(q) ||
          row.toBranch.toLowerCase().contains(q) ||
          row.itemCode.toLowerCase().contains(q) ||
          row.itemName.toLowerCase().contains(q) ||
          row.senderNote.toLowerCase().contains(q);

      final matchesStatus = switch (statusFilter) {
        'pending' => row.isSenderPending,
        'confirmed' => row.isSenderConfirmed,
        'no_send' => row.isNoSend,
        _ => true,
      };

      return matchesSearch && matchesStatus;
    }).toList();
  }
}

class _BranchProgressList extends StatelessWidget {
  final Map<String, List<BranchAllocationTask>> byBranch;

  const _BranchProgressList({required this.byBranch});

  @override
  Widget build(BuildContext context) {
    if (byBranch.isEmpty) {
      return const Center(child: Text('No sent allocation yet.'));
    }

    final entries = byBranch.entries.toList()
      ..sort((a, b) {
        final ap = a.value.where((task) => task.isSenderPending).length;
        final bp = b.value.where((task) => task.isSenderPending).length;
        if (ap != bp) return bp.compareTo(ap);
        return a.key.compareTo(b.key);
      });

    return GridView.builder(
      itemCount: entries.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 360,
        mainAxisExtent: 118,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final pending = entry.value
            .where((task) => task.isSenderPending)
            .length;
        final confirmed = entry.value
            .where((task) => task.isSenderConfirmed)
            .length;
        final noSend = entry.value.where((task) => task.isNoSend).length;
        final total = entry.value.length;
        final done = confirmed + noSend;
        final ready = pending == 0;
        final finished =
            entry.value.isNotEmpty &&
            entry.value.every((task) => task.isBatchFinished);

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: finished
                ? const Color(0xffECFDF5)
                : ready
                ? const Color(0xffEFF6FF)
                : const Color(0xffFFFBEB),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: finished
                  ? const Color(0xffA7F3D0)
                  : ready
                  ? const Color(0xffBFDBFE)
                  : const Color(0xffFDE68A),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    finished
                        ? Icons.check_circle_rounded
                        : ready
                        ? Icons.rule_rounded
                        : Icons.pending_actions_rounded,
                    color: finished
                        ? const Color(0xff059669)
                        : ready
                        ? const Color(0xff2563EB)
                        : const Color(0xffD97706),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.key,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff0F172A),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : done / total,
                  minHeight: 8,
                  backgroundColor: Colors.white,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    finished
                        ? const Color(0xff059669)
                        : ready
                        ? const Color(0xff2563EB)
                        : const Color(0xffF59E0B),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Done $done/$total  -  Confirmed $confirmed  -  No Send $noSend',
                style: const TextStyle(
                  color: Color(0xff475569),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AllocationDetailsTable extends StatelessWidget {
  final List<BranchAllocationTask> rows;

  const _AllocationDetailsTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(child: Text('No rows match the selected filters.'));
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffD7E2F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xffEFF6FF)),
          columnSpacing: 24,
          columns: const [
            DataColumn(label: Text('From Branch')),
            DataColumn(label: Text('To Branch')),
            DataColumn(label: Text('Item')),
            DataColumn(label: Text('Qty')),
            DataColumn(label: Text('Qty Send')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Note')),
          ],
          rows: rows.map((row) {
            return DataRow(
              cells: [
                DataCell(Text(row.fromBranch)),
                DataCell(Text(row.toBranch)),
                DataCell(Text('${row.itemCode}\n${row.itemName}')),
                DataCell(Text(row.qty.toString())),
                DataCell(Text(row.qtySend.toString())),
                DataCell(_SentStatusPill(row: row)),
                DataCell(
                  SizedBox(
                    width: 260,
                    child: Text(
                      row.senderNote,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _SentStatusPill extends StatelessWidget {
  final BranchAllocationTask row;

  const _SentStatusPill({required this.row});

  @override
  Widget build(BuildContext context) {
    final text = row.isNoSend
        ? 'No Send'
        : row.isSenderConfirmed
        ? 'Confirmed'
        : 'Pending';
    final color = row.isNoSend
        ? const Color(0xffDC2626)
        : row.isSenderConfirmed
        ? const Color(0xff059669)
        : const Color(0xffD97706);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _StatusFilterButton extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final ValueChanged<String> onChanged;

  const _StatusFilterButton({
    required this.label,
    required this.value,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: ChoiceChip(
        selected: selected,
        label: Text(label),
        selectedColor: const Color(0xffDBEAFE),
        labelStyle: TextStyle(
          color: selected ? const Color(0xff1D4ED8) : const Color(0xff64748B),
          fontWeight: FontWeight.w900,
        ),
        onSelected: (_) => onChanged(value),
      ),
    );
  }
}

class _StatusMiniCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatusMiniCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultsTable extends StatelessWidget {
  final List<AllocationResultRow> rows;
  final int totalRows;
  final String searchValue;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  const _ResultsTable({
    required this.rows,
    required this.totalRows,
    required this.searchValue,
    required this.searchController,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffE2E8F0)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const Icon(
                  Icons.table_chart_rounded,
                  color: AppColors.primaryColor,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Allocation Result',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                Text(
                  totalRows == rows.length
                      ? '${rows.length} rows'
                      : '${rows.length} of $totalRows rows',
                  style: const TextStyle(
                    color: Color(0xff64748B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
            child: _AllocationSearchBar(
              value: searchValue,
              controller: searchController,
              onChanged: onSearchChanged,
            ),
          ),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(46),
              child: Text(
                'No allocation calculated yet. Select filters and press Run Allocation.',
                style: TextStyle(color: Color(0xff64748B)),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tableWidth = constraints.maxWidth < 1180
                      ? 1180.0
                      : constraints.maxWidth;
                  final usableWidth = tableWidth - 180;
                  final fromBranchWidth = usableWidth * 0.18;
                  final itemCodeWidth = usableWidth * 0.14;
                  final itemNameWidth = usableWidth * 0.40;
                  final qtyWidth = usableWidth * 0.08;
                  final toBranchWidth = usableWidth * 0.20;

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth,
                      child: DataTable(
                        border: TableBorder.all(
                          color: const Color(0xffD8E2EF),
                          width: 1,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        headingRowColor: WidgetStateProperty.all(
                          const Color(0xffEAF3FF),
                        ),
                        dataRowColor: WidgetStateProperty.resolveWith((states) {
                          return null;
                        }),
                        headingTextStyle: const TextStyle(
                          color: Color(0xff0F2F55),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                        dataTextStyle: const TextStyle(
                          color: Color(0xff1F2937),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        headingRowHeight: 48,
                        dataRowMinHeight: 44,
                        dataRowMaxHeight: 58,
                        columnSpacing: 32,
                        horizontalMargin: 18,
                        columns: const [
                          DataColumn(label: Text('From Branch')),
                          DataColumn(label: Text('Item Code')),
                          DataColumn(label: Text('Item Name')),
                          DataColumn(label: Text('QTY')),
                          DataColumn(label: Text('To Branch')),
                        ],
                        rows: rows.take(600).map((row) {
                          return DataRow(
                            cells: [
                              DataCell(
                                SizedBox(
                                  width: fromBranchWidth,
                                  child: Text(row.fromBranch),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: itemCodeWidth,
                                  child: Text(row.itemCode),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: itemNameWidth,
                                  child: Text(
                                    row.itemName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: qtyWidth,
                                  child: Text(
                                    _formatQty(row.qty),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: toBranchWidth,
                                  child: Text(row.toBranch),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (rows.length > 600)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                totalRows == rows.length
                    ? 'Showing first 600 rows. Export includes all ${rows.length} rows.'
                    : 'Showing first 600 filtered rows from ${rows.length} matches. Export includes all $totalRows rows.',
                style: const TextStyle(color: Color(0xff64748B)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  final String message;

  const _SuccessBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xffECFDF5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xff86EFAC)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            color: Color(0xff16A34A),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xff166534),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatQty(num value) {
  if (value % 1 == 0) return value.toInt().toString();
  return value.toStringAsFixed(2);
}
