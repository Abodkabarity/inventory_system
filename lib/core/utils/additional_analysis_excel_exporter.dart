import 'dart:html' as html;
import 'dart:typed_data';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

class AdditionalAnalysisExcelExporter {
  static Future<void> exportOverview({
    required Map<String, dynamic> data,
    required DateTime from,
    required DateTime to,
  }) async {
    final workbook = xlsio.Workbook();
    workbook.worksheets[0].name = 'Executive Summary';

    final summaryRows = [
      ['Metric', 'Value'],
      ['Total Requests', data['total_requests'] ?? 0],
      ['Total Quantity', data['total_qty'] ?? 0],
      ['Unique Products', data['unique_products'] ?? 0],
      ['Unique Branches', data['unique_branches'] ?? 0],
      ['Branch Request Rate %', data['active_branch_rate'] ?? 0],
      ['Completion Rate %', data['completion_rate'] ?? 0],
      ['Rejection Rate %', data['rejection_rate'] ?? 0],
      ['Average Quantity', data['avg_qty'] ?? 0],
    ];

    _buildIntro(
      workbook.worksheets[0],
      title: 'Additional Orders Overview Report',
      from: from,
      to: to,
      subtitle:
          'Executive report for additional order requests, completion, rejection, branches, products, and request patterns.',
    );
    _writeTable(workbook.worksheets[0], 6, summaryRows);

    _addMapSheet(
      workbook,
      name: 'Branch Requests',
      title: 'Branch Request Summary',
      rows: _list(data['top_branches']),
      columns: const [
        _ColumnSpec('branch_name', 'Branch'),
        _ColumnSpec('requests', 'Requests'),
        _ColumnSpec('qty', 'Quantity'),
      ],
      from: from,
      to: to,
    );

    _addMapSheet(
      workbook,
      name: 'Product Requests',
      title: 'Most Requested Products',
      rows: _list(data['top_products']),
      columns: const [
        _ColumnSpec('item_code', 'Item Code'),
        _ColumnSpec('item_name', 'Item Name'),
        _ColumnSpec('requests', 'Requests'),
        _ColumnSpec('qty', 'Quantity'),
      ],
      from: from,
      to: to,
    );

    _addMapSheet(
      workbook,
      name: 'Branch Performance',
      title: 'Branch Performance',
      rows: _list(data['branch_performance']),
      columns: const [
        _ColumnSpec('branch_name', 'Branch'),
        _ColumnSpec('requests', 'Requests'),
        _ColumnSpec('qty', 'Quantity'),
        _ColumnSpec('done', 'Done'),
        _ColumnSpec('rejected', 'Rejected'),
        _ColumnSpec('completion_rate', 'Completion Rate %'),
      ],
      from: from,
      to: to,
    );

    _addMapSheet(
      workbook,
      name: 'Status Distribution',
      title: 'Status Distribution',
      rows: _list(data['status_distribution']),
      columns: const [
        _ColumnSpec('status', 'Status'),
        _ColumnSpec('count', 'Count'),
        _ColumnSpec('percent', 'Percent %'),
      ],
      from: from,
      to: to,
    );

    _addMapSheet(
      workbook,
      name: 'Reasons',
      title: 'Most Common Reasons',
      rows: _list(data['reasons']),
      columns: const [
        _ColumnSpec('reason', 'Reason'),
        _ColumnSpec('count', 'Count'),
        _ColumnSpec('percent', 'Percent %'),
      ],
      from: from,
      to: to,
    );

    _addMapSheet(
      workbook,
      name: 'Purchase Types',
      title: 'Purchase Type Breakdown',
      rows: _list(data['purchase_types']),
      columns: const [
        _ColumnSpec('item_purchase_type', 'Purchase Type'),
        _ColumnSpec('requests', 'Requests'),
        _ColumnSpec('qty', 'Quantity'),
        _ColumnSpec('percent', 'Percent %'),
      ],
      from: from,
      to: to,
    );

    _download(
      workbook,
      'Additional_Orders_Overview_${_formatDate(from)}_${_formatDate(to)}.xlsx',
    );
  }

