import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/mismatch_item.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';

class MismatchPage extends StatefulWidget {
  const MismatchPage({super.key});

  @override
  State<MismatchPage> createState() => _MismatchPageState();
}

class _MismatchPageState extends State<MismatchPage> {
  bool _isInitialLoading = true;
  Timer? _initialLoadFallback;

  @override
  void initState() {
    super.initState();
    final bloc = context.read<InventoryBloc>();
    bloc.add(StartMismatchRealtime());
    bloc.add(LoadMismatch());
    _initialLoadFallback = Timer(const Duration(seconds: 12), () {
      if (mounted && _isInitialLoading) {
        setState(() => _isInitialLoading = false);
      }
    });
  }

  @override
  void dispose() {
    _initialLoadFallback?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<InventoryBloc, InventoryState>(
      listenWhen: (previous, current) =>
          previous.filteredMismatch != current.filteredMismatch ||
          previous.mismatchTodayCount != current.mismatchTodayCount ||
          previous.mismatchMonthCount != current.mismatchMonthCount ||
          previous.mismatchTotalCount != current.mismatchTotalCount,
      listener: (_, _) {
        if (_isInitialLoading && mounted) {
          _initialLoadFallback?.cancel();
          setState(() => _isInitialLoading = false);
        }
      },
      child: BlocBuilder<InventoryBloc, InventoryState>(
        buildWhen: (previous, current) {
          return previous.filteredMismatch != current.filteredMismatch ||
              previous.mismatchColumnWidths != current.mismatchColumnWidths ||
              previous.mismatchTodayCount != current.mismatchTodayCount ||
              previous.mismatchMonthCount != current.mismatchMonthCount ||
              previous.mismatchTotalCount != current.mismatchTotalCount ||
              previous.mismatchDiffSum != current.mismatchDiffSum ||
              previous.mismatchBranch != current.mismatchBranch ||
              previous.branches != current.branches ||
              previous.isExporting != current.isExporting ||
              previous.exportMessage != current.exportMessage ||
              previous.isLoading != current.isLoading;
        },
        builder: (context, state) {
          final rows = state.filteredMismatch;
          final widths = state.mismatchColumnWidths;

          return Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Column(
                  children: [
                    _header(state),
                    const SizedBox(height: 14),
                    _cards(state),
                    const SizedBox(height: 14),
                    _filters(context, state),
                    const SizedBox(height: 14),

                    /// 🔥 TABLE
                    Expanded(
                      child: _isInitialLoading
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    color: AppColors.primaryColor,
                                  ),
                                  SizedBox(height: 10),
                                  Text('Loading mismatch report...'),
                                ],
                              ),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                color: AppColors.card,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFF0C9D1),
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: SfDataGridTheme(
                                  data: SfDataGridThemeData(
                                    headerColor: const Color(0xFFFFE8EC),
                                    gridLineColor: AppColors.border,
                                    rowHoverColor: const Color(0xFFFFF5F7),
                                    selectionColor: const Color(0x14BE123C),
                                    filterPopupBackgroundColor: const Color(
                                      0xFFFFF7F8,
                                    ),
                                    filterPopupIconColor: const Color(
                                      0xFFBE123C,
                                    ),
                                    filterPopupCheckColor: Colors.white,
                                    filterPopupCheckboxFillColor:
                                        const WidgetStatePropertyAll(
                                          Color(0xFFBE123C),
                                        ),
                                    filterPopupInputBorderColor: const Color(
                                      0xFFBE123C,
                                    ),
                                    okFilteringLabelColor: Colors.white,
                                    okFilteringLabelButtonColor: const Color(
                                      0xFFBE123C,
                                    ),
                                    cancelFilteringLabelColor: const Color(
                                      0xFF881337,
                                    ),
                                    cancelFilteringLabelButtonColor:
                                        Colors.transparent,
                                    searchAreaFocusedBorderColor: const Color(
                                      0xFFBE123C,
                                    ),
                                  ),
                                  child: SfDataGrid(
                                    source: _MismatchDataSource(rows, context),

                                    allowFiltering: true,
                                    allowColumnsResizing: true,
                                    allowSorting: true,

                                    columnWidthMode: ColumnWidthMode.none,

                                    gridLinesVisibility:
                                        GridLinesVisibility.both,
                                    headerGridLinesVisibility:
                                        GridLinesVisibility.both,

                                    rowHeight: 55,
                                    headerRowHeight: 60,

                                    onColumnResizeUpdate: (details) {
                                      context.read<InventoryBloc>().add(
                                        UpdateMismatchColumnWidth(
                                          details.column.columnName,
                                          details.width,
                                        ),
                                      );
                                      return true;
                                    },

                                    columns: [
                                      _col("index", "#", widths),
                                      _col("branch", "Branch", widths),
                                      _col("code", "Item Code", widths),
                                      _col("name", "Item Name", widths),
                                      _col("system", "System", widths),
                                      _col("actual", "Actual", widths),
                                      _col("diff", "Diff", widths),
                                      _col("history", "History", widths),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),

              /// ================= LOADING =================
              if (state.isExporting)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 25,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 250.w,
                              child: Column(
                                children: [
                                  LinearProgressIndicator(
                                    value: _extractProgress(
                                      state.exportMessage,
                                    ),
                                    color: AppColors.primaryColor,
                                    backgroundColor: AppColors.backgroundWidget,
                                    minHeight: 6,
                                  ),
                                  const SizedBox(height: 12),

                                  Text(
                                    state.exportMessage ?? "Exporting...",
                                    style: const TextStyle(fontSize: 14),
                                    textAlign: TextAlign.center,
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
            ],
          );
        },
      ),
    );
  }

  double _extractProgress(String? msg) {
    if (msg == null) return 0;

    final regex = RegExp(r'(\d+)%');
    final match = regex.firstMatch(msg);

    if (match == null) return 0;

    final value = double.tryParse(match.group(1)!) ?? 0;
    return value / 100;
  }

  Widget _header(InventoryState state) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB91C1C), Color(0xFFE11D48), Color(0xFFFB7185)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x55FFFFFF)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .92),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.warning_amber_outlined,
              color: Color(0xFFBE123C),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mismatch Report',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Review system and branch count differences, then follow their update history.',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
          _MismatchMetric(
            label: 'Visible',
            value: '${state.filteredMismatch.length}',
          ),
          const SizedBox(width: 8),
          _MismatchMetric(label: 'Total', value: '${state.mismatchTotalCount}'),
        ],
      ),
    );
  }

  /// ================= CARDS =================
  Widget _cards(InventoryState state) {
    return Row(
      children: [
        _card(
          'Today',
          state.mismatchTodayCount,
          Icons.today_outlined,
          const Color(0xFFBE123C),
        ),
        const SizedBox(width: 12),
        _card(
          'This month',
          state.mismatchMonthCount,
          Icons.calendar_month_outlined,
          const Color(0xFFE11D48),
        ),
        const SizedBox(width: 12),
        _card(
          'Active records',
          state.mismatchTotalCount,
          Icons.inventory_2_outlined,
          const Color(0xFF9F1239),
        ),
        const SizedBox(width: 12),
        _card(
          'Difference sum',
          state.mismatchDiffSum,
          Icons.difference_outlined,
          const Color(0xFF881337),
        ),
      ],
    );
  }

  Widget _card(String title, num value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .28)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(11),
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
                      color: AppColors.subText,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _displayNumber(value),
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ================= FILTER =================
  Widget _filters(BuildContext context, InventoryState state) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            onChanged: (v) {
              context.read<InventoryBloc>().add(SearchMismatch(v));
            },
            decoration: InputDecoration(
              hintText: 'Search branch, item code, or item name',

              prefixIcon: const Icon(Icons.search),
              filled: true,

              fillColor: const Color(0xFFFFF7F8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFFB7185)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFFB7185)),
              ),

              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFFBE123C),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFBE123C),
          ),
          onPressed: () {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text("Export"),
                content: const Text("Choose export type"),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      context.read<InventoryBloc>().add(
                        ExportMismatchCurrent(),
                      );
                    },
                    child: const Text("Current"),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      context.read<InventoryBloc>().add(
                        ExportMismatchWithHistory(),
                      );
                    },
                    child: const Text("With History"),
                  ),
                ],
              ),
            );
          },
          icon: const Icon(Icons.download, color: Colors.white),
          label: const Text("Export", style: TextStyle(color: Colors.white)),
        ),

        /* const SizedBox(width: 10),

        /// 🔥 TRACKER BUTTON
        Stack(
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.track_changes, color: Colors.white),
              label: const Text(
                "Tracker",
                style: TextStyle(color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => BlocProvider.value(
                    value: context.read<InventoryBloc>(),
                    child: const MismatchTrackerDialog(),
                  ),
                );
              },
            ),

            if (state.mismatchTodayCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    state.mismatchTodayCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),*/
        const SizedBox(width: 10),

        /// 🔥 BRANCH FILTER
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            initialValue: state.mismatchBranch,
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down),

            decoration: InputDecoration(
              hintText: "Select Branch",

              filled: true,
              fillColor: const Color(0xFFFFF7F8),

              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),

              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFFB7185)),
              ),

              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFFB7185)),
              ),

              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: const Color(0xFFBE123C),
                  width: 1.5,
                ),
              ),
            ),

            items: ["ALL", ...state.branches].map((e) {
              return DropdownMenuItem(
                value: e,
                child: Text(e, overflow: TextOverflow.ellipsis),
              );
            }).toList(),
            onChanged: (v) {
              context.read<InventoryBloc>().add(FilterMismatchBranch(v!));
              context.read<InventoryBloc>().add(LoadMismatchStats(v));
            },
          ),
        ),
      ],
    );
  }

  GridColumn _col(String name, String title, Map<String, double> widths) {
    return GridColumn(
      columnName: name,
      allowFiltering: name != "history",
      width: name == 'index' ? 80 : (widths[name] ?? 140),
      minimumWidth: 100,
      label: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF881337),
          ),
        ),
      ),
    );
  }
}

