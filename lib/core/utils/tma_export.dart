import 'dart:html' as html;
import 'dart:typed_data';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

class TmaExcelExporter {
  static Future<void> export({
    required List<Map<String, dynamic>> rows,
    required bool includeHistory,
  }) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];

    /// =========================
    /// 🔥 DETECT MODE (COMPARE)
    /// =========================
    final isCompare = rows.isNotEmpty && rows.first.containsKey('old_qty');

    /// =========================
    /// HEADERS
    /// =========================
    final headers = isCompare
        ? [
            'branch_name',
            'item_code',
            'item_name',

            /// 🔴 OLD
            'old_qty',
            'old_start',
            'old_end',

            /// 🟢 NEW
            'new_qty',
            'new_start',
            'new_end',
          ]
        : [
            'branch_name',
            'item_code',
            'item_name',
            'qty_per_duration',
            'start_date',
            'end_date',
          ];

    /// history
    if (!isCompare && includeHistory) {
      headers.addAll(['final_qty_to_keep', 'moved_at', 'action']);
    }

    /// =========================
    /// HEADER TITLES
    /// =========================
    final headerMap = {
      'branch_name': 'Branch',
      'item_code': 'Item Code',
      'item_name': 'Item Name',

      /// main
      'qty_per_duration': 'Qty',
      'start_date': 'Start',
      'end_date': 'End',

      /// OLD
      'old_qty': 'Old Qty',
      'old_start': 'Old Start',
      'old_end': 'Old End',

      /// NEW
      'new_qty': 'New Qty',
      'new_start': 'New Start',
      'new_end': 'New End',

      /// HISTORY
      'final_qty_to_keep': 'Final Qty',
      'moved_at': 'Moved At',
      'action': 'Action',
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

        /// 🎨 COLORING (compare mode)
        if (isCompare) {
          if (key.startsWith('old_')) {
            cell.cellStyle.backColor = '#F8D7DA'; // 🔴
          } else if (key.startsWith('new_')) {
            cell.cellStyle.backColor = '#D4EDDA'; // 🟢
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
      ..setAttribute("download", "tma.xlsx")
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  /// =========================
  /// COLUMN WIDTH
  /// =========================
  static double _getColumnWidth(String key) {
    if (key.contains('name')) return 35;
    if (key.contains('code')) return 25;
    if (key.contains('start') || key.contains('end')) return 25;
    if (key.contains('qty')) return 20;
    return 22;
  }
}
