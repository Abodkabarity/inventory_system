import 'dart:html' as html;
import 'dart:typed_data';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

class BranchOrderExcelExporter {
  static Future<void> export({
    required String branch,
    required DateTime orderDate,
    required List<Map<String, dynamic>> rows,
  }) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Branch Order';

    final headers = [
      '#',
      'Branch Name',
      'Item Code',
      'Item Name',
      'Qty',
      'Order Date',
    ];

    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.getRangeByIndex(1, c + 1);
      cell.setText(headers[c]);
      cell.cellStyle.bold = true;
      cell.cellStyle.fontColor = '#FFFFFF';
      cell.cellStyle.backColor = '#0F6CBD';
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.vAlign = xlsio.VAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      cell.cellStyle.borders.all.color = '#1E3A8A';
    }

    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      final qty = num.tryParse((row['qty'] ?? '0').toString()) ?? 0;
      final values = [
        r + 1,
        row['branch'] ?? branch,
        row['item_code'] ?? '',
        row['item_name'] ?? '',
        qty,
        row['movement_date'] ?? _formatDate(orderDate),
      ];

      for (var c = 0; c < values.length; c++) {
        final cell = sheet.getRangeByIndex(r + 2, c + 1);
        final value = values[c];

        if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText(value.toString());
        }

        cell.cellStyle.hAlign = c == 3
            ? xlsio.HAlignType.left
            : xlsio.HAlignType.center;
        cell.cellStyle.vAlign = xlsio.VAlignType.center;
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        cell.cellStyle.borders.all.color = '#CBD5E1';
      }
    }

    sheet
        .getRangeByIndex(1, 1, rows.length + 1, headers.length)
        .autoFitColumns();
    sheet.getRangeByIndex(1, 4).columnWidth = 46;
    sheet.getRangeByIndex(1, 2).columnWidth = 22;
    sheet.getRangeByIndex(1, 3).columnWidth = 18;
    sheet.getRangeByIndex(1, 5).columnWidth = 10;
    sheet.getRangeByIndex(1, 6).columnWidth = 16;
    sheet.getRangeByIndex(1, 1, rows.length + 1, headers.length).rowHeight = 22;

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final blob = html.Blob([Uint8List.fromList(bytes)]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final safeBranch = branch
        .replaceAll('/', '_')
        .replaceAll('\\', '_')
        .replaceAll(' ', '_');
    final fileName =
        'Branch_Order_${safeBranch}_${_formatDate(orderDate)}.xlsx';

    html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  static String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
