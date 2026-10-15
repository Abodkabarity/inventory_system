import 'dart:html' as html;
import 'dart:typed_data';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'store_branch_identity_registry.dart';
import 'max_adj_export_rows.dart';

class MaxAdjExcelExporter {
  static Future<void> export({
    required List<Map<String, dynamic>> rows,
    required bool includeHistory,
  }) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];

    /// =========================
    /// 🔥 DETECT MODE
    /// =========================
    final isCompare = rows.isNotEmpty && rows.first.containsKey('old_max_adj');
    final displayRows = isCompare ? rows : maxAdjExportRows(rows);

    /// =========================
    /// HEADERS
    /// =========================
    final headers = isCompare
        ? [
            'branch_name',
            'item_code',
            'item_name',

            /// 🔵 OLD
            'old_current_demand',
            'old_max_adj',
            'old_adjustment_type',
            'old_reason',
            'old_update_date',
            'old_added_by',
            'old_end_date',

            /// 🟢 NEW
            'new_current_demand',
            'new_max_adj',
            'new_adjustment_type',
            'new_reason',
            'new_update_date',
            'new_added_by',
            'new_end_date',
          ]
        : [
            'branch_name',
            'item_code',
            'item_name',
            'current_demand_30d',
            'max_adjustment_30d',
            'adjustment_type',
            'reason',
            'update_date',
            'qty',
            'added_by',
            'end_date',
            'expiry_date',
            'remaining_days',
          ];

    if (!isCompare && includeHistory) {
      headers.addAll(['created_at', 'action_type', 'moved_at']);
    }

    /// =========================
    /// HEADER TITLES
    /// =========================
    final headerMap = {
      'branch_name': 'Branch',
      'item_code': 'Item Code',
      'item_name': 'Item Name',

      /// NORMAL
      'current_demand_30d': 'Demand',
      'max_adjustment_30d': 'Max Adjustment',
      'adjustment_type': 'Type',
      'reason': 'Reason',
      'update_date': 'Update Date',
      'qty': 'Qty',
      'added_by': 'Added By',
      'end_date': 'End Date',
      'expiry_date': 'Effective Expiry Date',
      'remaining_days': 'Days Remaining (at export)',

      /// OLD
      'old_current_demand': 'Old Demand',
      'old_max_adj': 'Old Max',
      'old_adjustment_type': 'Old Type',
      'old_reason': 'Old Reason',
      'old_update_date': 'Old Update Date',
      'old_added_by': 'Old Added By',
      'old_end_date': 'Old End Date',

      /// NEW
      'new_current_demand': 'New Demand',
      'new_max_adj': 'New Max',
      'new_adjustment_type': 'New Type',
      'new_reason': 'New Reason',
      'new_update_date': 'New Update Date',
      'new_added_by': 'New Added By',
      'new_end_date': 'New End Date',

      /// HISTORY
      'created_at': 'Created At',
      'action_type': 'Action Type',
      'moved_at': 'Moved At',
    };

    /// =========================
    /// HEADER STYLE
    /// =========================
    for (int c = 0; c < headers.length; c++) {
      final key = headers[c];

      final cell = sheet.getRangeByIndex(1, c + 1);
      cell.setText(headerMap[key] ?? key);

      cell.cellStyle.bold = true;
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.backColor = '#E6E8F0';

      sheet.getRangeByIndex(1, c + 1).columnWidth = _getColumnWidth(key);
    }

    /// =========================
    /// DATA
    /// =========================
    for (int r = 0; r < rows.length; r++) {
      final row = displayRows[r];

      for (int c = 0; c < headers.length; c++) {
        final key = headers[c];
        final value = StoreBranchIdentityRegistry.exportValue(key, row[key]);

        final cell = sheet.getRangeByIndex(r + 2, c + 1);

        if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText(value?.toString() ?? '');
        }

        cell.cellStyle.hAlign = xlsio.HAlignType.center;

        /// =========================
        /// 🎨 COLORING (COMPARE MODE)
        /// =========================
        if (isCompare) {
          if (key.startsWith('old_')) {
            cell.cellStyle.backColor = '#F8D7DA'; // 🔴 OLD
          } else if (key.startsWith('new_')) {
            cell.cellStyle.backColor = '#D4EDDA'; // 🟢 NEW
          }
        }
      }
    }

    /// =========================
    /// SAVE
    /// =========================
    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final blob = html.Blob([Uint8List.fromList(bytes)]);
    final url = html.Url.createObjectUrlFromBlob(blob);

    html.AnchorElement(href: url)
      ..setAttribute("download", "max_adjustment.xlsx")
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  /// =========================
  /// COLUMN WIDTH
  /// =========================
  static double _getColumnWidth(String key) {
    if (key.contains('name')) return 35;
    if (key.contains('code')) return 25;
    if (key.contains('reason')) return 40;
    if (key.contains('date')) return 25;
    return 20;
  }
}
