part of '../zone_manager_page.dart';

extension _ZoneMismatchPageView on _ZoneManagerPageState {
  Widget buildZoneMismatchPage() {
    if (_reportLoading && _mismatch.isEmpty) {
      return const _ReportLoading(label: 'Loading mismatch report…');
    }
    final rows = _filtered(_mismatch, 'branch_name')..sort(_compareBranchItem);
    const columns = [
      _ColumnDef('branch_name', 'Branch'),
      _ColumnDef('item_code', 'Item Code'),
      _ColumnDef('item_name', 'Item Name'),
      _ColumnDef('system_stock', 'System Stock'),
      _ColumnDef('actual_stock', 'Actual Stock'),
      _ColumnDef('diff', 'Diff'),
      _ColumnDef('update_date', 'Updated'),
    ];
    return _ReportPage(
      title: 'Mismatch Report',
      subtitle: 'Current stock differences for branches in ${widget.zoneName}.',
      accent: const Color(0xffF97316),
      rows: rows,
      columns: columns,
      searchController: _search,
      onSearchChanged: _onSearchChanged,
      kpis: [
        _ReportKpi(
          Icons.inventory_2_outlined,
          'Total Mismatches',
          '${rows.length}',
          'Items with stock variance',
          const Color(0xff2563EB),
        ),
        _ReportKpi(
          Icons.trending_down_rounded,
          'Negative Diff',
          '${rows.where((row) => _number(row['diff']) < 0).length}',
          'Lower actual stock',
          const Color(0xffEF4444),
        ),
        _ReportKpi(
          Icons.trending_up_rounded,
          'Positive Diff',
          '${rows.where((row) => _number(row['diff']) > 0).length}',
          'Higher actual stock',
          const Color(0xff16A34A),
        ),
        _ReportKpi(
          Icons.schedule_rounded,
          'Last Updated',
          _latestActivity(rows, const ['update_date', 'created_at']),
          'Latest data refresh time',
          const Color(0xff7C3AED),
        ),
      ],
      onExport: () => _exportExcel('Mismatch_Report', rows, columns),
    );
  }
}
