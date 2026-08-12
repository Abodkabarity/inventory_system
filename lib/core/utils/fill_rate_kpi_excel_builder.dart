import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../data/datasources/remote/fill_rate_kpi_remote_ds.dart';

class FillRateKpiExcelBuilder {
  static List<int> build({
    required DateTime from,
    required DateTime to,
    required String branch,
    required FillRateReport report,
    required List<FillRateItem> items,
  }) {
    final book = xlsio.Workbook(5);
    _managementSheet(
      book.worksheets[0]..name = 'Management Overview',
      from: from,
      to: to,
      branch: branch,
      report: report,
    );
    _summarySheet(
      book.worksheets[1]..name = 'Branch Summary',
      from: from,
      to: to,
      rows: report.summaries,
    );
    _statusSheet(
      book.worksheets[2]..name = 'Purchase Status',
      from: from,
      to: to,
      rows: report.statuses,
    );
    _dailySheet(
      book.worksheets[3]..name = 'Daily Trend',
      from: from,
      to: to,
      rows: report.daily,
    );
    _detailSheet(
      book.worksheets[4]..name = 'Item Details',
      from: from,
      to: to,
      rows: items,
    );
    final bytes = book.saveAsStream();
    book.dispose();
    return bytes;
  }

  static void _managementSheet(
    xlsio.Worksheet sheet, {
    required DateTime from,
    required DateTime to,
    required String branch,
    required FillRateReport report,
  }) {
    final focused = FillRateFocusedMetrics.fromStatuses(report.statuses);
    final focusedStatuses = report.statuses.where(
      (status) => FillRateFocusedMetrics.includes(status.name),
    );
    final focusedReceivedProducts = focusedStatuses.fold<int>(
      0,
      (sum, status) => sum + status.suppliedItems,
    );
    _title(
      sheet,
      columns: 8,
      title: 'REFILL SUPPLY — MANAGEMENT REPORT',
      subtitle:
          'Reporting period: ${_date(from)} to ${_date(to)}   |   Scope: $branch   |   Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
    );

    _section(sheet, 5, 8, '1. Fill Rate Comparison for Every Purchase Status');
    _header(sheet, 6, const [
      'Purchase Status',
      'Requested Products',
      'Products Received',
      'Products Not Received',
      'Requested Quantity',
      'Quantity Received',
      'Share of All Products %',
      'Fill Rate — Quantity Received %',
    ]);
    for (var i = 0; i < report.statuses.length; i++) {
      final status = report.statuses[i];
      _row(
        sheet,
        i + 7,
        [
          status.name,
          status.totalItems,
          status.suppliedItems,
          status.totalItems - status.suppliedItems,
          status.requiredQty,
          status.suppliedQty,
          status.share,
          status.unitFillRate,
        ],
        percentColumns: const {7, 8},
      );
      sheet.getRangeByIndex(i + 7, 1).cellStyle.bold = true;
    }
    final statusTableEnd = 6 + report.statuses.length;
    _note(
      sheet,
      statusTableEnd + 1,
      8,
      'Products Received means products that received any quantity above zero. Fill Rate = Quantity Received ÷ Requested Quantity × 100.',
      color: '#EFF6FF',
      fontColor: '#1E3A8A',
    );

    final combinedSectionRow = statusTableEnd + 3;
    _section(
      sheet,
      combinedSectionRow,
      8,
      '2. Combined Result — AVAILABLE + AVAILABLE N.E + NOT ASSIGNED',
    );
    _note(
      sheet,
      combinedSectionRow + 1,
      8,
      'Use this result to compare the combined percentage with the individual Purchase Status percentages shown above.',
      color: '#E8F7F2',
      fontColor: '#047857',
    );
    _metric(
      sheet,
      combinedSectionRow + 3,
      1,
      2,
      'Requested Products',
      focused.includedItems,
    );
    _metric(
      sheet,
      combinedSectionRow + 3,
      3,
      4,
      'Products Received',
      focusedReceivedProducts,
    );
    _metric(
      sheet,
      combinedSectionRow + 3,
      5,
      6,
      'Products Not Received',
      focused.includedItems - focusedReceivedProducts,
    );
    _metric(
      sheet,
      combinedSectionRow + 3,
      7,
      8,
      'Requested Quantity',
      focused.requiredQty,
    );
    _metric(
      sheet,
      combinedSectionRow + 7,
      1,
      4,
      'Quantity Received',
      focused.suppliedQty,
    );
    _metric(
      sheet,
      combinedSectionRow + 7,
      5,
      8,
      'COMBINED FILL RATE — QUANTITY RECEIVED',
      focused.unitFillRate,
      percentage: true,
    );
    _note(
      sheet,
      combinedSectionRow + 10,
      8,
      '${_number(focused.suppliedQty)} quantity received ÷ ${_number(focused.requiredQty)} quantity requested × 100 = ${_percent(focused.unitFillRate)}',
      color: '#F8FAFC',
      fontColor: '#334155',
    );
    _setWidths(sheet, const [34, 22, 22, 24, 23, 23, 24, 28]);
    sheet.getRangeByName('A5').freezePanes();
    sheet.pageSetup
      ..orientation = xlsio.ExcelPageOrientation.landscape
      ..isFitToPage = true
      ..fitToPagesWide = 1;
  }

