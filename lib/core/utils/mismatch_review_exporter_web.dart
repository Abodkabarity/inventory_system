// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'store_branch_identity_registry.dart';

class MismatchReviewExporter {
  static Future<void> export(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    final workbook = xlsio.Workbook();
    try {
      final sheet = workbook.worksheets[0];
      sheet.name = 'Mismatch review';
      final columns = rows.first.keys.toList();
      for (var c = 0; c < columns.length; c++) {
        sheet.getRangeByIndex(1, c + 1).setText(columns[c]);
        sheet.getRangeByIndex(1, c + 1).cellStyle.bold = true;
        sheet.getRangeByIndex(1, c + 1).cellStyle.backColor = '#E9F1F6';
        sheet.getRangeByIndex(1, c + 1).columnWidth = columns[c] == 'item_name'
            ? 45
            : 24;
      }
      for (var r = 0; r < rows.length; r++) {
        if (r % 250 == 0) await Future<void>.delayed(Duration.zero);
        for (var c = 0; c < columns.length; c++) {
          final v = StoreBranchIdentityRegistry.exportValue(
            columns[c],
            rows[r][columns[c]],
          );
          final cell = sheet.getRangeByIndex(r + 2, c + 1);
          if (v is num) {
            cell.setNumber(v.toDouble());
          } else {
            cell.setText(v?.toString() ?? '');
          }
        }
      }
      final bytes = await workbook.save();
      final url = html.Url.createObjectUrlFromBlob(
        html.Blob([
          bytes,
        ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
      );
      html.AnchorElement(href: url)
        ..download =
            'Mismatch_Review_${DateTime.now().millisecondsSinceEpoch}.xlsx'
        ..click();
      html.Url.revokeObjectUrl(url);
    } finally {
      workbook.dispose();
    }
  }
}
