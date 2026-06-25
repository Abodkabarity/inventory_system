import 'dart:html' as html;
import 'dart:typed_data';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

class PurchaseShortageExcelExporter {
  static Future<void> export({
    required List<Map<String, dynamic>> rows,
    required List<Map<String, dynamic>> branchStockRows,
  }) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'TotalShortage';

    const headers = [
      'Item Code',
      'Item Name',
      'Branches Stock',
      'Category',
      'Supplier',
      'Store Stock',
      'Shortage',
      'UPP Shortage',
      'Assortment Items',
    ];

    _writeHeader(sheet, headers, '#002060');

    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      final values = [
        row['item_code'],
        row['item_name'],
        row['branches_stock'],
        row['category'],
        row['supplier'],
        row['store_stock'],
        row['shortage'],
        row['upp_shortage'] ?? '',
        row['assortment_items'],
      ];

      for (var c = 0; c < values.length; c++) {
        final cell = sheet.getRangeByIndex(r + 2, c + 1);
        final value = values[c];
        if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText(value?.toString() ?? '');
        }
        _styleBodyCell(cell);
      }
    }

    sheet.getRangeByIndex(1, 1, rows.length + 1, headers.length)
      ..autoFitColumns()
      ..cellStyle.vAlign = xlsio.VAlignType.center;

    final stockSheet = workbook.worksheets.addWithName('BRANCHES STOCK');
    const stockHeaders = ['Branch', 'Item Code', 'Item Name', 'Branch Stock'];
    _writeHeader(stockSheet, stockHeaders, '#0F766E');

    for (var r = 0; r < branchStockRows.length; r++) {
      final row = branchStockRows[r];
      final values = [
        row['branch'],
        row['item_code'],
        row['item_name'],
        row['branch_stock'],
      ];

      for (var c = 0; c < values.length; c++) {
        final cell = stockSheet.getRangeByIndex(r + 2, c + 1);
        final value = values[c];
        if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText(value?.toString() ?? '');
        }
        _styleBodyCell(cell);
      }
    }

    stockSheet.getRangeByIndex(
        1,
        1,
        branchStockRows.length + 1,
        stockHeaders.length,
      )
      ..autoFitColumns()
      ..cellStyle.vAlign = xlsio.VAlignType.center;

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final blob = html.Blob([
      Uint8List.fromList(bytes),
    ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    final url = html.Url.createObjectUrlFromBlob(blob);

    html.AnchorElement(href: url)
      ..setAttribute(
        'download',
        'TotalShortage_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      )
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  static void _writeHeader(
    xlsio.Worksheet sheet,
    List<String> headers,
    String color,
  ) {
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.getRangeByIndex(1, c + 1);
      cell.setText(headers[c]);
      cell.cellStyle.bold = true;
      cell.cellStyle.fontColor = '#FFFFFF';
      cell.cellStyle.backColor = color;
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.vAlign = xlsio.VAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
    }
  }

  static void _styleBodyCell(xlsio.Range cell) {
    cell.cellStyle.hAlign = xlsio.HAlignType.center;
    cell.cellStyle.vAlign = xlsio.VAlignType.center;
    cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
  }
}
