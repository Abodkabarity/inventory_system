// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../../data/datasources/remote/fill_rate_kpi_remote_ds.dart';
import 'fill_rate_kpi_excel_builder.dart';

class FillRateKpiExcelExporter {
  static Future<void> export({
    required DateTime from,
    required DateTime to,
    required String branch,
    required FillRateReport report,
    required List<FillRateItem> items,
  }) async {
    final bytes = FillRateKpiExcelBuilder.build(
      from: from,
      to: to,
      branch: branch,
      report: report,
      items: items,
    );
    final blob = html.Blob([
      Uint8List.fromList(bytes),
    ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final dates = '${_date(from)}_${_date(to)}';
    final safeBranch = branch.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    html.AnchorElement(href: url)
      ..setAttribute('download', 'Fill_Rate_KPI_${safeBranch}_$dates.xlsx')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  static String _date(DateTime value) => DateFormat('yyyy-MM-dd').format(value);
}
