import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/max_adjustment_expiry.dart';
import '../../../core/utils/store_branch_identity_registry.dart';

class MaxAdjDataSource extends DataGridSource {
  List<DataGridRow> _rows = [];

  final Function(Map<String, dynamic>) onHistory;
  final int pageOffset;

  MaxAdjDataSource({
    required List<Map<String, dynamic>> data,
    required this.onHistory,
    this.pageOffset = 0,
    DateTime? now,
  }) {
    final snapshot = now ?? DateTime.now();
    _rows = data.asMap().entries.map<DataGridRow>((entry) {
      final index = entry.key;
      final e = entry.value;
      final expiry = MaxAdjustmentExpiry(e, now: snapshot);

      return DataGridRow(
        cells: [
          DataGridCell(columnName: 'index', value: pageOffset + index + 1),

          DataGridCell(
            columnName: 'branch',
            value: StoreBranchIdentityRegistry.displayName(
              e['branch_name']?.toString(),
            ),
          ),
          DataGridCell(columnName: 'code', value: e['item_code']),
          DataGridCell(columnName: 'name', value: e['item_name']),
          DataGridCell(columnName: 'demand', value: e['current_demand_30d']),
          DataGridCell(columnName: 'max', value: e['max_adjustment_30d']),
          DataGridCell<int>(
            columnName: 'remaining_days',
            value: expiry.daysRemaining,
          ),
          DataGridCell(columnName: 'type', value: e['adjustment_type']),
          DataGridCell(columnName: 'qty', value: e['qty']),
          DataGridCell(columnName: 'reason', value: e['reason']),
          DataGridCell(columnName: 'date', value: e['update_date']),
          DataGridCell(
            columnName: 'expiry_date',
            value: expiry.deadline == null ? null : expiry.dateLabel,
          ),
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
    final type =
        row
            .getCells()
            .firstWhere((cell) => cell.columnName == 'type')
            .value
            ?.toString() ??
        '';

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
          'expiry_date',
        ].contains(cell.columnName);

        if (cell.columnName == 'action') {
          final data = cell.value;

          return Center(
            child: IconButton(
              tooltip: 'View adjustment history',
              icon: const Icon(Icons.history),
              onPressed: () => onHistory(data),
            ),
          );
        }

        if (cell.columnName == 'remaining_days') {
          final data =
              row.getCells().firstWhere((c) => c.columnName == 'action').value
                  as Map<String, dynamic>;
          final expiry = MaxAdjustmentExpiry(data);
          final days = cell.value as int?;
          // Use the source snapshot so labels and numeric sorting agree.
          final label = MaxAdjustmentExpiry.labelForDays(days);
          final color = days == null
              ? AppColors.subText
              : days <= 0
              ? const Color(0xFFDC2626)
              : days <= 7
              ? const Color(0xFFB45309)
              : const Color(0xFF15803D);
          return Tooltip(
            message: expiry.tooltip,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
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