  static void _summarySheet(
    xlsio.Worksheet sheet, {
    required DateTime from,
    required DateTime to,
    required List<FillRateSummary> rows,
  }) {
    const headers = [
      'Branch',
      'Quantity Received %',
      'Requested Products',
      'Products Received',
      'Fully Supplied',
      'Partially Supplied',
      'Not Supplied',
      'Requested Quantity',
      'Quantity Received',
    ];
    _tableTitle(
      sheet,
      columns: headers.length,
      title: 'Refill Supply by Branch',
      subtitle:
          '${_date(from)} to ${_date(to)} — Products Received means products that received any quantity above zero. ALL BRANCHES is the company total.',
    );
    _header(sheet, 5, headers);
    for (var i = 0; i < rows.length; i++) {
      final value = rows[i];
      _row(
        sheet,
        i + 6,
        [
          value.branchName,
          value.unitFillRate,
          value.totalItems,
          value.suppliedItems,
          value.fullySupplied,
          value.partiallySupplied,
          value.notSupplied,
          value.requiredQty,
          value.suppliedQty,
        ],
        percentColumns: const {2},
      );
    }
    _finishTable(sheet, 5, headers.length, rows.length);
    _setWidths(sheet, const [32, 20, 22, 22, 18, 20, 18, 20, 20]);
  }

  static void _statusSheet(
    xlsio.Worksheet sheet, {
    required DateTime from,
    required DateTime to,
    required List<FillRateStatus> rows,
  }) {
    const headers = [
      'Purchase Status',
      'Requested Products',
      'Products Received',
      'Requested Quantity',
      'Quantity Received',
      'Share of All Products %',
      'Quantity Received %',
    ];
    _tableTitle(
      sheet,
      columns: headers.length,
      title: 'Purchase Status Distribution and Supply Results',
      subtitle:
          '${_date(from)} to ${_date(to)} — Each Purchase Status is shown independently for direct comparison.',
    );
    _header(sheet, 5, headers);
    for (var i = 0; i < rows.length; i++) {
      final value = rows[i];
      _row(
        sheet,
        i + 6,
        [
          value.name,
          value.totalItems,
          value.suppliedItems,
          value.requiredQty,
          value.suppliedQty,
          value.share,
          value.unitFillRate,
        ],
        percentColumns: const {6, 7},
      );
    }
    _finishTable(sheet, 5, headers.length, rows.length);
    _setWidths(sheet, const [34, 22, 22, 23, 23, 24, 28]);
  }