class _MismatchMetric extends StatelessWidget {
  const _MismatchMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 82),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: .26)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

String _displayNumber(num value) {
  final rounded = value.roundToDouble();
  if (value == rounded) return rounded.toInt().toString();
  return value.toStringAsFixed(2);
}

class _MismatchDataSource extends DataGridSource {
  final List<MismatchItem> data;
  final BuildContext context;
  late final List<DataGridRow> _rows;

  _MismatchDataSource(this.data, this.context) {
    _rows = List.generate(data.length, (index) {
      final e = data[index];

      return DataGridRow(
        cells: [
          DataGridCell(columnName: 'index', value: index + 1),
          DataGridCell(columnName: 'branch', value: e.branchName),
          DataGridCell(columnName: 'code', value: e.itemCode),
          DataGridCell(columnName: 'name', value: e.itemName),
          DataGridCell(columnName: 'system', value: e.systemStock),
          DataGridCell(columnName: 'actual', value: e.actualStock),
          DataGridCell(columnName: 'diff', value: e.diff),
          DataGridCell(columnName: 'history', value: e),
        ],
      );
    });
  }

  @override
  List<DataGridRow> get rows => _rows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final rowNo = int.tryParse(row.getCells().first.value.toString()) ?? 1;

    return DataGridRowAdapter(
      color: rowNo.isOdd ? Colors.white : const Color(0xFFFFFBFC),
      cells: row.getCells().map((c) {
        /// 🔥 DIFF STYLE
        if (c.columnName == 'diff') {
          final val = num.tryParse(c.value.toString()) ?? 0;

          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: val < 0
                  ? Colors.red.withValues(alpha: .08)
                  : Colors.green.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              c.value.toString(),
              style: TextStyle(
                color: val < 0
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF16A34A),
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }

        /// 🔥 HISTORY BUTTON
        if (c.columnName == 'history') {
          final item = c.value as MismatchItem;

          if (!item.hasHistory) {
            return const SizedBox();
          }

          return OutlinedButton.icon(
            icon: const Icon(
              Icons.visibility_rounded,
              size: 16,
              color: AppColors.secondaryColor,
            ),
            label: const Text(
              "View",
              style: TextStyle(color: AppColors.secondaryColor),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFFF8FBFF),
              side: BorderSide(
                color: AppColors.secondaryColor.withValues(alpha: .35),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              final ctx = context;

              final raw = await context
                  .read<InventoryBloc>()
                  .repo
                  .fetchMismatchHistory(item.branchName, item.itemCode);
              final res = raw.where((e) {
                final action = (e['action'] ?? '').toString().toLowerCase();
                return action == 'update' || action == 'delete';
              }).toList();

              if (!ctx.mounted) return;

              showDialog(
                context: ctx,
                builder: (_) => _MismatchHistoryDialog(item: item, logs: res),
              );
            },
          );
        }

        return Container(
          alignment: c.columnName == 'name'
              ? Alignment.centerLeft
              : Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: SelectableText(
            c.value.toString(),
            textAlign: c.columnName == 'name'
                ? TextAlign.left
                : TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.text),
          ),
        );
      }).toList(),
    );
  }
}

