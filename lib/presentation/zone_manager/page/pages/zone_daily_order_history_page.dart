part of '../zone_manager_page.dart';

extension _ZoneDailyOrderHistoryPageView on _ZoneManagerPageState {
  Widget buildZoneDailyOrderHistoryPage() {
    return _DownloadCenter(
      title: 'Daily Order History',
      subtitle:
          'Choose an order date and download one branch or one ZIP for every branch in the zone.',
      rows: _dailyExports,
      zoneBranches: _branches.map((row) => _text(row['branch_name'])).toList(),
      accent: AppColors.primaryColor,
      onDownloadOne: (row) => _downloadExport(row, nonReceived: false),
      onDownloadSelection: (rows) =>
          _downloadExportBatch(rows, nonReceived: false),
    );
  }
}