  static void _dailySheet(
    xlsio.Worksheet sheet, {
    required DateTime from,
    required DateTime to,
    required List<FillRateDaily> rows,
  }) {
    const headers = [
      'Date',
      'Quantity Received %',
      'Requested Products',
      'Products Received',
      'Fully Supplied',
      'Partially Supplied',
      'Not Supplied',
    ];
    _tableTitle(
      sheet,
      columns: headers.length,
      title: 'Daily Refill Supply Trend',
      subtitle:
          '${_date(from)} to ${_date(to)} — Products Received means products that received any quantity above zero.',
    );
    _header(sheet, 5, headers);
    for (var i = 0; i < rows.length; i++) {
      final value = rows[i];
      _row(
        sheet,
        i + 6,
        [
          _date(value.date),
          value.unitFillRate,
          value.totalItems,
          value.suppliedItems,
          value.fullySupplied,
          value.partiallySupplied,
          value.notSupplied,
        ],
        percentColumns: const {2},
      );
    }
    _finishTable(sheet, 5, headers.length, rows.length);
    _setWidths(sheet, const [18, 22, 22, 22, 18, 20, 18]);
  }

  static void _detailSheet(
    xlsio.Worksheet sheet, {
    required DateTime from,
    required DateTime to,
    required List<FillRateItem> rows,
  }) {
    const headers = [
      'Branch',
      'Order Date',
      'Item Code',
      'Product Name',
      'Original Reorder Qty',
      'Effective Required Qty',
      'Edited Order?',
      'Approved Transfer Qty',
      'Qty Counted',
      'Product Supply %',
      'Fulfillment Result',
      'Purchase Status',
    ];
    _tableTitle(
      sheet,
      columns: headers.length,
      title: 'Product-Level Audit Details',
      subtitle:
          '${_date(from)} to ${_date(to)} — Branch is first and Purchase Status is last. Excel filters are enabled on every column.',
    );
    _header(sheet, 5, headers);
    for (var i = 0; i < rows.length; i++) {
      final value = rows[i];
      _row(
        sheet,
        i + 6,
        [
          value.branchName,
          _date(value.date),
          value.itemCode,
          value.itemName,
          value.originalQty,
          value.requiredQty,
          value.wasEdited ? 'Yes' : 'No',
          value.transferredQty,
          value.suppliedQty,
          value.fillRate,
          value.fulfillmentStatus,
          value.purchaseStatus,
        ],
        percentColumns: const {10},
      );
    }
    _finishTable(sheet, 5, headers.length, rows.length);
    _setWidths(sheet, const [32, 16, 19, 48, 21, 23, 16, 23, 17, 18, 22, 31]);
  }

  static void _title(
    xlsio.Worksheet sheet, {
    required int columns,
    required String title,
    required String subtitle,
  }) {
    final titleRange = sheet.getRangeByIndex(1, 1, 2, columns)..merge();
    titleRange
      ..setText(title)
      ..rowHeight = 28;
    titleRange.cellStyle
      ..bold = true
      ..fontSize = 20
      ..fontColor = '#FFFFFF'
      ..backColor = '#1E3A8A'
      ..hAlign = xlsio.HAlignType.left
      ..vAlign = xlsio.VAlignType.center;
    final subtitleRange = sheet.getRangeByIndex(3, 1, 3, columns)..merge();
    subtitleRange
      ..setText(subtitle)
      ..rowHeight = 25;
    subtitleRange.cellStyle
      ..fontColor = '#E0F2FE'
      ..backColor = '#075985'
      ..vAlign = xlsio.VAlignType.center;
    sheet.getRangeByIndex(4, 1).rowHeight = 8;
    sheet.pageSetup.showGridlines = false;
  }

  static void _tableTitle(
    xlsio.Worksheet sheet, {
    required int columns,
    required String title,
    required String subtitle,
  }) {
    _title(sheet, columns: columns, title: title, subtitle: subtitle);
  }

  static void _section(
    xlsio.Worksheet sheet,
    int row,
    int columns,
    String title,
  ) {
    final range = sheet.getRangeByIndex(row, 1, row, columns)..merge();
    range
      ..setText(title)
      ..rowHeight = 27;
    range.cellStyle
      ..bold = true
      ..fontSize = 13
      ..fontColor = '#FFFFFF'
      ..backColor = '#2563EB'
      ..vAlign = xlsio.VAlignType.center;
  }