class _MismatchHistoryDialog extends StatelessWidget {
  final MismatchItem item;
  final List<Map<String, dynamic>> logs;

  const _MismatchHistoryDialog({required this.item, required this.logs});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      child: Container(
        width: 780,
        constraints: const BoxConstraints(maxHeight: 720),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .16),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 14, 18),
              decoration: const BoxDecoration(
                color: Color(0xFFF4FAFF),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withValues(alpha: .14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.manage_history_rounded,
                      color: AppColors.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.itemName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF102033),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.branchName} • ${item.itemCode}',
                          style: const TextStyle(
                            color: Color(0xFF6B7A90),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: logs.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(36),
                      child: Text('No update/delete history found'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(20),
                      itemCount: logs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        final action = (log['action'] ?? '')
                            .toString()
                            .toLowerCase();
                        return _HistoryLogCard(log: log, action: action);
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Done'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryLogCard extends StatelessWidget {
  final Map<String, dynamic> log;
  final String action;

  const _HistoryLogCard({required this.log, required this.action});

  @override
  Widget build(BuildContext context) {
    final isDelete = action == 'delete';
    final color = isDelete ? const Color(0xFFFF4D57) : AppColors.primaryColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDelete ? const Color(0xFFFFF6F6) : const Color(0xFFF7FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  action.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _formatDate(log['changed_at']),
                style: const TextStyle(
                  color: Color(0xFF728198),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (isDelete)
            Row(
              children: [
                Expanded(
                  child: _ValueBox(
                    label: 'Old System',
                    value: log['old_system_stock'],
                    color: const Color(0xFFFF4D57),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ValueBox(
                    label: 'Old Actual',
                    value: log['old_actual_stock'],
                    color: const Color(0xFFFF4D57),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ValueBox(
                    label: 'Old Diff',
                    value: log['old_diff'],
                    color: const Color(0xFFFF4D57),
                  ),
                ),
              ],
            )
          else ...[
            _CompareLine(
              title: 'System Stock',
              oldValue: log['old_system_stock'],
              newValue: log['new_system_stock'],
            ),
            const SizedBox(height: 10),
            _CompareLine(
              title: 'Actual Stock',
              oldValue: log['old_actual_stock'],
              newValue: log['new_actual_stock'],
            ),
            const SizedBox(height: 10),
            _CompareLine(
              title: 'Diff',
              oldValue: log['old_diff'],
              newValue: log['new_diff'],
            ),
          ],
          if ((log['note'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5EAF2)),
              ),
              child: Text(
                'Note: ${log['note']}',
                style: const TextStyle(color: Color(0xFF46556A)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompareLine extends StatelessWidget {
  final String title;
  final dynamic oldValue;
  final dynamic newValue;

  const _CompareLine({
    required this.title,
    required this.oldValue,
    required this.newValue,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF334155),
            ),
          ),
        ),
        Expanded(
          child: _ValueBox(
            label: 'Old',
            value: oldValue,
            color: const Color(0xFFFF4D57),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Icon(Icons.arrow_forward_rounded, color: Color(0xFF8AA0B8)),
        ),
        Expanded(
          child: _ValueBox(
            label: 'New',
            value: newValue,
            color: const Color(0xFF24A148),
          ),
        ),
      ],
    );
  }
}

class _ValueBox extends StatelessWidget {
  final String label;
  final dynamic value;
  final Color color;

  const _ValueBox({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .18)),
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
          const SizedBox(height: 4),
          Text(
            (value ?? '-').toString(),
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(dynamic value) {
  final parsed = DateTime.tryParse((value ?? '').toString());
  if (parsed == null) return (value ?? '').toString();
  final y = parsed.year.toString().padLeft(4, '0');
  final m = parsed.month.toString().padLeft(2, '0');
  final d = parsed.day.toString().padLeft(2, '0');
  final hh = parsed.hour.toString().padLeft(2, '0');
  final mm = parsed.minute.toString().padLeft(2, '0');
  return '$y-$m-$d  $hh:$mm';
}
