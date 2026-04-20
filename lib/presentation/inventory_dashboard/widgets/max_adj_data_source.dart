import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

class MaxAdjDataSource extends DataGridSource {
  List<DataGridRow> _rows = [];

  final Function(Map<String, dynamic>) onHistory;

  MaxAdjDataSource({
    required List<Map<String, dynamic>> data,
    required this.onHistory,
  }) {
    _rows = data.map<DataGridRow>((e) {
      return DataGridRow(
        cells: [
          DataGridCell(columnName: 'branch', value: e['branch_name']),
          DataGridCell(columnName: 'code', value: e['item_code']),
          DataGridCell(columnName: 'name', value: e['item_name']),
          DataGridCell(columnName: 'demand', value: e['current_demand_30d']),
          DataGridCell(columnName: 'max', value: e['max_adjustment_30d']),
          DataGridCell(columnName: 'type', value: e['adjustment_type']),
          DataGridCell(columnName: 'qty', value: e['qty']),
          DataGridCell(columnName: 'added', value: e['added_by']),
          DataGridCell(columnName: 'date', value: e['update_date']),
          DataGridCell(columnName: 'action', value: e),
        ],
      );
    }).toList();
  }

  @override
  List<DataGridRow> get rows => _rows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final type = row.getCells()[5].value;

    return DataGridRowAdapter(
      color: Colors.white,
      cells: row.getCells().map<Widget>((cell) {
        /// 🔹 تحديد الأعمدة الرقمية
        final isCenterColumn = [
          'demand',
          'max',
          'qty',
          'type',
          'added',
          'date',
        ].contains(cell.columnName);

        /// 🔹 زر History
        if (cell.columnName == 'action') {
          final data = cell.value;

          return Center(
            child: IconButton(
              icon: const Icon(Icons.history),
              onPressed: () => onHistory(data),
            ),
          );
        }

        /// 🔹 Type ملون
        if (cell.columnName == 'type') {
          return Center(
            child: Text(
              type,
              style: TextStyle(
                color: type == 'INCREASE' ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }

        return Container(
          alignment: isCenterColumn ? Alignment.center : Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            cell.value?.toString() ?? '',
            style: const TextStyle(fontSize: 13),
          ),
        );
      }).toList(),
    );
  }
}
