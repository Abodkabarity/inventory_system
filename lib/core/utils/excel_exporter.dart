import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';

class ExcelExporter {
  static Future<String> exportRowsToExcel({
    required List<Map<String, dynamic>> rows,
    required List<String> columns,
    String sheetName = 'Export',
    String fileName = 'table_export.xlsx',
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel[sheetName];

    // Header row
    sheet.appendRow(columns.map((c) => TextCellValue(c)).toList());

    // Data rows
    for (final r in rows) {
      final rowValues = columns.map((c) {
        final v = r[c];
        if (v == null) return TextCellValue('');
        final s = v.toString();
        return TextCellValue(s);
      }).toList();

      sheet.appendRow(rowValues);
    }

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to encode excel');

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    return file.path;
  }
}
