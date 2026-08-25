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
    final book = xlsio.Workbook(2);
    _managementSheet(
      book.worksheets[0]..name = 'Fill Rate Gap Analysis',
      from: from,
      to: to,
      branch: branch,
      report: report,
    );
    _detailSheet(
      book.worksheets[1]..name = 'Item Details',
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
    final total = report.total;
    final totalReorderQty = total.requiredQty;
    final transferFromStore = total.suppliedQty;
    final unfulfilledQty = (totalReorderQty - transferFromStore).clamp(
      0,
      totalReorderQty,
    );
    final fillRate = totalReorderQty > 0
        ? 100 * transferFromStore / totalReorderQty
        : 0;
    final unfulfilledGap = totalReorderQty > 0
        ? 100 * unfulfilledQty / totalReorderQty
        : 0;
    final gapByStatus = report.statuses
        .map(
          (status) => (
            status: status,
            qty: (status.requiredQty - status.suppliedQty).clamp(
              0,
              status.requiredQty,
            ),
          ),
        )
        .where((value) => value.qty > 0)
        .toList(growable: false);
    _title(
      sheet,
      columns: 4,
      title: 'FILL RATE — GAP ANALYSIS',
      subtitle:
          'Reporting period: ${_date(from)} to ${_date(to)}   |   Scope: $branch   |   Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
    );

    _section(sheet, 5, 4, '1. Fill Rate and Unfulfilled Gap');
    _metric(sheet, 6, 1, 2, 'Total Reorder Qty', totalReorderQty);
    _metric(sheet, 6, 3, 4, 'Transfer from Store', transferFromStore);
    _metric(sheet, 9, 1, 2, 'Fill Rate', fillRate, percentage: true);
    _metric(
      sheet,
      9,
      3,
      4,
      'Unfulfilled Gap',
      unfulfilledGap,
      percentage: true,
    );

    const breakdownSectionRow = 13;
    _section(
      sheet,
      breakdownSectionRow,
      4,
      '2. Unfulfilled Gap Breakdown by Purchase Status',
    );
    _note(
      sheet,
      breakdownSectionRow + 1,
      4,
      'The “Of All Reorder Qty %” column adds up to the Unfulfilled Gap. For example, if Fill Rate is 30%, the rows below explain the remaining 70% by Purchase Status.',
      color: '#E8F7F2',
      fontColor: '#047857',
    );
    _header(sheet, breakdownSectionRow + 2, const [
      'Purchase Status',
      'Unfulfilled Reorder Qty',
      'Share of Unfulfilled Gap %',
      'Of All Reorder Qty %',
    ]);
    for (var i = 0; i < gapByStatus.length; i++) {
      final value = gapByStatus[i];
      final shareOfGap = unfulfilledQty > 0
          ? 100 * value.qty / unfulfilledQty
          : 0;
      final shareOfAllReorder = totalReorderQty > 0
          ? 100 * value.qty / totalReorderQty
          : 0;
      _row(
        sheet,
        breakdownSectionRow + 3 + i,
        [value.status.name, value.qty, shareOfGap, shareOfAllReorder],
        percentColumns: const {3, 4},
      );
      sheet.getRangeByIndex(breakdownSectionRow + 3 + i, 1).cellStyle.bold =
          true;
    }
    final breakdownTableEnd = breakdownSectionRow + 2 + gapByStatus.length;
    _note(
      sheet,
      breakdownTableEnd + 1,
      4,
      'Unfulfilled Reorder Qty = Reorder Qty − Transfer from Store. A transfer above an item\'s effective Reorder Qty is capped at that Reorder Qty. An approved order edit is the effective Reorder Qty.',
      color: '#EFF6FF',
      fontColor: '#1E3A8A',
    );
    if (gapByStatus.isNotEmpty) {
      sheet.autoFilters.filterRange = sheet.getRangeByIndex(
        breakdownSectionRow + 2,
        1,
        breakdownTableEnd,
        4,
      );
    }
    _setWidths(sheet, const [34, 25, 29, 24]);
    sheet.getRangeByName('A5').freezePanes();
    sheet.pageSetup
      ..orientation = xlsio.ExcelPageOrientation.landscape
      ..isFitToPage = true
      ..fitToPagesWide = 1;
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
      'Reorder Qty',
      'Transfer from Store',
      'Fill Rate',
      'Fulfillment Status',
      'Purchase Status',
    ];
    _tableTitle(
      sheet,
      columns: headers.length,
      title: 'Product Details',
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
          value.requiredQty,
          value.transferredQty,
          value.fillRate,
          value.fulfillmentStatus,
          value.purchaseStatus,
        ],
        percentColumns: const {8},
      );
    }
    _finishTable(sheet, 5, headers.length, rows.length);
    _setWidths(sheet, const [32, 16, 19, 48, 18, 23, 16, 22, 31]);
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
}
