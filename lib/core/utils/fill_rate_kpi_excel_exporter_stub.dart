import '../../data/datasources/remote/fill_rate_kpi_remote_ds.dart';

class FillRateKpiExcelExporter {
  static Future<void> export({
    required DateTime from,
    required DateTime to,
    required String branch,
    required FillRateReport report,
    required List<FillRateItem> items,
  }) {
    throw UnsupportedError('Fill Rate Excel export is available on web only.');
  }
}
