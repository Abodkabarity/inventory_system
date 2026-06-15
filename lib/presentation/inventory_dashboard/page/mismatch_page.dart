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
import '../widgets/mismatch_tracker_dialog.dart';

class MismatchPage extends StatelessWidget {
  const MismatchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, state) {
        final rows = state.filteredMismatch;
        final widths = state.mismatchColumnWidths;

        return Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _cards(state),
                  const SizedBox(height: 16),
                  _filters(context, state),
                  const SizedBox(height: 16),

                  /// 🔥 TABLE
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SfDataGridTheme(
                        data: SfDataGridThemeData(
                          headerColor: AppColors.backgroundWidget,
                          gridLineColor: Colors.grey.shade300,
                          selectionColor: Colors.blue.withValues(alpha: .08),
                        ),
                        child: SfDataGrid(
                          source: _MismatchDataSource(rows, context),

                          allowFiltering: true,
                          allowColumnsResizing: true,
                          allowSorting: true,

                          columnWidthMode: ColumnWidthMode.none,

                          gridLinesVisibility: GridLinesVisibility.both,
                          headerGridLinesVisibility: GridLinesVisibility.both,

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
                                  value: _extractProgress(state.exportMessage),
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

  /// ================= CARDS =================
  Widget _cards(InventoryState state) {
    return Row(
      children: [
        _card("Today", state.mismatchTodayCount),
        _card("Month", state.mismatchMonthCount),
        _card("Total", state.mismatchTotalCount),
        _card("Diff Sum", state.mismatchDiffSum),
      ],
    );
  }

  Widget _card(String title, num value) {
    return Expanded(
      child: Card(
        color: Colors.white,
        elevation: 5,
        shadowColor: AppColors.primaryColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Text(title, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 6),
              Text(
                value.toString(),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
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
              hintText: "Search item...",

              prefixIcon: const Icon(Icons.search),
              filled: true,

              fillColor: AppColors.backgroundWidget,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primaryColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primaryColor),
              ),

              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primaryColor),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryColor,
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
        const SizedBox(width: 10),

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
        ),

        const SizedBox(width: 10),

        /// 🔥 BRANCH FILTER
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String>(
            value: state.mismatchBranch,
            isExpanded: true,
            icon: const Icon(Icons.keyboard_arrow_down),

            decoration: InputDecoration(
              hintText: "Select Branch",

              filled: true,
              fillColor: AppColors.backgroundWidget,

              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),

              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primaryColor),
              ),

              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primaryColor),
              ),

              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppColors.primaryColor,
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
      width: widths[name] ?? 140,
      minimumWidth: 100,
      label: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}

class _MismatchDataSource extends DataGridSource {
  final List<MismatchItem> data;
  final BuildContext context;

  _MismatchDataSource(this.data, this.context);

  @override
  List<DataGridRow> get rows => List.generate(data.length, (index) {
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

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final index = effectiveRows.indexOf(row);

    return DataGridRowAdapter(
      color: index % 2 == 0 ? Colors.white : Colors.grey.shade50,
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
            child: Text(
              c.value.toString(),
              style: TextStyle(
                color: val < 0 ? Colors.red : Colors.green,
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
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(c.value.toString(), textAlign: TextAlign.center),
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
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
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
