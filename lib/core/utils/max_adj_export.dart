import 'dart:html' as html;
import 'dart:typed_data';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

class MaxAdjExcelExporter {
  static Future<void> export({
    required List<Map<String, dynamic>> rows,
    required bool includeHistory,
  }) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];

    /// =========================
    /// HEADERS
    /// =========================
    final headers = [
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
    ];

    if (includeHistory) {
      headers.addAll(['created_at', 'action_type', 'moved_at']);
    }

    /// =========================
    /// HEADER TITLES
    /// =========================
    final headerMap = {
      'branch_name': 'Branch',
      'item_code': 'Item Code',
      'item_name': 'Item Name',
      'current_demand_30d': 'Demand',
      'max_adjustment_30d': 'Max Adjustment',
      'adjustment_type': 'Type',
      'reason': 'Reason',
      'update_date': 'Update Date',
      'qty': 'Qty',
      'added_by': 'Added By',
      'end_date': 'End Date',
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

  static double _getColumnWidth(String key) {
    if (key.contains('name')) return 35;
    if (key.contains('code')) return 25;
    if (key.contains('reason')) return 40;
    if (key.contains('date')) return 25;
    return 20;
  }
}
