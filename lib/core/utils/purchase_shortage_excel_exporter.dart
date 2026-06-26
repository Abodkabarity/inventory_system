import 'dart:html' as html;

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

class PurchaseShortageExcelExporter {
  static Future<void> export({
    required List<Map<String, dynamic>> rows,
    required List<Map<String, dynamic>> branchStockMatrixRows,
    void Function(int rowsWritten, int totalRows)? onBranchStockProgress,
  }) async {
    final workbook = xlsio.Workbook();

    // ------------------------------------------------------------
    // 1. SHEET 1: TotalShortage (980 rows)
    // ------------------------------------------------------------
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

    _writeHeaderWithStyle(sheet, headers, '#002060');

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

      // Yield event loop occasionally during small sheet export
      if (r % 500 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    _styleDataSheet(sheet, rows.length + 1, headers.length);
    _setColumnWidths(sheet, [17, 42, 16, 24, 34, 14, 13, 15, 30]);

    // ------------------------------------------------------------
    // 2. SHEET 2: Branches Stock List (888,000 rows)
    // ------------------------------------------------------------
    await _writeBranchStockListSheetFast(
      workbook,
      branchStockMatrixRows,
      onBranchStockProgress,
    );

    await Future<void>.delayed(Duration.zero);

    // Save and dispose workbook safely
    final bytes = workbook.saveAsStream();
    workbook.dispose();

    _downloadBlob(
      html.Blob([
        bytes,
      ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
      'Items Shortage Include Assortment ${_downloadDate()}.xlsx',
    );
  }

  /// FAST SHEET WRITER FOR MASSIVE DATASET (888,000+ rows)
  /// Optimizations applied:
  /// - ZERO Cell styling (keeps workbook memory extremely lightweight)
  /// - Periodic Event Loop Yielding (await Future.delayed) to prevent page freeze
  /// - Garbage collection safety triggers
  static Future<void> _writeBranchStockListSheetFast(
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

    final sheet = workbook.worksheets.addWithName('BRANCHES STOCK LIST');

    // Headers
    for (var c = 0; c < headers.length; c++) {
      sheet.getRangeByIndex(1, c + 1).setText(headers[c]);
    }

    sheet.getRangeByIndex(1, 1).columnWidth = 18;
    sheet.getRangeByIndex(1, 2).columnWidth = 16;
    sheet.getRangeByIndex(1, 3).columnWidth = 40;
    sheet.getRangeByIndex(1, 4).columnWidth = 14;

    var dataRowIndex = 2;
    var totalRowsWritten = 0;

    for (final row in matrixRows) {
      final itemCode = row['item_code'];
      final itemName = row['item_name'];
      final stocks = row['stocks'] is Map ? row['stocks'] as Map : const {};

      for (final branch in branchList) {
        final stock = stocks[branch] ?? 0;

        // Pure values - absolutely zero style configuration
        sheet.getRangeByIndex(dataRowIndex, 1).setText(branch.toString());
        sheet.getRangeByIndex(dataRowIndex, 2).setText(itemCode.toString());
        sheet.getRangeByIndex(dataRowIndex, 3).setText(itemName.toString());
        sheet
            .getRangeByIndex(dataRowIndex, 4)
            .setNumber(_parseNum(stock).toDouble());

        dataRowIndex++;
        totalRowsWritten++;

        // CRITICAL: Yield thread every 50,000 rows to prevent event-loop lock and maximize writing speed!
        if (totalRowsWritten % 50000 == 0) {
          onProgress?.call(totalRowsWritten, totalRows);
          await Future<void>.delayed(
            Duration.zero,
          ); // yields to browser UI scheduler
        }
      }
    }

    onProgress?.call(totalRowsWritten, totalRows);
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
    return '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
  }

  static void _writeHeaderWithStyle(
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
    }
  }

  static void _styleDataSheet(
    xlsio.Worksheet sheet,
    int lastRow,
    int lastColumn,
  ) {
    if (lastRow > 15000)
      return; // Completely disabled for bulk worksheets to prevent memory exhaustion
    try {
      final range = sheet.getRangeByIndex(1, 1, lastRow, lastColumn);
      range.cellStyle.hAlign = xlsio.HAlignType.center;
      range.cellStyle.vAlign = xlsio.VAlignType.center;
    } catch (_) {}
  }

  static void _setColumnWidths(xlsio.Worksheet sheet, List<double> widths) {
    for (var i = 0; i < widths.length; i++) {
      try {
        sheet.getRangeByIndex(1, i + 1).columnWidth = widths[i];
      } catch (_) {}
    }
  }

  static num _parseNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse(value.toString()) ?? 0;
  }
}
