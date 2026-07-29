part of '../zone_manager_page.dart';

extension _ZoneOrderEditsPageView on _ZoneManagerPageState {
  Widget buildZoneOrderEditsPage() {
    final rows = _filtered(_edits, 'branch_name')..sort(_compareBranchItem);
    const columns = [
      _ColumnDef('branch_name', 'Branch'),
      _ColumnDef('item_code', 'Item Code'),
      _ColumnDef('item_name', 'Item Name'),
      _ColumnDef('old_qty', 'Original Qty'),
      _ColumnDef('new_qty', 'Edited Qty'),
      _ColumnDef('diff', 'Diff'),
      _ColumnDef('created_at', 'Edited At'),
    ];
    return _ReportPage(
      title: 'Order Edits',
      subtitle:
          'Every daily-order quantity change made by branches on ${_displayDate(widget.runDate)}.',
      accent: const Color(0xff2563EB),
      rows: rows,
      columns: columns,
      searchController: _search,
      onSearchChanged: _onSearchChanged,
      kpis: [
        _ReportKpi(
          Icons.edit_note_rounded,
          'Total Edits',
          '${rows.length}',
          'Changed daily-order lines',
          const Color(0xff2563EB),
        ),
        _ReportKpi(
          Icons.trending_up_rounded,
          'Quantity Increased',
          '${rows.where((row) => _number(row['diff']) > 0).length}',
          'Edits above original qty',
          const Color(0xff16A34A),
        ),
        _ReportKpi(
          Icons.trending_down_rounded,
          'Quantity Reduced',
          '${rows.where((row) => _number(row['diff']) < 0).length}',
          'Edits below original qty',
          const Color(0xffEF4444),
        ),
        _ReportKpi(
          Icons.schedule_rounded,
          'Last Edited',
          _latestActivity(rows, const ['created_at']),
          'Latest branch edit time',
          const Color(0xff7C3AED),
        ),
      ],
      onExport: () => _exportExcel('Order_Edits', rows, columns),
    );
  }
}
