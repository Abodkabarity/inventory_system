import 'dart:html' as html;
import 'dart:typed_data';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

class OrderEditAnalysisExcelExporter {
  static Future<void> export({
    required Map<String, dynamic> data,
    required DateTime from,
    required DateTime to,
    String branch = 'All Branches',
    String search = '',
  }) async {
    final workbook = xlsio.Workbook();
    final summary = workbook.worksheets[0];
    summary.name = 'Summary';

    _intro(summary, 'Order Edit Increase Analysis', from, to, [
      ['Branch Filter', branch],
      ['Search', search.trim().isEmpty ? 'All' : search.trim()],
      ['Rule', 'Only order_edits rows where diff > 0'],
    ]);

    _writeTable(summary, 8, [
      ['Metric', 'Value'],
      ['Total Edits', data['total_edits'] ?? data['total_requests'] ?? 0],
      ['Total Added Qty', data['total_qty'] ?? 0],
      ['Unique Products', data['unique_products'] ?? 0],
      ['Unique Branches', data['unique_branches'] ?? 0],
      ['Average Added Qty', data['avg_qty'] ?? 0],
      ['Largest Single Addition', data['max_addition'] ?? 0],
    ]);

    _sheet(
      workbook,
      name: 'Branches',
      title: 'Branch Added Quantity',
      from: from,
      to: to,
      rows: _list(data['branch_export_rows'] ?? data['top_branches']),
      columns: const [
        _Column('branch_name', 'Branch'),
        _Column('orders', 'Order Days'),
        _Column('edited_orders', 'Edited Order Days'),
        _Column('qty', 'Added Qty'),
        _Column('products', 'Products'),
      ],
    );

    _sheet(
      workbook,
      name: 'Products',
      title: 'Most Increased Products',
      from: from,
      to: to,
      rows: _list(data['top_products']),
      columns: const [
        _Column('item_code', 'Item Code'),
        _Column('item_name', 'Item Name'),
        _Column('requests', 'Edits'),
        _Column('qty', 'Added Qty'),
      ],
    );

    _sheet(
      workbook,
      name: 'Reasons',
      title: 'Reasons',
      from: from,
      to: to,
      rows: _list(data['reasons']),
      columns: const [
        _Column('reason', 'Reason'),
        _Column('count', 'Edits'),
        _Column('qty', 'Added Qty'),
        _Column('percent', 'Percent %'),
      ],
    );

    _sheet(
      workbook,
      name: 'Details',
      title: 'Positive Order Edit Details',
      from: from,
      to: to,
      rows: _list(data['rows']),
      columns: const [
        _Column('run_date', 'Run Date'),
        _Column('branch_name', 'Branch'),
        _Column('zone', 'Zone'),
        _Column('item_code', 'Item Code'),
        _Column('item_name', 'Item Name'),
        _Column('old_qty', 'Old Qty'),
        _Column('new_qty', 'New Qty'),
        _Column('diff', 'Added Qty'),
        _Column('reason', 'Reason'),
        _Column('changed_at', 'Changed At'),
      ],
    );

    _download(
      workbook,
      'Order_Edit_Increase_Analysis_${_fmt(from)}_${_fmt(to)}.xlsx',
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
    final summarySheet = workbook.worksheets[0];
    summarySheet.name = 'Sales Summary';

    final summary = Map<String, dynamic>.from(data['summary'] as Map? ?? {});
    _intro(summarySheet, 'Order Edit Sales Monitoring', from, to, [
      ['Branch Filter', branch ?? 'All Branches'],
      ['Status Filter', _effectivenessLabel(statusFilter)],
      ['Search', search.trim().isEmpty ? 'All' : search.trim()],
      [
        'Rule',
        'Positive edits only: diff > 0. Sales are counted after the edit date.',
      ],
    ]);

    _writeTable(summarySheet, 9, [
      ['Metric', 'Value'],
      ['Total Positive Edits', summary['total_requests'] ?? 0],
      ['Total Added Qty', summary['total_added_qty'] ?? 0],
      ['Total Sold Qty', summary['total_sold_qty'] ?? 0],
      ['Remaining Added Qty', summary['remaining_added_qty'] ?? 0],
      ['Sales Count', summary['sale_count'] ?? 0],
      ['Sold Within 3 Days', summary['sold_within_3d'] ?? 0],
      ['Sold After 3 Days', summary['sold_after_3d'] ?? 0],
      ['Not Sold', summary['not_sold'] ?? 0],
      ['Sales Success Rate %', summary['effectiveness_rate'] ?? 0],
      ['Quick Sell Rate %', summary['quick_sell_rate'] ?? 0],
      ['Average Days To First Sale', summary['avg_days_to_first_sale'] ?? ''],
      ['Average Sold %', summary['avg_sold_pct'] ?? 0],
    ]);

    _sheet(
      workbook,
      name: 'Branch Sales',
      title: 'Branch Sales Monitoring After Positive Order Edits',
      from: from,
      to: to,
      rows: _list(data['branch_effectiveness']),
      columns: const [
        _Column('branch_name', 'Branch'),
        _Column('total_requests', 'Positive Edits'),
        _Column('products_count', 'Products'),
        _Column('total_request_qty', 'Added Qty'),
        _Column('total_sold_qty', 'Sold Qty'),
        _Column('remaining_added_qty', 'Remaining Added Qty'),
        _Column('sale_count', 'Sales Count'),
        _Column('sold_within_3d', 'Sold <= 3 Days'),
        _Column('sold_after_3d', 'Sold > 3 Days'),
        _Column('not_sold', 'Not Sold'),
        _Column('effectiveness_rate', 'Success Rate %'),
        _Column('quick_sell_rate', 'Quick Sell Rate %'),
        _Column('avg_days_to_first_sale', 'Avg Days To Sale'),
        _Column('last_sale_date', 'Last Sale Date'),
      ],
    );

    _sheet(
      workbook,
      name: 'Product Sales',
      title: 'Product Sales Monitoring After Positive Order Edits',
      from: from,
      to: to,
      rows: _list(data['product_effectiveness']),
      columns: const [
        _Column('item_code', 'Item Code'),
        _Column('item_name', 'Item Name'),
        _Column('total_requests', 'Positive Edits'),
        _Column('total_request_qty', 'Added Qty'),
        _Column('total_sold_qty', 'Sold Qty'),
        _Column('remaining_added_qty', 'Remaining Added Qty'),
        _Column('sale_count', 'Sales Count'),
        _Column('sold_within_3d', 'Sold <= 3 Days'),
        _Column('sold_after_3d', 'Sold > 3 Days'),
        _Column('not_sold', 'Not Sold'),
        _Column('effectiveness_rate', 'Success Rate %'),
        _Column('sold_pct', 'Sold Qty %'),
      ],
    );

    _sheet(
      workbook,
      name: 'Edit Details',
      title: 'Edit-Level Sales Monitoring',
      from: from,
      to: to,
      rows: _list(data['rows']),
      columns: const [
        _Column('request_date', 'Added Date'),
        _Column('branch_name', 'Branch'),
        _Column('item_code', 'Item Code'),
        _Column('item_name', 'Item Name'),
        _Column('old_qty', 'Old Qty'),
        _Column('new_qty', 'New Qty'),
        _Column('request_qty', 'Added Qty'),
        _Column('total_sold_qty', 'Sold Qty'),
        _Column('remaining_added_qty', 'Remaining Added Qty'),
        _Column('sale_count', 'Sales Count'),
        _Column('sold_pct', 'Sold %'),
        _Column('monitoring_label', 'Sales Status'),
        _Column('first_sale_date', 'First Sale Date'),
        _Column('last_sale_date', 'Last Sale Date'),
        _Column('days_to_first_sale', 'Days To First Sale'),
        _Column('days_without_sale', 'Days Without Sale'),
        _Column('selling_days', 'Selling Days'),
        _Column('reason', 'Reason'),
      ],
    );

    _download(
      workbook,
      'Order_Edit_Sales_Monitoring_${_fmt(from)}_${_fmt(to)}.xlsx',
    );
  }

  static void _intro(
    xlsio.Worksheet sheet,
    String title,
    DateTime from,
    DateTime to,
    List<List<dynamic>> extra,
  ) {
    sheet.getRangeByName('A1:F1').merge();
    final titleCell = sheet.getRangeByName('A1');
    titleCell.setText(title);
    titleCell.cellStyle.bold = true;
    titleCell.cellStyle.fontSize = 18;
    titleCell.cellStyle.fontColor = '#0F172A';

    sheet.getRangeByName('A3').setText('From');
    sheet.getRangeByName('B3').setText(_fmt(from));
    sheet.getRangeByName('A4').setText('To');
    sheet.getRangeByName('B4').setText(_fmt(to));

    var row = 3;
    for (final item in extra) {
      sheet.getRangeByIndex(row, 4).setText(item[0].toString());
      sheet.getRangeByIndex(row, 5).setText(item[1].toString());
      row++;
    }
  }

  static void _sheet(
    xlsio.Workbook workbook, {
    required String name,
    required String title,
    required DateTime from,
    required DateTime to,
    required List<Map<String, dynamic>> rows,
    required List<_Column> columns,
  }) {
    final sheet = workbook.worksheets.addWithName(name);
    _intro(sheet, title, from, to, const []);

    final table = <List<dynamic>>[
      columns.map((e) => e.label).toList(),
      ...rows.map((row) => columns.map((col) => row[col.key] ?? '').toList()),
    ];
    _writeTable(sheet, 7, table);
  }

  static void _writeTable(
    xlsio.Worksheet sheet,
    int startRow,
    List<List<dynamic>> rows,
  ) {
    if (rows.isEmpty) return;

    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < rows[r].length; c++) {
        final cell = sheet.getRangeByIndex(startRow + r, c + 1);
        final value = rows[r][c];
        if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText(value?.toString() ?? '');
        }

        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        cell.cellStyle.borders.all.color = '#CBD5E1';

        if (r == 0) {
          cell.cellStyle.bold = true;
          cell.cellStyle.backColor = '#DBEAFE';
          cell.cellStyle.fontColor = '#0F172A';
        }
      }
    }

    sheet.getRangeByIndex(startRow, 1, startRow + rows.length, rows[0].length)
      ..autoFitColumns()
      ..cellStyle.vAlign = xlsio.VAlignType.center;
  }

  static List<Map<String, dynamic>> _list(dynamic raw) {
    return List<Map<String, dynamic>>.from(raw as List? ?? const []);
  }

  static String _fmt(DateTime value) {
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
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

  static void _download(xlsio.Workbook workbook, String fileName) {
    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final blob = html.Blob([
      Uint8List.fromList(bytes),
    ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..download = fileName
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}

class _Column {
  final String key;
  final String label;

  const _Column(this.key, this.label);
}
