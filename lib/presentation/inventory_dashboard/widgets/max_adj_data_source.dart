import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../core/theme/app_colors.dart';

class MaxAdjDataSource extends DataGridSource {
  List<DataGridRow> _rows = [];

  final Function(Map<String, dynamic>) onHistory;
  final int pageOffset;

  MaxAdjDataSource({
    required List<Map<String, dynamic>> data,
    required this.onHistory,
    this.pageOffset = 0,
  }) {
    _rows = data.asMap().entries.map<DataGridRow>((entry) {
      final index = entry.key;
      final e = entry.value;

      return DataGridRow(
        cells: [
          DataGridCell(columnName: 'index', value: pageOffset + index + 1),

          DataGridCell(columnName: 'branch', value: e['branch_name']),
          DataGridCell(columnName: 'code', value: e['item_code']),
          DataGridCell(columnName: 'name', value: e['item_name']),
          DataGridCell(columnName: 'demand', value: e['current_demand_30d']),
          DataGridCell(columnName: 'max', value: e['max_adjustment_30d']),
          DataGridCell(columnName: 'type', value: e['adjustment_type']),
          DataGridCell(columnName: 'qty', value: e['qty']),
          DataGridCell(columnName: 'reason', value: e['reason']),
          DataGridCell(columnName: 'date', value: e['update_date']),
          DataGridCell(columnName: 'added_by', value: e['added_by']),
          DataGridCell(columnName: 'action', value: e),
        ],
      );
    }).toList();
  }

  @override
  List<DataGridRow> get rows => _rows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final type = row.getCells()[6].value;

    return DataGridRowAdapter(
      color: AppColors.card,
      cells: row.getCells().map<Widget>((cell) {
        final isCenterColumn = [
          'index',
          'demand',
          'max',
          'qty',
          'type',
          'added_by',
          'date',
        ].contains(cell.columnName);

        if (cell.columnName == 'action') {
          final data = cell.value;

          return Center(
            child: IconButton(
              icon: const Icon(Icons.history),
              onPressed: () => onHistory(data),
            ),
          );
        }

        /// 🔹 Type coloring
        if (cell.columnName == 'type') {
          return Center(
            child: SelectableText(
              type,
              style: TextStyle(
                color: type == 'INCREASE'
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFDC2626),
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }

        if (cell.columnName == 'reason') {
          final reason = cell.value?.toString().trim() ?? '';
          return Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Tooltip(
              message: reason.isEmpty ? 'No reason recorded' : reason,
              child: Text(
                reason.isEmpty ? 'No reason recorded' : reason,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: reason.isEmpty ? AppColors.subText : AppColors.text,
                  fontStyle: reason.isEmpty
                      ? FontStyle.italic
                      : FontStyle.normal,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }

        return Container(
          alignment: isCenterColumn ? Alignment.center : Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SelectableText(
            cell.value?.toString() ?? '',
            style: const TextStyle(fontSize: 13, color: AppColors.text),
          ),
        );
      }).toList(),
    );
  }
}