  static void _metric(
    xlsio.Worksheet sheet,
    int row,
    int startColumn,
    int endColumn,
    String label,
    num value, {
    bool percentage = false,
  }) {
    final labelRange = sheet.getRangeByIndex(row, startColumn, row, endColumn)
      ..merge();
    labelRange
      ..setText(label)
      ..rowHeight = 22;
    labelRange.cellStyle
      ..bold = true
      ..fontColor = '#475569'
      ..backColor = '#EFF6FF'
      ..hAlign = xlsio.HAlignType.center;
    final valueRange = sheet.getRangeByIndex(
      row + 1,
      startColumn,
      row + 2,
      endColumn,
    )..merge();
    valueRange
      ..setNumber(value.toDouble())
      ..numberFormat = percentage
          ? '0.00"%"'
          : value is int
          ? '#,##0'
          : '#,##0.00';
    valueRange.cellStyle
      ..bold = true
      ..fontSize = 18
      ..fontColor = percentage ? '#DC2626' : '#0F172A'
      ..backColor = '#F8FAFC'
      ..hAlign = xlsio.HAlignType.center
      ..vAlign = xlsio.VAlignType.center;
  }

  static void _note(
    xlsio.Worksheet sheet,
    int row,
    int columns,
    String text, {
    String color = '#F8FAFC',
    String fontColor = '#334155',
  }) {
    final range = sheet.getRangeByIndex(row, 1, row, columns)..merge();
    range
      ..setText(text)
      ..rowHeight = 25;
    range.cellStyle
      ..backColor = color
      ..fontColor = fontColor
      ..wrapText = true
      ..vAlign = xlsio.VAlignType.center;
  }

  static void _header(xlsio.Worksheet sheet, int row, List<String> headers) {
    for (var column = 1; column <= headers.length; column++) {
      final cell = sheet.getRangeByIndex(row, column)
        ..setText(headers[column - 1]);
      cell.cellStyle
        ..bold = true
        ..fontColor = '#FFFFFF'
        ..backColor = '#164E63'
        ..hAlign = xlsio.HAlignType.center
        ..vAlign = xlsio.VAlignType.center
        ..wrapText = true;
    }
    sheet.getRangeByIndex(row, 1, row, headers.length).rowHeight = 36;
  }

  static void _row(
    xlsio.Worksheet sheet,
    int row,
    List<Object> values, {
    Set<int> percentColumns = const {},
  }) {
    for (var column = 1; column <= values.length; column++) {
      final cell = sheet.getRangeByIndex(row, column);
      final value = values[column - 1];
      if (value is num) {
        cell
          ..setNumber(value.toDouble())
          ..numberFormat = percentColumns.contains(column)
              ? '0.00"%"'
              : value is int
              ? '#,##0'
              : '#,##0.00';
      } else {
        cell.setText('$value');
      }
      cell.cellStyle
        ..backColor = row.isEven ? '#F0F9FF' : '#FFFFFF'
        ..vAlign = xlsio.VAlignType.center
        ..wrapText = true;
    }
    sheet.getRangeByIndex(row, 1, row, values.length).rowHeight = 24;
  }

  static void _finishTable(
    xlsio.Worksheet sheet,
    int headerRow,
    int columns,
    int rowCount,
  ) {
    if (rowCount > 0) {
      sheet.autoFilters.filterRange = sheet.getRangeByIndex(
        headerRow,
        1,
        headerRow + rowCount,
        columns,
      );
    }
    sheet.getRangeByIndex(headerRow + 1, 1).freezePanes();
    sheet.pageSetup
      ..showGridlines = false
      ..orientation = xlsio.ExcelPageOrientation.landscape
      ..isFitToPage = true
      ..fitToPagesWide = 1;
  }

  static void _setWidths(xlsio.Worksheet sheet, List<double> widths) {
    for (var i = 0; i < widths.length; i++) {
      sheet.getRangeByIndex(1, i + 1).columnWidth = widths[i];
    }
  }

  static String _date(DateTime value) => DateFormat('yyyy-MM-dd').format(value);
  static String _number(num value) => NumberFormat('#,##0.##').format(value);
  static String _percent(num value) => '${value.toStringAsFixed(2)}%';
}
