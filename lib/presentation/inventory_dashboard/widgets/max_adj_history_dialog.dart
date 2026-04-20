import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../core/theme/app_colors.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_state.dart';

class MaxAdjHistoryDialog extends StatelessWidget {
  const MaxAdjHistoryDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: BlocBuilder<InventoryBloc, InventoryState>(
        builder: (context, state) {
          return Container(
            width: 1500.w,
            height: 500.h,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  "History",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 15),

                Expanded(
                  child: state.isHistoryLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primaryColor,
                          ),
                        )
                      : state.maxAdjHistory.isEmpty
                      ? const Center(child: Text("No history"))
                      : SfDataGrid(
                          source: _HistoryDataSource(state.maxAdjHistory),
                          columnWidthMode: ColumnWidthMode.fill,
                          headerRowHeight: 50,
                          rowHeight: 45,
                          columns: [
                            _col('branch', 'Branch'),
                            _col('code', 'Item Code'),
                            _col('name', 'Item Name'),
                            _col('demand', 'Demand', center: true),
                            _col('max', 'Max Adj', center: true),
                            _col('type', 'Type', center: true),
                            _col('qty', 'Qty', center: true),
                            _col('reason', 'Reason'),
                            _col('date', 'Date', center: true),
                            _col('status', 'Status', center: true),
                          ],
                        ),
                ),

                const SizedBox(height: 10),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Close"),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  GridColumn _col(String name, String title, {bool center = false}) {
    return GridColumn(
      columnName: name,
      label: Container(
        alignment: center ? Alignment.center : Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _HistoryDataSource extends DataGridSource {
  List<DataGridRow> _rows = [];

  _HistoryDataSource(List<Map<String, dynamic>> data) {
    _rows = data.map((e) {
      return DataGridRow(
        cells: [
          DataGridCell(columnName: 'branch', value: e['branch_name']),
          DataGridCell(columnName: 'code', value: e['item_code']),
          DataGridCell(columnName: 'name', value: e['item_name']),
          DataGridCell(columnName: 'demand', value: e['current_demand_30d']),
          DataGridCell(columnName: 'max', value: e['max_adjustment_30d']),
          DataGridCell(columnName: 'type', value: e['adjustment_type']),
          DataGridCell(columnName: 'qty', value: e['qty']),
          DataGridCell(columnName: 'reason', value: e['reason']),
          DataGridCell(
            columnName: 'date',
            value: e['update_date'] ?? e['moved_at'],
          ),
          DataGridCell(
            columnName: 'status',
            value: e['action'] ?? e['action_type'] ?? 'current',
          ),
        ],
      );
    }).toList();
  }

  @override
  List<DataGridRow> get rows => _rows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    return DataGridRowAdapter(
      cells: row.getCells().map<Widget>((cell) {
        if (cell.columnName == 'type') {
          return Center(
            child: Text(
              cell.value.toString(),
              style: TextStyle(
                color: cell.value == 'INCREASE' ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }

        if (cell.columnName == 'status') {
          return Center(
            child: Text(
              cell.value.toString(),
              style: TextStyle(
                color: cell.value == 'log' ? Colors.orange : Colors.blue,
              ),
            ),
          );
        }

        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(cell.value?.toString() ?? ''),
        );
      }).toList(),
    );
  }
}
