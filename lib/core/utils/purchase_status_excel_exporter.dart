// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'package:intl/intl.dart';

import '../../domain/entities/purchase_status_record.dart';
import 'purchase_status_excel_workbook.dart';

class PurchaseStatusExcelExporter {
  static Future<void> export(
    List<PurchaseStatusRecord> records,
    List<PurchaseStatusOption> statuses,
  ) async {
    final bytes = await PurchaseStatusExcelWorkbook.build(records, statuses);
    final blob = html.Blob([
      bytes,
    ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final fileDate = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
    html.AnchorElement(href: url)
      ..setAttribute('download', 'Purchase_Status_$fileDate.xlsx')
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}
