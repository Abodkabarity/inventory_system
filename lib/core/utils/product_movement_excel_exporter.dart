import 'dart:html' as html;
import 'dart:typed_data';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../domain/entities/product_movement.dart';

class ProductMovementExcelExporter {
  static Future<void> export({
    required String itemLabel,
    required String branchLabel,
    required DateTime from,
    required DateTime to,
    required String movementTypeLabel,
    required List<ProductMovement> rows,
  }) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Product Movement';

    sheet.getRangeByIndex(1, 1).setText('Product Movement Export');
    sheet.getRangeByIndex(1, 1, 1, 8).merge();
    final title = sheet.getRangeByIndex(1, 1);
    title.cellStyle.bold = true;
    title.cellStyle.fontSize = 16;
    title.cellStyle.fontColor = '#0F172A';

    sheet.getRangeByIndex(2, 1).setText('Product');
    sheet.getRangeByIndex(2, 2).setText(itemLabel);
    sheet.getRangeByIndex(2, 4).setText('Branch');
    sheet.getRangeByIndex(2, 5).setText(branchLabel);
    sheet.getRangeByIndex(3, 1).setText('Date Range');
    sheet
        .getRangeByIndex(3, 2)
        .setText('${_formatDate(from)} -> ${_formatDate(to)}');
    sheet.getRangeByIndex(3, 4).setText('Movement Type');
    sheet.getRangeByIndex(3, 5).setText(movementTypeLabel);

    for (final cell in [
      sheet.getRangeByIndex(2, 1),
      sheet.getRangeByIndex(2, 4),
      sheet.getRangeByIndex(3, 1),
      sheet.getRangeByIndex(3, 4),
    ]) {
      cell.cellStyle.bold = true;
      cell.cellStyle.fontColor = '#475569';
    }

    final headers = [
      '#',
      'Branch Name',
      'Item Code',
      'Item Name',
      'Movement',
      'Qty',
      'Order Date',
      'Created At',
    ];

    const headerRow = 5;
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.getRangeByIndex(headerRow, c + 1);
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
      final values = [
        r + 1,
        row.branch,
        row.itemCode,
        row.itemName,
        _movementTitle(row.movementType),
        row.qty,
        _formatDate(row.movementDate),
        _formatDateTime(row.createdAt),
      ];

      for (var c = 0; c < values.length; c++) {
        final cell = sheet.getRangeByIndex(headerRow + r + 1, c + 1);
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
        .getRangeByIndex(1, 1, headerRow + rows.length, headers.length)
        .autoFitColumns();
    sheet.getRangeByIndex(1, 2).columnWidth = 24;
    sheet.getRangeByIndex(1, 3).columnWidth = 18;
    sheet.getRangeByIndex(1, 4).columnWidth = 44;
    sheet.getRangeByIndex(1, 5).columnWidth = 20;
    sheet.getRangeByIndex(1, 7).columnWidth = 16;
    sheet.getRangeByIndex(1, 8).columnWidth = 20;
    sheet
            .getRangeByIndex(1, 1, headerRow + rows.length, headers.length)
            .rowHeight =
        22;

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final blob = html.Blob([Uint8List.fromList(bytes)]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final safeItem = itemLabel
        .replaceAll('/', '_')
        .replaceAll('\\', '_')
        .replaceAll(' ', '_');
    final fileName =
        'Product_Movement_${safeItem}_${_formatDate(from)}_${_formatDate(to)}.xlsx';

    html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  static String _movementTitle(String value) {
    switch (value) {
      case 'daily_order':
        return 'Daily Order';
      case 'additional_request':
        return 'Additional Request';
      default:
        return value;
    }
  }

  static String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _formatDateTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${_formatDate(date)} $hour:$minute';
  }
}
