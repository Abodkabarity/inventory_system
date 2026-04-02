import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
  final searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<InventoryBloc>().add(LoadMismatch());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InventoryBloc, InventoryState>(
      builder: (context, state) {
        final rows = state.filteredMismatch;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _cards(state),
              const SizedBox(height: 16),
              _filters(state),
              const SizedBox(height: 16),

              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SfDataGridTheme(
                    data: SfDataGridThemeData(
                      headerColor: const Color(0xFFF7F8FC),
                      gridLineColor: AppColors.border.withOpacity(.8),
                      selectionColor: const Color(0xFFEAF2FF),
                    ),
                    child: SfDataGrid(
                      source: _MismatchDataSource(rows, context),

                      allowFiltering: true,
                      allowSorting: false,
                      allowColumnsResizing: true,

                      columnWidthMode: ColumnWidthMode.none,

                      gridLinesVisibility: GridLinesVisibility.both,
                      headerGridLinesVisibility: GridLinesVisibility.both,

                      frozenColumnsCount: 0,

                      rowHeight: 52,
                      headerRowHeight: 72,

                      onColumnResizeUpdate: (details) {
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
      },
    );
  }

  /// ================= CARDS =================
  Widget _cards(InventoryState state) {
    final total = state.mismatch.length;
    final diffSum = state.mismatch.fold<num>(0, (sum, e) => sum + e.diff);

    return Row(
      children: [
        _card("Today Changes", total),
        _card("Month Changes", total),
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
  Widget _filters(InventoryState state) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: searchController,
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

  /// ================= COLUMNS =================
  List<GridColumn> _columns() {
    return [
      _col("branch", "BRANCH"),
      _col("code", "ITEM CODE"),
      _col("name", "ITEM NAME"),
      _col("system", "SYSTEM"),
      _col("actual", "ACTUAL"),
      _col("diff", "DIFF"),
      _col("history", "HISTORY"),
    ];
  }

  GridColumn _col(String name, String title) {
    return GridColumn(
      columnName: name,
      width: 160,
      minimumWidth: 120,
      label: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(8),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
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
  List<DataGridRow> get rows => data.map((e) {
    return DataGridRow(
      cells: [
        DataGridCell(columnName: 'branch', value: e.branchName),
        DataGridCell(columnName: 'code', value: e.itemCode),
        DataGridCell(columnName: 'name', value: e.itemName),
        DataGridCell(columnName: 'system', value: e.systemStock),
        DataGridCell(columnName: 'actual', value: e.actualStock),
        DataGridCell(columnName: 'diff', value: e.diff),
        DataGridCell(columnName: 'history', value: e),
      ],
    );
  }).toList();

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    return DataGridRowAdapter(
      cells: row.getCells().map((c) {
        /// DIFF COLOR
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

        /// HISTORY BUTTON
        if (c.columnName == 'history') {
          final item = c.value as MismatchItem;

          if (!item.hasHistory) return const SizedBox();

          return ElevatedButton(
            onPressed: () async {
              final res = await context
                  .read<InventoryBloc>()
                  .repo
                  .fetchMismatchHistory(item.branchName, item.itemCode);

              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text("History"),
                  content: SizedBox(
                    width: 500,
                    child: ListView(
                      children: res
                          .map(
                            (e) => ListTile(
                              title: Text(e['action']),
                              subtitle: Text(e['changed_at']),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              );
            },
            child: const Text("View"),
          );
        }

        /// NORMAL CELL
        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(c.value.toString(), overflow: TextOverflow.ellipsis),
        );
      }).toList(),
    );
  }
}
