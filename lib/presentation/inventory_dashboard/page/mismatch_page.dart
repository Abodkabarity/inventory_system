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
              Icons.history,
              size: 16,
              color: AppColors.secondaryColor,
            ),
            label: const Text(
              "View",
              style: TextStyle(color: AppColors.secondaryColor),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              final ctx = context;

              final res = await context
                  .read<InventoryBloc>()
                  .repo
                  .fetchMismatchHistory(item.branchName, item.itemCode);
              if (!ctx.mounted) return;

              showDialog(
                context: ctx,
                builder: (_) => AlertDialog(
                  backgroundColor: Colors.white,
                  title: const Text("History Log"),
                  content: SizedBox(
                    width: 600,
                    child: Column(
                      children: [
                        Expanded(
                          child: ListView(
                            children: res.map((e) {
                              return Card(
                                color: AppColors.white,
                                elevation: 5,
                                shadowColor: AppColors.primaryColor,
                                child: ListTile(
                                  title: Text(e['item_name'] ?? ''),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text("Action: ${e['action']}"),
                                      Text(
                                        "Old System: ${e['old_system_stock']}",
                                      ),
                                      Text(
                                        "Old Actual: ${e['old_actual_stock']}",
                                      ),
                                      Text("Diff: ${e['old_diff']}"),
                                      Text("Note: ${e['note'] ?? ''}"),
                                      Text("Time: ${e['changed_at']}"),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: EdgeInsets.symmetric(horizontal: 75.w),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          child: Text(
                            "Close",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
