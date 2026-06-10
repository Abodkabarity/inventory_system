import 'dart:html' as html;
import 'dart:typed_data';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../data/models/transfer_report_row.dart';

class TransferReportExcelExporter {
  static Future<void> export(List<TransferReportRow> rows) async {
    final workbook = xlsio.Workbook();

    final sheet = workbook.worksheets[0];

    final headers = [
      'Status',
      'Branch',
      'Item Code',
      'Item Name',
      'Quantity In Order',
      'Prepared By Store',
      'Difference',
      'Completion %',
    ];

    /// =========================
    /// HEADER
    /// =========================

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(1, i + 1);

      cell.setText(headers[i]);

      cell.cellStyle.bold = true;
      cell.cellStyle.backColor = '#243B53';
      cell.cellStyle.fontColor = '#FFFFFF';
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
    }

    /// =========================
    /// DATA
    /// =========================

    for (int r = 0; r < rows.length; r++) {
      final item = rows[r];

      String status;

      switch (item.status) {
        case TransferStatus.complete:
          status = 'COMPLETE';
          break;

        case TransferStatus.partial:
          status = 'PARTIAL';
          break;

        case TransferStatus.missing:
          status = 'MISSING';
          break;

        case TransferStatus.extra:
          status = 'EXTRA';
          break;

        case TransferStatus.notInDailyOrder:
          status = 'NOT IN DAILY ORDER';
          break;
      }

      final values = [
        status,
        item.branch,
        item.itemCode,
        item.itemName,
        item.requiredQty,
        item.transferredQty,
        item.diff,
        item.completion,
      ];

      for (int c = 0; c < values.length; c++) {
        final cell = sheet.getRangeByIndex(r + 2, c + 1);

        final value = values[c];

        if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText(value.toString());
        }

        cell.cellStyle.hAlign = xlsio.HAlignType.center;
      }
    }

    /// =========================
    /// COLUMN WIDTHS
    /// =========================

    sheet
        .getRangeByIndex(1, 1, rows.length + 1, headers.length)
        .autoFitColumns();

    sheet.getRangeByIndex(1, 4).columnWidth = 40;

    /// =========================
    /// SAVE
    /// =========================

    final bytes = workbook.saveAsStream();

    workbook.dispose();

    final blob = html.Blob([Uint8List.fromList(bytes)]);

    final url = html.Url.createObjectUrlFromBlob(blob);

    final branchName = rows.isNotEmpty
        ? rows.first.branch
              .replaceAll('/', '_')
              .replaceAll('\\', '_')
              .replaceAll(' ', '_')
        : 'UNKNOWN_BRANCH';

    final date = DateTime.now().toString().split(' ').first;

    final fileName = 'Transfer_Report_${branchName}_$date.xlsx';

    html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();

    html.Url.revokeObjectUrl(url);
  }
}
