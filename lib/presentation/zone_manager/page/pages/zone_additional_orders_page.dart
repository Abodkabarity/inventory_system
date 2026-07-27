part of '../zone_manager_page.dart';

extension _ZoneAdditionalOrdersPageView on _ZoneManagerPageState {
  Widget buildZoneAdditionalOrdersPage() {
    final rows = _filtered(_additional, 'branch_name');
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
    return _ReportPage(
      title: 'Additional Orders',
      subtitle:
          'Requests and fulfillment status for the selected zone branches.',
      accent: AppColors.primaryColor,
      rows: rows,
      columns: columns,
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
      onExport: () => _exportExcel('Additional_Orders', rows, columns),
    );
  }
}