  static Future<void> exportSalesPerformance({
    required Map<String, dynamic> data,
    required DateTime from,
    required DateTime to,
    String? branch,
    String search = '',
    String statusFilter = 'all',
  }) async {
    final workbook = xlsio.Workbook();
    workbook.worksheets[0].name = 'Sales Summary';

    final summary = Map<String, dynamic>.from(data['summary'] as Map? ?? {});
    _buildIntro(
      workbook.worksheets[0],
      title: 'Additional Orders Sales Performance',
      from: from,
      to: to,
      subtitle:
          'Detailed sales follow-up showing which additional requests sold, sold late, or did not sell.',
      extraLines: [
        ['Branch Filter', branch ?? 'All Branches'],
        ['Status Filter', _effectivenessLabel(statusFilter)],
        ['Search', search.trim().isEmpty ? 'All' : search.trim()],
      ],
    );

    _writeTable(workbook.worksheets[0], 9, [
      ['Metric', 'Value'],
      ['Total Requests', summary['total_requests'] ?? 0],
      ['Sold Within 3 Days', summary['sold_within_3d'] ?? 0],
      ['Sold After 3 Days', summary['sold_after_3d'] ?? 0],
      ['Not Sold', summary['not_sold'] ?? 0],
      ['Sales Success Rate %', summary['effectiveness_rate'] ?? 0],
      ['Quick Sell Rate %', summary['quick_sell_rate'] ?? 0],
      ['Average Days To First Sale', summary['avg_days_to_first_sale'] ?? ''],
      ['Average Sold %', summary['avg_sold_pct'] ?? 0],
    ]);

    _addMapSheet(
      workbook,
      name: 'Branch Sales',
      title: 'Branch Sales Success',
      rows: _list(data['branch_effectiveness']),
      columns: const [
        _ColumnSpec('branch_name', 'Branch'),
        _ColumnSpec('total_requests', 'Requests'),
        _ColumnSpec('sold_within_3d', 'Sold <= 3 Days'),
        _ColumnSpec('sold_after_3d', 'Sold > 3 Days'),
        _ColumnSpec('not_sold', 'Not Sold'),
        _ColumnSpec('effectiveness_rate', 'Success Rate %'),
        _ColumnSpec('quick_sell_rate', 'Quick Sell Rate %'),
        _ColumnSpec('avg_days_to_first_sale', 'Avg Days To Sale'),
      ],
      from: from,
      to: to,
    );

    _addMapSheet(
      workbook,
      name: 'Product Sales',
      title: 'Product Sales Effectiveness',
      rows: _list(data['product_effectiveness']),
      columns: const [
        _ColumnSpec('item_code', 'Item Code'),
        _ColumnSpec('item_name', 'Item Name'),
        _ColumnSpec('total_requests', 'Requests'),
        _ColumnSpec('total_request_qty', 'Request Qty'),
        _ColumnSpec('total_sold_qty', 'Sold Qty'),
        _ColumnSpec('sold_within_3d', 'Sold <= 3 Days'),
        _ColumnSpec('sold_after_3d', 'Sold > 3 Days'),
        _ColumnSpec('not_sold', 'Not Sold'),
        _ColumnSpec('effectiveness_rate', 'Success Rate %'),
        _ColumnSpec('sold_pct', 'Sold Qty %'),
      ],
      from: from,
      to: to,
    );

    _addMapSheet(
      workbook,
      name: 'Request Details',
      title: 'Request-Level Sales Details',
      rows: _list(data['rows']),
      columns: const [
        _ColumnSpec('request_date', 'Request Date'),
        _ColumnSpec('branch_name', 'Branch'),
        _ColumnSpec('item_code', 'Item Code'),
        _ColumnSpec('item_name', 'Item Name'),
        _ColumnSpec('request_qty', 'Request Qty'),
        _ColumnSpec('total_sold_qty', 'Sold Qty'),
        _ColumnSpec('sold_pct', 'Sold %'),
        _ColumnSpec('effectiveness_label', 'Result'),
        _ColumnSpec('days_to_first_sale', 'Days To First Sale'),
        _ColumnSpec('days_without_sale', 'Days Without Sale'),
        _ColumnSpec('selling_days', 'Selling Days'),
        _ColumnSpec('status', 'Request Status'),
      ],
      from: from,
      to: to,
    );

    _addMapSheet(
      workbook,
      name: 'Weekly Trend',
      title: 'Weekly Sales Trend',
      rows: _list(data['weekly_trend']),
      columns: const [
        _ColumnSpec('week', 'Week'),
        _ColumnSpec('total', 'Requests'),
        _ColumnSpec('sold_3d', 'Sold <= 3 Days'),
        _ColumnSpec('sold_after_3d', 'Sold > 3 Days'),
        _ColumnSpec('not_sold', 'Not Sold'),
        _ColumnSpec('effectiveness_rate', 'Success Rate %'),
      ],
      from: from,
      to: to,
    );

    _download(
      workbook,
      'Additional_Orders_Sales_Performance_${_formatDate(from)}_${_formatDate(to)}.xlsx',
    );
  }

