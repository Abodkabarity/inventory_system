import 'dart:html' as html;
import 'dart:typed_data';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../domain/entities/allocation_result_row.dart';

class AllocationShortageExportRow {
  final String branch;
  final String itemCode;
  final String itemName;
  final num shortageQty;

  const AllocationShortageExportRow({
    required this.branch,
    required this.itemCode,
    required this.itemName,
    required this.shortageQty,
  });
}

class AllocationExcelExporter {
  static Future<void> export(List<AllocationResultRow> rows) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Allocation';

    const headers = [
      'From Branch',
      'Item Code',
      'Item Name',
      'QTY',
      'To Branch',
    ];

    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.getRangeByIndex(1, c + 1);
      cell.setText(headers[c]);
      cell.cellStyle.bold = true;
      cell.cellStyle.fontColor = '#FFFFFF';
      cell.cellStyle.backColor = '#0EA5E9';
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.vAlign = xlsio.VAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      cell.cellStyle.borders.all.color = '#0F172A';
    }

    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      final values = [
        row.fromBranch,
        row.itemCode,
        row.itemName,
        row.qty,
        row.toBranch,
      ];

      for (var c = 0; c < values.length; c++) {
        final cell = sheet.getRangeByIndex(r + 2, c + 1);
        final value = values[c];

        if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText(value.toString());
        }

        cell.cellStyle.hAlign = c == 2
            ? xlsio.HAlignType.left
            : xlsio.HAlignType.center;
        cell.cellStyle.vAlign = xlsio.VAlignType.center;
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        cell.cellStyle.borders.all.color = '#CBD5E1';

        if (r.isEven) {
          cell.cellStyle.backColor = '#F8FAFC';
        }
      }
    }

    sheet.getRangeByIndex(1, 1).columnWidth = 24;
    sheet.getRangeByIndex(1, 2).columnWidth = 18;
    sheet.getRangeByIndex(1, 3).columnWidth = 42;
    sheet.getRangeByIndex(1, 4).columnWidth = 12;
    sheet.getRangeByIndex(1, 5).columnWidth = 24;

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final blob = html.Blob([Uint8List.fromList(bytes)]);
    final url = html.Url.createObjectUrlFromBlob(blob);

    html.AnchorElement(href: url)
      ..setAttribute(
        'download',
        'allocation_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      )
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  static Future<void> exportShortage(
    List<AllocationShortageExportRow> rows,
  ) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Allocation Shortage';

    const headers = ['Branch', 'Item Code', 'Item Name', 'Shortage Qty'];

    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.getRangeByIndex(1, c + 1);
      cell.setText(headers[c]);
      cell.cellStyle.bold = true;
      cell.cellStyle.fontColor = '#FFFFFF';
      cell.cellStyle.backColor = '#DC2626';
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.vAlign = xlsio.VAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      cell.cellStyle.borders.all.color = '#7F1D1D';
    }

    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      final values = [row.branch, row.itemCode, row.itemName, row.shortageQty];

      for (var c = 0; c < values.length; c++) {
        final cell = sheet.getRangeByIndex(r + 2, c + 1);
        final value = values[c];

        if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText(value.toString());
        }

        cell.cellStyle.hAlign = c == 2
            ? xlsio.HAlignType.left
            : xlsio.HAlignType.center;
        cell.cellStyle.vAlign = xlsio.VAlignType.center;
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        cell.cellStyle.borders.all.color = '#CBD5E1';

        if (r.isEven) {
          cell.cellStyle.backColor = '#FFF7ED';
        }
      }
    }

    sheet.getRangeByIndex(1, 1).columnWidth = 24;
    sheet.getRangeByIndex(1, 2).columnWidth = 18;
    sheet.getRangeByIndex(1, 3).columnWidth = 48;
    sheet.getRangeByIndex(1, 4).columnWidth = 16;

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final today = DateTime.now().toIso8601String().split('T').first;
    final blob = html.Blob([Uint8List.fromList(bytes)]);
    final url = html.Url.createObjectUrlFromBlob(blob);

    html.AnchorElement(href: url)
      ..setAttribute('download', 'Allocation Shortage $today.xlsx')
      ..click();

    html.Url.revokeObjectUrl(url);
  }
}
