// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'package:intl/intl.dart';
import '../../domain/entities/items_tracker_record.dart';
import 'items_tracker_excel_workbook.dart';

class ItemsTrackerExcelExporter {
  static Future<void> export(
    List<ItemsTrackerRecord> records, {
    required String role,
  }) async {
    final bytes = await ItemsTrackerExcelWorkbook.build(records, role: role);
    final blob = html.Blob([
      bytes,
    ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    html.AnchorElement(href: url)
      ..setAttribute('download', 'Items_Tracker_$timestamp.xlsx')
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}
