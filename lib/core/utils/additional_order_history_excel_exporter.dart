import 'dart:html' as html;
import 'dart:typed_data';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

class AdditionalOrderHistoryExcelExporter {
  static Future<void> export({
    required List<Map<String, dynamic>> rows,
    required DateTime from,
    required DateTime to,
    required String branch,
    required String query,
  }) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Additional History';

    sheet.getRangeByIndex(1, 1).setText('Additional Order History');
    sheet.getRangeByIndex(1, 1, 1, 12).merge();
    final title = sheet.getRangeByIndex(1, 1);
    title.cellStyle.bold = true;
    title.cellStyle.fontSize = 17;
    title.cellStyle.fontColor = '#0F172A';
    title.cellStyle.hAlign = xlsio.HAlignType.left;

    sheet.getRangeByIndex(2, 1).setText('Date Range');
    sheet
        .getRangeByIndex(2, 2)
        .setText('${_formatDate(from)} -> ${_formatDate(to)}');
    sheet.getRangeByIndex(2, 4).setText('Branch');
    sheet.getRangeByIndex(2, 5).setText(branch);
    sheet.getRangeByIndex(3, 1).setText('Search');
    sheet.getRangeByIndex(3, 2).setText(query.isEmpty ? 'All' : query);
    sheet.getRangeByIndex(3, 4).setText('Rows');
    sheet.getRangeByIndex(3, 5).setNumber(rows.length.toDouble());

    for (final cell in [
      sheet.getRangeByIndex(2, 1),
      sheet.getRangeByIndex(2, 4),
      sheet.getRangeByIndex(3, 1),
      sheet.getRangeByIndex(3, 4),
    ]) {
      cell.cellStyle.bold = true;
      cell.cellStyle.fontColor = '#475569';
    }

    final headers = [
      '#',
      'Status',
      'Branch',
      'Item Code',
      'Item Name',
      'Request Qty',
      'Inventory Qty',
      'Store Qty',
      'Inventory Note',
      'Store Note',
      'Date & Time',
      'Contact Logistic',
    ];

    const headerRow = 5;
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.getRangeByIndex(headerRow, c + 1);
      cell.setText(headers[c]);
      cell.cellStyle.bold = true;
      cell.cellStyle.fontColor = '#FFFFFF';
      cell.cellStyle.backColor = '#0891B2';
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.vAlign = xlsio.VAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      cell.cellStyle.borders.all.color = '#155E75';
    }

    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      final values = [
        r + 1,
        _statusLabel(_text(row, 'status')),
        _text(row, 'branch_name'),
        _text(row, 'item_code'),
        _text(row, 'item_name'),
        _num(row['request_qty']),
        _num(row['inventory_qty']),
        _num(row['fulfilled_qty']),
        _text(row, 'inventory_note'),
        _text(row, 'store_note'),
        _historyDate(row),
        _text(row, 'contact_logistic'),
      ];

      for (var c = 0; c < values.length; c++) {
        final cell = sheet.getRangeByIndex(headerRow + r + 1, c + 1);
        final value = values[c];
        if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText(value.toString());
        }

        cell.cellStyle.hAlign = (c == 4 || c == 8 || c == 9)
            ? xlsio.HAlignType.left
            : xlsio.HAlignType.center;
        cell.cellStyle.vAlign = xlsio.VAlignType.center;
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        cell.cellStyle.borders.all.color = '#CBD5E1';
        if (r.isOdd) cell.cellStyle.backColor = '#F8FAFC';
      }
    }

    final lastRow = headerRow + rows.length;
    sheet.getRangeByIndex(1, 1, lastRow, headers.length).autoFitColumns();
    sheet.getRangeByIndex(1, 3).columnWidth = 22;
    sheet.getRangeByIndex(1, 4).columnWidth = 18;
    sheet.getRangeByIndex(1, 5).columnWidth = 44;
    sheet.getRangeByIndex(1, 9).columnWidth = 34;
    sheet.getRangeByIndex(1, 10).columnWidth = 34;
    sheet.getRangeByIndex(1, 11).columnWidth = 20;
    sheet.getRangeByIndex(1, 1, lastRow, headers.length).rowHeight = 22;

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final blob = html.Blob([Uint8List.fromList(bytes)]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final fileName =
        'Additional_Order_History_${_formatDate(from)}_${_formatDate(to)}.xlsx';

    html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  static String _text(Map<String, dynamic> row, String key) {
    return (row[key] ?? '').toString().trim();
  }

  static num _num(dynamic raw) {
    if (raw is num) return raw;
    return num.tryParse((raw ?? '').toString()) ?? 0;
  }

  static String _statusLabel(String status) {
    switch (status.toLowerCase().trim()) {
      case 'pending':
      case 'pending_inventory':
        return 'Pending';
      case 'sent_to_store':
        return 'Sent To Store';
      case 'done':
        return 'Done';
      case 'rejected':
        return 'Rejected';
      default:
        return status;
    }
  }

  static String _historyDate(Map<String, dynamic> row) {
    final status = _text(row, 'status').toLowerCase();
    final rawDates = <dynamic>[
      if (status == 'done' || status == 'rejected') row['done_at'],
      if (status == 'sent_to_store' || status == 'rejected')
        row['inventory_approved_at'],
      row['created_at'],
    ];

    for (final raw in rawDates) {
      final parsed = DateTime.tryParse((raw ?? '').toString())?.toLocal();
      if (parsed == null) continue;
      return '${_formatDate(parsed)} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
    }

    return '';
  }

  static String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
