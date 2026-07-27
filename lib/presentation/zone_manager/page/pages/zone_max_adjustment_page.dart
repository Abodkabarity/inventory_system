part of '../zone_manager_page.dart';

extension _ZoneMaxAdjustmentPageView on _ZoneManagerPageState {
  Widget buildZoneMaxAdjustmentPage() {
    if (_reportLoading && _maxAdj.isEmpty) {
      return const _ReportLoading(label: 'Loading max adjustments…');
    }
    final rows = _filtered(_maxAdj, 'branch_name')..sort(_compareBranchItem);
    const columns = [
      _ColumnDef('branch_name', 'Branch'),
      _ColumnDef('item_code', 'Item Code'),
      _ColumnDef('item_name', 'Item Name'),
      _ColumnDef('current_demand_30d', 'Demand'),
      _ColumnDef('max_adjustment_30d', 'Max Adj'),
      _ColumnDef('adjustment_type', 'Type'),
      _ColumnDef('qty', 'Qty'),
      _ColumnDef('reason', 'Reason'),
      _ColumnDef('update_date', 'Date'),
      _ColumnDef('added_by', 'Added By'),
    ];
    return _ReportPage(
      title: 'Max Adjustment',
      subtitle: 'All active maximum-stock adjustments for zone branches.',
      accent: const Color(0xffF97316),
      rows: rows,
      columns: columns,
      kpis: [
        _ReportKpi(
          Icons.tune_rounded,
          'Total Adjustments',
          '${rows.length}',
          'Active maximum changes',
          const Color(0xff2563EB),
        ),
        _ReportKpi(
          Icons.add_chart_rounded,
          'Increased Max',
          '${rows.where(_isPositiveMaxAdjustment).length}',
          'Upward stock adjustments',
          const Color(0xff16A34A),
        ),
        _ReportKpi(
          Icons.trending_down_rounded,
          'Reduced Max',
          '${rows.where(_isNegativeMaxAdjustment).length}',
          'Downward stock adjustments',
          const Color(0xffEF4444),
        ),
        _ReportKpi(
          Icons.schedule_rounded,
          'Last Updated',
          _latestActivity(rows, const ['update_date', 'created_at']),
          'Latest adjustment activity',
          const Color(0xff7C3AED),
        ),
      ],
      onExport: () => _exportExcel('Max_Adjustment', rows, columns),
    );
  }
}
