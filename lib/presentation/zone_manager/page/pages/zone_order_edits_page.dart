part of '../zone_manager_page.dart';

extension _ZoneOrderEditsPageView on _ZoneManagerPageState {
  Future<void> _pickOrderEditsDateRange() async {
    final result = await showDialog<DateTimeRange>(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => AdditionalAnalysisDateRangePickerDialog(
        initialRange: DateTimeRange(start: _editsFrom, end: _editsTo),
      ),
    );
    if (result == null || !mounted) return;
    // The extension is scoped to the owning State and updates its report range.
    // ignore: invalid_use_of_protected_member
    setState(() {
      _editsFrom = DateTime(
        result.start.year,
        result.start.month,
        result.start.day,
      );
      _editsTo = DateTime(
        result.end.year,
        result.end.month,
        result.end.day,
        23,
        59,
        59,
      );
    });
    await _reloadEditsReport();
  }

  String _orderEditsRangeLabel() {
    final formatter = DateFormat('dd MMM yyyy');
    final from = formatter.format(_editsFrom);
    final to = formatter.format(_editsTo);
    return _dateKey(_editsFrom) == _dateKey(_editsTo) ? from : '$from  →  $to';
  }

  Widget buildZoneOrderEditsPage() {
    final rows = _filtered(_editsReport, 'branch_name')
      ..sort(_compareBranchItem);
    const columns = [
      _ColumnDef('branch_name', 'Branch'),
      _ColumnDef('item_code', 'Item Code'),
      _ColumnDef('item_name', 'Item Name'),
      _ColumnDef('old_qty', 'Original Qty'),
      _ColumnDef('new_qty', 'Edited Qty'),
      _ColumnDef('diff', 'Diff'),
      _ColumnDef('created_at', 'Edited At'),
    ];
    return Stack(
      children: [
        Positioned.fill(
          child: _ReportPage(
            title: 'Order Edits',
            subtitle:
                'Every daily-order quantity change made by zone branches • ${_orderEditsRangeLabel()}.',
            accent: const Color(0xff2563EB),
            rows: rows,
            columns: columns,
            searchController: _search,
            onSearchChanged: _onSearchChanged,
            extraActions: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xffF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xffE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 15,
                      color: Color(0xff64748B),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _orderEditsRangeLabel(),
                      style: const TextStyle(
                        color: Color(0xff64748B),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _editsReportLoading
                    ? null
                    : _pickOrderEditsDateRange,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xff06B6D4),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xffBAE6FD),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.date_range_rounded, size: 18),
                label: const Text(
                  'Date Range',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
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
            onExport: () => _exportExcel(
              'Order_Edits_${_dateKey(_editsFrom)}_${_dateKey(_editsTo)}',
              rows,
              columns,
            ),
          ),
        ),
        if (_editsReportLoading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: const LinearProgressIndicator(
                minHeight: 3,
                color: Color(0xff06B6D4),
                backgroundColor: Color(0xffCFFAFE),
              ),
            ),
          ),
      ],
    );
  }
}
