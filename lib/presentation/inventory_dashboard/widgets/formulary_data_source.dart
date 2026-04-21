import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

class FormularyDataSource extends DataGridSource {
  final List<Map<String, dynamic>> _allData;
  final Function(Map<String, dynamic>) onHistory;

  static const int rowsPerPage = 1000;

  List<DataGridRow> _rows = [];

  FormularyDataSource({
    required List<Map<String, dynamic>> data,
    required this.onHistory,
  }) : _allData = data {
    _buildPage(0);
  }

  void _buildPage(int pageIndex) {
    final start = pageIndex * rowsPerPage;

    final pageData = _allData.skip(start).take(rowsPerPage).toList();

    _rows = pageData.asMap().entries.map((entry) {
      final index = start + entry.key;
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

    notifyListeners();
  }

  /// 🔥 مهم جداً (هذا سبب مشكلتك)
  @override
  Future<bool> handlePageChange(int oldPageIndex, int newPageIndex) async {
    _buildPage(newPageIndex);
    return true;
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
              icon: const Icon(Icons.history),
              onPressed: () => onHistory(cell.value),
            ),
          );
        }

        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(8),
          child: Text(
            cell.value?.toString() ?? '',
            softWrap: true,
            overflow: TextOverflow.visible,
          ),
        );
      }).toList(),
    );
  }

  double get totalPages => (_allData.length / rowsPerPage).ceilToDouble();

  int get totalRows => _allData.length;
}
