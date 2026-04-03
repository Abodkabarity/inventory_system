import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
    context.read<InventoryBloc>().add(StartMismatchRealtime());
    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, state) {
        final rows = state.filteredMismatch;
        final widths = state.mismatchColumnWidths;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _cards(state),
              const SizedBox(height: 16),
              _filters(context, state),
              const SizedBox(height: 16),

              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SfDataGridTheme(
                    data: SfDataGridThemeData(
                      headerColor: const Color(0xFF1E293B),
                      gridLineColor: AppColors.border.withValues(alpha: .7),
                      selectionColor: const Color(0xFFEAF2FF),
                    ),
                    child: SfDataGrid(
                      source: _MismatchDataSource(rows, context),

                      allowFiltering: true,
                      allowColumnsResizing: true,
                      allowSorting: false,

                      columnWidthMode: ColumnWidthMode.none,

                      gridLinesVisibility: GridLinesVisibility.both,
                      headerGridLinesVisibility: GridLinesVisibility.both,

                      rowHeight: 52,
                      headerRowHeight: 65,

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

                        _col("branch", "BRANCH", widths),
                        _col("code", "ITEM CODE", widths),
                        _col("name", "ITEM NAME", widths),
                        _col("system", "SYSTEM", widths),
                        _col("actual", "ACTUAL", widths),
                        _col("diff", "DIFF", widths),
                        _col("history", "HISTORY", widths),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// ================= CARDS =================
  Widget _cards(InventoryState state) {
    final total = state.mismatchTotalCount;
    final diffSum = state.mismatchDiffSum;
    return Row(
      children: [
        _card("Today Mismatch", state.mismatchTodayCount),
        _card("Month Mismatch", state.mismatchMonthCount),
        _card("Total Mismatch", total),
        _card("Total Diff", diffSum),
      ],
    );
  }

  Widget _card(String title, num value) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(title),
              const SizedBox(height: 8),
              Text(
                value.toString(),
                style: const TextStyle(
                  fontSize: 20,
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
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Stack(
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.track_changes),
              label: const Text("Mismatch Tracker"),
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

            /// 🔴 BADGE
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
        SizedBox(width: 10),
        DropdownButton<String>(
          value: state.mismatchBranch,
          items: [
            "ALL",
            ...state.branches,
          ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) {
            context.read<InventoryBloc>().add(FilterMismatchBranch(v!));
          },
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
            fontWeight: FontWeight.w900,
            color: Colors.white,
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
    return DataGridRowAdapter(
      cells: row.getCells().map((c) {
        if (c.columnName == 'diff') {
          final val = num.tryParse(c.value.toString()) ?? 0;

          return Container(
            alignment: Alignment.center,
            child: Text(
              c.value.toString(),
              style: TextStyle(
                color: val < 0 ? Colors.red : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }

        if (c.columnName == 'history') {
          final item = c.value as MismatchItem;

          if (!item.hasHistory) {
            return const SizedBox();
          }

          return ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: () async {
              final res = await context
                  .read<InventoryBloc>()
                  .repo
                  .fetchMismatchHistory(item.branchName, item.itemCode);

              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text("History Log"),
                  content: SizedBox(
                    width: 600,
                    child: ListView(
                      children: res.map((e) {
                        return Card(
                          child: ListTile(
                            title: Text(e['item_name'] ?? ''),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Action: ${e['action']}"),
                                Text("Old System: ${e['old_system_stock']}"),
                                Text("Old Actual: ${e['old_actual_stock']}"),
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
                ),
              );
            },
            child: const Text("View"),
          );
        }

        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(c.value.toString()),
        );
      }).toList(),
    );
  }
}
