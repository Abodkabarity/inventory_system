// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'stock_excel_report.dart';
import 'stock_check_kpi_export_worker.dart';

Future<void> saveExcel(StockExcelReport report, String fileName) async {
  final bytes = await StockCheckKpiExportWorker.build(
    summaryHeaders: const [],
    summaryWidths: const [],
    summaryRows: const [],
    detailHeaders: report.headers,
    detailWidths: report.widths,
    detailRows: report.values,
    totalRows: report.rows.length,
    job: KpiExportJob(),
    singleReport: true,
    sheetName: report.sheetName,
    columnTypes: report.types,
  );
  final url = html.Url.createObjectUrlFromBlob(
    html.Blob([
      bytes,
    ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
  );
  try {
    final anchor = html.AnchorElement(href: url)..download = fileName;
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    await Future<void>.delayed(const Duration(seconds: 1));
  } finally {
    html.Url.revokeObjectUrl(url);
  }
}
