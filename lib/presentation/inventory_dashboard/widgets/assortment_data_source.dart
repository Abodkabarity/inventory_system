import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../core/theme/app_colors.dart';

class AssortmentDataSource extends DataGridSource {
  List<DataGridRow> _rows = [];

  final Function(Map<String, dynamic>) onHistory;

  AssortmentDataSource({
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
          DataGridCell(columnName: 'qty', value: e['assortment_qty']),
          DataGridCell(columnName: 'by', value: e['assortment_by']),
          DataGridCell(columnName: 'reason', value: e['reason']),
          DataGridCell(columnName: 'start', value: e['assortment_start']),
          DataGridCell(columnName: 'end', value: e['assortment_end']),
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
      color: AppColors.card,
      cells: row.getCells().map((cell) {
        if (cell.columnName == 'action') {
          return IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => onHistory(cell.value),
          );
        }

        final isCenter = [
          'index',
          'qty',
          'by',
          'start',
          'end',
        ].contains(cell.columnName);
        final value = cell.value?.toString().trim() ?? '';

        if (cell.columnName == 'reason') {
          final display = value.isEmpty ? 'No reason recorded' : value;
          return Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Tooltip(
              message: display,
              child: SelectableText(
                display,
                maxLines: 1,
                style: TextStyle(
                  color: value.isEmpty ? AppColors.subText : AppColors.text,
                  fontStyle: value.isEmpty
                      ? FontStyle.italic
                      : FontStyle.normal,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }

        return Container(
          alignment: isCenter ? Alignment.center : Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SelectableText(
            value,
            textAlign: isCenter ? TextAlign.center : TextAlign.left,
            style: const TextStyle(fontSize: 13, color: AppColors.text),
          ),
        );
      }).toList(),
    );
  }
}
