import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

class TmaDataSource extends DataGridSource {
  List<DataGridRow> _rows = [];

  final Function(Map<String, dynamic>) onHistory;

  TmaDataSource({
    required List<Map<String, dynamic>> data,
    required this.onHistory,
  }) {
    _rows = data.asMap().entries.map((entry) {
      final index = entry.key;
      final e = entry.value;

      return DataGridRow(
        cells: [
          DataGridCell(columnName: 'index', value: index + 1),
          DataGridCell(columnName: 'branch', value: e['branch_name']),
          DataGridCell(columnName: 'code', value: e['item_code']),
          DataGridCell(columnName: 'name', value: e['item_name']),
          DataGridCell(columnName: 'qty', value: e['qty_per_duration']),
          DataGridCell(columnName: 'start', value: e['start_date']),
          DataGridCell(columnName: 'end', value: e['end_date']),
          DataGridCell(columnName: 'action', value: e),
        ],
      );
    }).toList();
  }

  @override
  List<DataGridRow> get rows => _rows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    return DataGridRowAdapter(
      cells: row.getCells().map((cell) {
        if (cell.columnName == 'action') {
          return IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => onHistory(cell.value),
          );
        }

        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(8),
          child: Text(cell.value?.toString() ?? ''),
        );
      }).toList(),
    );
  }
}
