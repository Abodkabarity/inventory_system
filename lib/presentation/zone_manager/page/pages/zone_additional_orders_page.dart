part of '../zone_manager_page.dart';

extension _ZoneAdditionalOrdersPageView on _ZoneManagerPageState {
  Future<void> _pickAdditionalDateRange() async {
    final result = await showDialog<DateTimeRange>(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => AdditionalAnalysisDateRangePickerDialog(
        initialRange: DateTimeRange(start: _additionalFrom, end: _additionalTo),
      ),
    );
    if (result == null || !mounted) return;
    // The extension is scoped to the owning State and updates its report range.
    // ignore: invalid_use_of_protected_member
    setState(() {
      _additionalFrom = DateTime(
        result.start.year,
        result.start.month,
        result.start.day,
      );
      _additionalTo = DateTime(
        result.end.year,
        result.end.month,
        result.end.day,
        23,
        59,
        59,
      );
    });
    await _reloadAdditionalReport();
  }

  String _additionalRangeLabel() {
    final formatter = DateFormat('dd MMM yyyy');
    final from = formatter.format(_additionalFrom);
    final to = formatter.format(_additionalTo);
    return _dateKey(_additionalFrom) == _dateKey(_additionalTo)
        ? from
        : '$from  →  $to';
  }

  Widget buildZoneAdditionalOrdersPage() {
    final rows = _filtered(_additionalReport, 'branch_name');
    const columns = [
      _ColumnDef('branch_name', 'Branch'),
      _ColumnDef('item_code', 'Item Code'),
      _ColumnDef('item_name', 'Item Name'),
      _ColumnDef('request_qty', 'Requested'),
      _ColumnDef('inventory_qty', 'Inventory Confirm'),
      _ColumnDef('fulfilled_qty', 'Store Supply'),
      _ColumnDef('branch_stock', 'Branch Stock'),
      _ColumnDef('store_stock', 'Store Stock'),
      _ColumnDef('status', 'Status'),
      _ColumnDef('created_at', 'Created'),
    ];
    return Stack(
      children: [
        Positioned.fill(
          child: _ReportPage(
            title: 'Additional Orders',
            subtitle:
                'Requests and fulfillment status • ${_additionalRangeLabel()}.',
            accent: AppColors.primaryColor,
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
                      _additionalRangeLabel(),
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
                onPressed: _additionalReportLoading
                    ? null
                    : _pickAdditionalDateRange,
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
                Icons.receipt_long_rounded,
                'Total Requests',
                '${rows.length}',
                'Additional order lines',
                const Color(0xff2563EB),
              ),
              _ReportKpi(
                Icons.hourglass_top_rounded,
                'Pending',
                '${rows.where((row) => _statusContains(row, 'pending')).length}',
                'Awaiting action',
                const Color(0xffF59E0B),
              ),
              _ReportKpi(
                Icons.local_shipping_outlined,
                'Sent To Store',
                '${rows.where((row) => _statusContains(row, 'sent_to_store')).length}',
                'Approved and forwarded',
                const Color(0xff16A34A),
              ),
              _ReportKpi(
                Icons.cancel_outlined,
                'Rejected',
                '${rows.where((row) => _statusContains(row, 'reject')).length}',
                'Rejected requests',
                const Color(0xffEF4444),
              ),
            ],
            onExport: () => _exportExcel(
              'Additional_Orders_${_dateKey(_additionalFrom)}_${_dateKey(_additionalTo)}',
              rows,
              columns,
            ),
          ),
        ),
        if (_additionalReportLoading)
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
