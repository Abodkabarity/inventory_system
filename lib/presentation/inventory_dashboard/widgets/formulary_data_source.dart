import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

class FormularyDataSource extends DataGridSource {
  final List<Map<String, dynamic>> data;
  final int pageOffset;
  final Function(Map<String, dynamic>) onHistory;

  late final List<DataGridRow> _rows;

  FormularyDataSource({
    required this.data,
    required this.onHistory,
    this.pageOffset = 0,
  }) {
    _rows = data.asMap().entries.map((entry) {
      final index = pageOffset + entry.key;
      final e = entry.value;

      return DataGridRow(
        cells: [
          DataGridCell(columnName: 'index', value: index + 1),
          DataGridCell(columnName: 'branch', value: e['branch_name']),
          DataGridCell(columnName: 'code', value: e['item_code']),
          DataGridCell(columnName: 'name', value: e['item_name']),
          DataGridCell(
            columnName: 'status',
            value: e['revised_branch_formulary'],
          ),
          DataGridCell(columnName: 'date', value: e['revised_date']),
          DataGridCell(columnName: 'reason', value: e['reason']),
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
          return Center(
            child: IconButton(
              tooltip: 'History',
              icon: const Icon(Icons.history_rounded),
              onPressed: () => onHistory(cell.value),
            ),
          );
        }

        final align = cell.columnName == 'name' || cell.columnName == 'reason'
            ? Alignment.centerLeft
            : Alignment.center;

        return Container(
          alignment: align,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            cell.value?.toString() ?? '',
            maxLines: cell.columnName == 'name' ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xff1E293B),
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }).toList(),
    );
  }
}
