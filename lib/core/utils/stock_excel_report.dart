import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'stock_item_added_date.dart';
import 'store_branch_identity_registry.dart';

/// Shared typed rows for native Excel and the browser export worker.
class StockExcelReport {
  final List<Map<String, dynamic>> rows;
  late final List<String> keys;
  late final List<String> headers;
  late final List<String> types;
  late final List<int> widths;
  final String sheetName;
  StockExcelReport(this.rows, String fileName)
    : sheetName = _sheetName(fileName) {
    if (rows.isEmpty) throw StateError('No matching rows to export.');
    keys = {for (final row in rows) ...row.keys}.toList();
    if (keys.isEmpty || keys.length > 16384 || rows.length >= 1048576) {
      throw StateError('The report exceeds Excel worksheet limits.');
    }
    headers = keys.map(_label).toList();
    types = keys.map((key) {
      final label = _label(key).toLowerCase();
      if (label.contains('%') || key.contains('percent')) return 'percent';
      if (label.contains('date') || label.endsWith('through')) return 'date';
      final sample = rows
          .map((r) => r[key])
          .firstWhere(
            (v) => v != null && v.toString().isNotEmpty,
            orElse: () => null,
          );
      return sample is num ? 'number' : 'text';
    }).toList();
    widths = [
      for (var i = 0; i < keys.length; i++) _width(headers[i], types[i]),
    ];
  }

  static String fileName(String value) {
    final base = value.replaceFirst(
      RegExp(r'\.(csv|xlsx)$', caseSensitive: false),
      '',
    );
    return '$base.xlsx';
  }

  static String _sheetName(String file) {
    if (file.contains('near_expiry')) return 'Near Expiry';
    if (file.contains('mrn_cd_overview')) return 'MRN CD Overview';
    if (file.contains('mrn_overview')) return 'MRN Overview';
    if (file.contains('monthly_sales')) return 'Monthly Sales';
    if (file.contains('daily_sales_45_days')) return 'Daily Sales 45 Days';
    if (file.contains('branches')) return 'Branch Stock';
    return 'Stock Overview';
  }

  static String _label(String key) => switch (key) {
    'item_code' => 'Item code',
    'item_name' => 'Product',
    'branch' || 'branch_name' => 'Branch',
    'recent_sales' => 'Sales 45D',
    'last_3_sales' => 'Last 3 days Qty',
    'baseline_daily' => '42-day daily average',
    'reorder_qty' => 'Reorder Qty',
    'final_qty' => 'Final Reorder Qty',
    'sales_2025' => 'Sales 2025',
    'sales_2026' => 'Sales 2026',
    'month' => 'Month',
    'total' => 'Total Qty',
    'stock' => 'Stock',
    'cash' => 'Cash',
    'insurance' => 'Insurance',
    'online' => 'Online',
    _ =>
      key.isEmpty
          ? 'Column'
          : '${key[0].toUpperCase()}${key.substring(1).replaceAll('_', ' ')}',
  };

  static int _width(String label, String type) {
    final value = label.toLowerCase();
    if (value == 'product' || value == 'note') return 48;
    if (value.contains('supplier') ||
        value.contains('company') ||
        value == 'branch') {
      return 30;
    }
    if (value.contains('status')) return 27;
    if (type == 'date') return 19;
    return (label.length ~/ 2 + 12).clamp(16, 28);
  }

  static String? _date(Object? value) {
    final raw = value?.toString() ?? '';
    final parts = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(raw);
    DateTime? date;
    if (parts != null) {
      final day = int.parse(parts[1]!),
          month = int.parse(parts[2]!),
          year = int.parse(parts[3]!);
      final parsed = DateTime.utc(year, month, day);
      if (parsed.year == year && parsed.month == month && parsed.day == day) {
        date = parsed;
      }
    } else {
      date = stockItemAddedDate(value);
    }
    return date == null
        ? null
        : DateTime.utc(date.year, date.month, date.day).toIso8601String();
  }

  Iterable<List<Object>> get values sync* {
    for (final row in rows) {
      yield [
        for (var i = 0; i < keys.length; i++)
          _value(keys[i], row[keys[i]], types[i]),
      ];
    }
  }

  Object _value(String key, Object? value, String type) {
    final display = StoreBranchIdentityRegistry.exportValue(key, value);
    if (display == null) return '';
    if (display is bool) return display ? 'Yes' : 'No';
    if (type == 'date') return _date(display) ?? display.toString();
    if (display is num) return display.isFinite ? display : '';
    return display.toString();
  }

  List<int> buildNative() {
    final book = xlsio.Workbook();
    try {
      final sheet = book.worksheets[0]..name = sheetName;
      final table = sheet.getRangeByIndex(1, 1, rows.length + 1, keys.length);
      table.cellStyle.borders.all
        ..lineStyle = xlsio.LineStyle.thin
        ..color = '#CBD5E1';
      table.cellStyle
        ..fontName = 'Calibri'
        ..fontSize = 11
        ..vAlign = xlsio.VAlignType.center;
      final header = sheet.getRangeByIndex(1, 1, 1, keys.length);
      header.rowHeight = 36;
      header.cellStyle
        ..backColor = '#4EB0DE'
        ..fontColor = '#FFFFFF'
        ..bold = true
        ..wrapText = true
        ..hAlign = xlsio.HAlignType.center;
      for (var col = 0; col < keys.length; col++) {
        sheet.getRangeByIndex(1, col + 1)
          ..setText(headers[col])
          ..columnWidth = widths[col].toDouble();
      }
      var row = 2;
      for (final values in this.values) {
        final range = sheet.getRangeByIndex(row, 1, row, keys.length)
          ..rowHeight = 24;
        range.cellStyle.backColor = row.isEven ? '#F3F9FD' : '#FFFFFF';
        for (var col = 0; col < values.length; col++) {
          final cell = sheet.getRangeByIndex(row, col + 1);
          final value = values[col];
          if (value is num) {
            cell
              ..setNumber(
                value.toDouble() / (types[col] == 'percent' ? 100 : 1),
              )
              ..numberFormat = types[col] == 'percent' ? '0.0%' : '#,##0.##';
            cell.cellStyle.hAlign = xlsio.HAlignType.right;
          } else if (types[col] == 'date' &&
              DateTime.tryParse(value.toString()) != null) {
            cell
              ..setDateTime(DateTime.parse(value.toString()))
              ..numberFormat = 'dd/mm/yyyy';
          } else {
            cell.setText(value.toString());
          }
        }
        row++;
      }
      sheet.autoFilters.filterRange = table;
      sheet.getRangeByName('B2').freezePanes();
      return book.saveAsStream();
    } finally {
      book.dispose();
    }
  }
}