  static void _buildIntro(
    xlsio.Worksheet sheet, {
    required String title,
    required DateTime from,
    required DateTime to,
    required String subtitle,
    List<List<Object?>> extraLines = const [],
  }) {
    sheet.getRangeByIndex(1, 1).setText(title);
    sheet.getRangeByIndex(1, 1, 1, 6).merge();
    final titleCell = sheet.getRangeByIndex(1, 1);
    titleCell.cellStyle.bold = true;
    titleCell.cellStyle.fontSize = 18;
    titleCell.cellStyle.fontColor = '#0F172A';

    sheet.getRangeByIndex(2, 1).setText(subtitle);
    sheet.getRangeByIndex(2, 1, 2, 6).merge();
    sheet.getRangeByIndex(2, 1).cellStyle.fontColor = '#475569';

    final lines = [
      ['Date Range', '${_formatDate(from)} -> ${_formatDate(to)}'],
      ['Generated At', _formatDateTime(DateTime.now())],
      ...extraLines,
    ];

    for (var i = 0; i < lines.length; i++) {
      final row = i + 3;
      sheet.getRangeByIndex(row, 1).setText(lines[i][0].toString());
      sheet.getRangeByIndex(row, 2).setText(lines[i][1].toString());
      sheet.getRangeByIndex(row, 1).cellStyle.bold = true;
      sheet.getRangeByIndex(row, 1).cellStyle.fontColor = '#475569';
    }
  }

  static void _addMapSheet(
    xlsio.Workbook workbook, {
    required String name,
    required String title,
    required List<Map<String, dynamic>> rows,
    required List<_ColumnSpec> columns,
    required DateTime from,
    required DateTime to,
  }) {
    final sheet = workbook.worksheets.addWithName(name);
    _buildIntro(
      sheet,
      title: title,
      from: from,
      to: to,
      subtitle: 'Rows: ${rows.length}',
    );

    final table = <List<Object?>>[
      columns.map((e) => e.title).toList(),
      ...rows.map((row) => columns.map((col) => row[col.key] ?? '').toList()),
    ];

    _writeTable(sheet, 6, table);
  }

  static void _writeTable(
    xlsio.Worksheet sheet,
    int startRow,
    List<List<Object?>> rows,
  ) {
    if (rows.isEmpty) return;

    final header = rows.first;
    for (var c = 0; c < header.length; c++) {
      final cell = sheet.getRangeByIndex(startRow, c + 1);
      cell.setText(header[c].toString());
      cell.cellStyle.bold = true;
      cell.cellStyle.fontColor = '#FFFFFF';
      cell.cellStyle.backColor = '#0F6CBD';
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.vAlign = xlsio.VAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      cell.cellStyle.borders.all.color = '#1E3A8A';
    }

    for (var r = 1; r < rows.length; r++) {
      final values = rows[r];
      for (var c = 0; c < values.length; c++) {
        final cell = sheet.getRangeByIndex(startRow + r, c + 1);
        final value = values[c];
        if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText((value ?? '').toString());
        }
        cell.cellStyle.vAlign = xlsio.VAlignType.center;
        cell.cellStyle.hAlign = value is num
            ? xlsio.HAlignType.center
            : xlsio.HAlignType.left;
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        cell.cellStyle.borders.all.color = '#CBD5E1';
        if (r.isOdd) cell.cellStyle.backColor = '#F8FAFC';
      }
    }

    final lastRow = startRow + rows.length;
    sheet.getRangeByIndex(1, 1, lastRow, header.length).autoFitColumns();
    sheet.getRangeByIndex(1, 1, lastRow, header.length).rowHeight = 22;
  }

  static void _download(xlsio.Workbook workbook, String fileName) {
    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final blob = html.Blob([Uint8List.fromList(bytes)]);
    final url = html.Url.createObjectUrlFromBlob(blob);

    html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  static List<Map<String, dynamic>> _list(dynamic value) {
    return List<Map<String, dynamic>>.from(value as List? ?? const []);
  }

  static String _effectivenessLabel(String value) {
    switch (value) {
      case 'sold_within_3d':
        return 'Sold Within 3 Days';
      case 'sold_after_3d':
        return 'Sold After 3 Days';
      case 'not_sold':
        return 'Not Sold';
      default:
        return 'All';
    }
  }

  static String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _formatDateTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${_formatDate(date)} $hour:$minute';
  }
}

class _ColumnSpec {
  final String key;
  final String title;

  const _ColumnSpec(this.key, this.title);
}
