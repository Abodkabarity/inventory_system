import 'dart:async';
import 'dart:html' as html;

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

class PurchaseShortageExcelExporter {
  static Future<void> export({
    required List<Map<String, dynamic>> rows,
    required Future<int> Function(
      FutureOr<void> Function(Map<String, dynamic> row) onRow,
    )
    loadBranchStockRows,
    void Function(int rowsWritten, int totalRows)? onBranchStockProgress,
  }) async {
    onBranchStockProgress?.call(0, 0);
    await _exportShortageWorkbook(rows);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _exportBranchStockCsv(loadBranchStockRows, onBranchStockProgress);
  }

  static Future<void> _exportShortageWorkbook(
    List<Map<String, dynamic>> rows,
  ) async {
    final workbook = xlsio.Workbook();

    // ------------------------------------------------------------
    // SHEET 1: TotalShortage
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

  static Future<void> _exportBranchStockCsv(
    Future<int> Function(
      FutureOr<void> Function(Map<String, dynamic> row) onRow,
    )
    loadBranchStockRows,
    void Function(int rowsWritten, int totalRows)? onProgress,
  ) async {
    final parts = <String>['\uFEFFBranch,Item Code,Item Name,Branch Stock\r\n'];
    final buffer = StringBuffer();
    var totalRowsWritten = 0;

    await loadBranchStockRows((row) async {
      buffer
        ..write(_csv(row['branch']))
        ..write(',')
        ..write(_csv(row['item_code']))
        ..write(',')
        ..write(_csv(row['item_name']))
        ..write(',')
        ..write(_csv(_parseNum(row['branch_stock'])))
        ..write('\r\n');

      totalRowsWritten++;

      if (totalRowsWritten % 10000 == 0) {
        parts.add(buffer.toString());
        buffer.clear();
      }

      if (totalRowsWritten % 50000 == 0) {
        onProgress?.call(totalRowsWritten, 0);
        await Future<void>.delayed(Duration.zero);
      }
    });

    if (buffer.isNotEmpty) {
      parts.add(buffer.toString());
    }

    onProgress?.call(totalRowsWritten, totalRowsWritten);
    _downloadBlob(
      html.Blob(parts, 'text/csv;charset=utf-8'),
      'Branches Stock ${_downloadDate()}.csv',
    );
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
    if (lastRow > 15000) {
      return; // Completely disabled for bulk worksheets to prevent memory exhaustion
    }
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

  static String _csv(dynamic value) {
    final text = value?.toString() ?? '';
    if (!text.contains(',') &&
        !text.contains('"') &&
        !text.contains('\n') &&
        !text.contains('\r')) {
      return text;
    }
    return '"${text.replaceAll('"', '""')}"';
  }
}
