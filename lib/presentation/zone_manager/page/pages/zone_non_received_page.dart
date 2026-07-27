part of '../zone_manager_page.dart';

extension _ZoneNonReceivedPageView on _ZoneManagerPageState {
  Widget buildZoneNonReceivedPage() {
    return _DownloadCenter(
      title: 'Non Received',
      subtitle:
          'Download the prepared Non Received Excel files. No heavy item table is loaded.',
      rows: _nonReceivedExports,
      zoneBranches: _branches.map((row) => _text(row['branch_name'])).toList(),
      accent: Colors.redAccent,
      onDownloadOne: (row) => _downloadExport(row, nonReceived: true),
      onDownloadSelection: (rows) =>
          _downloadExportBatch(rows, nonReceived: true),
    );
  }
}
