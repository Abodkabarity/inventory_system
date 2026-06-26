import 'dart:html' as html;

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

class PurchaseShortageExcelExporter {
  static Future<void> export({
    required List<Map<String, dynamic>> rows,
    required List<Map<String, dynamic>> branchStockMatrixRows,
    void Function(int rowsWritten, int totalRows)? onBranchStockProgress,
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
      sheet.importList(
        [
          row['item_code'],
          row['item_name'],
          row['branches_stock'],
          row['category'],
          row['supplier'],
          row['store_stock'],
          row['shortage'],
          row['upp_shortage'] ?? '',
          row['assortment_items'],
        ],
        r + 2,
        1,
        false,
      );

      if (r % 500 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    _styleSheet(sheet, rows.length + 1, headers.length);
    _setWidths(sheet, [17, 42, 16, 24, 34, 14, 13, 15, 30]);

    await _writeBranchStockListSheet(
      workbook,
      branchStockMatrixRows,
      onBranchStockProgress,
    );

    await Future<void>.delayed(Duration.zero);

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    _downloadBlob(
      html.Blob([
        bytes,
      ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
      'Items Shortage Include Assortment ${_downloadDate()}.xlsx',
    );
  }

  static Future<void> _writeBranchStockListSheet(
    xlsio.Workbook workbook,
    List<Map<String, dynamic>> matrixRows,
    void Function(int rowsWritten, int totalRows)? onProgress,
  ) async {
    final branches = <String>{};
    for (final row in matrixRows) {
      final stocks = row['stocks'];
      if (stocks is Map) {
        branches.addAll(stocks.keys.map((key) => key.toString()));
      }
    }

    final branchList = branches.toList()..sort();
    const headers = ['Branch', 'Item Code', 'Item Name', 'Branch Stock'];
    final totalRows = matrixRows.length * branchList.length;
    onProgress?.call(0, totalRows);

    var sheetIndex = 1;
    var dataRowsInSheet = 0;
    var totalRowsWritten = 0;
    var sheet = _createStockListSheet(workbook, sheetIndex, headers);

    for (final row in matrixRows) {
      final itemCode = row['item_code'];
      final itemName = row['item_name'];
      final stocks = row['stocks'] is Map ? row['stocks'] as Map : const {};

      for (final branch in branchList) {
        final stock = stocks[branch] ?? 0;

        if (dataRowsInSheet >= _maxDataRowsPerSheet) {
          _styleCompactSheet(sheet, dataRowsInSheet + 1, headers.length);
          sheetIndex++;
          dataRowsInSheet = 0;
          sheet = _createStockListSheet(workbook, sheetIndex, headers);
        }

        sheet.importList(
          [branch, itemCode, itemName, stock],
          dataRowsInSheet + 2,
          1,
          false,
        );
        dataRowsInSheet++;
        totalRowsWritten++;

        if (totalRowsWritten % 50000 == 0) {
          onProgress?.call(totalRowsWritten, totalRows);
          await Future<void>.delayed(Duration.zero);
        }
      }
    }

    _styleCompactSheet(sheet, dataRowsInSheet + 1, headers.length);
    onProgress?.call(totalRowsWritten, totalRows);
  }

  static const int _maxExcelRows = 1048576;
  static const int _maxDataRowsPerSheet = _maxExcelRows - 1;

  static xlsio.Worksheet _createStockListSheet(
    xlsio.Workbook workbook,
    int index,
    List<String> headers,
  ) {
    final sheetName = index == 1
        ? 'BRANCHES STOCK LIST'
        : 'BRANCHES STOCK LIST $index';
    final sheet = workbook.worksheets.addWithName(sheetName);
    _writeHeader(sheet, headers, '#0F766E');
    _setWidths(sheet, [24, 17, 46, 15]);
    return sheet;
  }

  static void _downloadBlob(html.Blob blob, String fileName) {
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  static String _downloadDate() {
    final now = DateTime.now();
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    return '$day-$month-${now.year}';
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

  static void _styleSheet(xlsio.Worksheet sheet, int lastRow, int lastColumn) {
    final range = sheet.getRangeByIndex(1, 1, lastRow, lastColumn);
    range.cellStyle.hAlign = xlsio.HAlignType.center;
    range.cellStyle.vAlign = xlsio.VAlignType.center;
    range.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
    range.cellStyle.borders.all.color = '#CBD5E1';
  }

  static void _styleCompactSheet(
    xlsio.Worksheet sheet,
    int lastRow,
    int lastColumn,
  ) {
    if (lastRow <= 1) return;
    if (lastRow > 100000) return;

    final range = sheet.getRangeByIndex(1, 1, lastRow, lastColumn);
    range.cellStyle.hAlign = xlsio.HAlignType.center;
    range.cellStyle.vAlign = xlsio.VAlignType.center;

    range.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
    range.cellStyle.borders.all.color = '#CBD5E1';
  }

  static void _setWidths(xlsio.Worksheet sheet, List<double> widths) {
    for (var i = 0; i < widths.length; i++) {
      sheet.getRangeByIndex(1, i + 1).columnWidth = widths[i];
    }
  }
}
