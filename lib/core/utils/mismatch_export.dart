import 'dart:html' as html;
import 'dart:typed_data';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

class MismatchExcelExporter {
  static Future<void> export({
    required List<Map<String, dynamic>> rows,
    required bool includeHistory,
  }) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];

    /// =========================
    /// HEADERS
    /// =========================
    final headers = includeHistory
        ? [
            'branch_name',
            'item_code',
            'item_name',

            /// OLD
            'old_system_stock',
            'old_actual_stock',
            'old_diff',

            /// NEW
            'new_system_stock',
            'new_actual_stock',
            'new_diff',

            'action',
            'changed_by',
            'changed_at',
            'note',
          ]
        : [
            'branch_name',
            'item_code',
            'item_name',
            'system_stock',
            'actual_stock',
            'diff',
            'update_date',
          ];

    /// =========================
    /// HEADER TITLES
    /// =========================
    final headerMap = {
      'branch_name': 'Branch',
      'item_code': 'Item Code',
      'item_name': 'Item Name',

      'system_stock': 'System',
      'actual_stock': 'Actual',
      'diff': 'Diff',
      'update_date': 'Date',

      'old_system_stock': 'Old System',
      'old_actual_stock': 'Old Actual',
      'old_diff': 'Old Diff',

      'new_system_stock': 'New System',
      'new_actual_stock': 'New Actual',
      'new_diff': 'New Diff',

      'action': 'Action',
      'changed_by': 'Changed By',
      'changed_at': 'Changed At',
      'note': 'Note',
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

      sheet.getRangeByIndex(1, c + 1).columnWidth = key.contains('name')
          ? 35
          : 22;
    }

    /// =========================
    /// DATA
    /// =========================
    for (int r = 0; r < rows.length; r++) {
      final row = rows[r];

      for (int c = 0; c < headers.length; c++) {
        final key = headers[c];
        final value = row[key];

        final cell = sheet.getRangeByIndex(r + 2, c + 1);

        if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText(value?.toString() ?? '');
        }

        cell.cellStyle.hAlign = xlsio.HAlignType.center;

        /// 🔥 COLORING
        if (key.startsWith('old_')) {
          cell.cellStyle.backColor = '#F8D7DA';
        } else if (key.startsWith('new_')) {
          cell.cellStyle.backColor = '#D4EDDA';
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
      ..setAttribute("download", "mismatch.xlsx")
      ..click();

    html.Url.revokeObjectUrl(url);
  }
}
