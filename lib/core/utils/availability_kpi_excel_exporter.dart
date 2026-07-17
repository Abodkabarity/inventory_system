// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../data/datasources/remote/availability_kpi_remote_ds.dart';

class AvailabilityKpiExcelExporter {
  static Future<void> export({
    required String branch,
    required String stockDate,
    required List<AvailabilityKpiItem> items,
  }) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0]..name = 'Availability KPI';

    final title = sheet.getRangeByName('A1:P1');
    title.merge();
    title.setText('Availability KPI — $branch');
    title.cellStyle
      ..bold = true
      ..fontSize = 18
      ..fontColor = '#FFFFFF'
      ..backColor = '#172554'
      ..hAlign = xlsio.HAlignType.left
      ..vAlign = xlsio.VAlignType.center;
    title.rowHeight = 34;

    sheet.getRangeByName('A2').setText('Stock date');
    sheet.getRangeByName('B2').setText(stockDate);
    sheet.getRangeByName('D2').setText('Exported rows');
    sheet.getRangeByName('E2').setNumber(items.length.toDouble());
    sheet.getRangeByName('G2').setText('Purchase status');
    sheet.getRangeByName('H2').setText('1#NORMAL PURCHASE');

    const headers = [
      'Branch',
      'Item Code',
      'Product',
      'Selection Reason',
      '3 Completed Months Sales',
      'Retail Price',
      'Retail Sales Value',
      'Branch Sales Share %',
      'Months Sold (1-12)',
      'Sold Months Count',
      'Total Studied Months',
      'Selling Month %',
      'Needed For 7 Days',
      'Current Branch Stock',
      'Units Missing',
      '7-Day Coverage %',
    ];
    const headerRow = 4;
    for (var column = 1; column <= headers.length; column++) {
      final cell = sheet.getRangeByIndex(headerRow, column);
      cell.setText(headers[column - 1]);
      cell.cellStyle
        ..bold = true
        ..fontColor = '#FFFFFF'
        ..backColor = '#2563EB'
        ..hAlign = xlsio.HAlignType.center
        ..vAlign = xlsio.VAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      cell.cellStyle.borders.all.color = '#1E3A8A';
    }
    sheet.getRangeByIndex(headerRow, 1, headerRow, headers.length).rowHeight =
        32;

    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final row = headerRow + index + 1;
      final values = <Object?>[
        item.branchName,
        item.itemCode,
        item.itemName,
        _selectionReason(item),
        item.recentSales,
        item.retail,
        item.recentSalesValue,
        item.recentSalesShare,
        item.sellingMonthNumbers.isEmpty
            ? ''
            : item.sellingMonthNumbers.join(', '),
        item.sellingMonths,
        item.totalMonths,
        item.monthConsistency,
        item.weeklyNeed,
        item.branchStock,
        item.stockShortage,
        item.availabilityRate,
      ];
      for (var column = 1; column <= values.length; column++) {
        final cell = sheet.getRangeByIndex(row, column);
        final value = values[column - 1];
        if (value is num) {
          cell.setNumber(value.toDouble());
          cell.numberFormat = '0.0';
        } else {
          cell.setText((value ?? '').toString());
        }
        cell.cellStyle
          ..vAlign = xlsio.VAlignType.center
          ..backColor = index.isOdd ? '#F8FAFC' : '#FFFFFF';
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        cell.cellStyle.borders.all.color = '#CBD5E1';
      }
      if (item.stockShortage > 0) {
        sheet.getRangeByIndex(row, 15).cellStyle
          ..fontColor = '#DC2626'
          ..bold = true;
      }
      sheet.getRangeByIndex(row, 16).cellStyle
        ..fontColor = item.availabilityRate >= 95
            ? '#059669'
            : item.availabilityRate >= 80
            ? '#D97706'
            : '#DC2626'
        ..bold = true;
    }

    sheet.getRangeByIndex(1, 1).columnWidth = 24;
    sheet.getRangeByIndex(1, 2).columnWidth = 18;
    sheet.getRangeByIndex(1, 3).columnWidth = 46;
    sheet.getRangeByIndex(1, 4).columnWidth = 28;
    for (var column = 5; column <= headers.length; column++) {
      sheet.getRangeByIndex(1, column).columnWidth = 18;
    }
    if (items.isNotEmpty) {
      sheet.autoFilters.filterRange = sheet.getRangeByIndex(
        headerRow,
        1,
        headerRow + items.length,
        headers.length,
      );
    }

    final bytes = workbook.saveAsStream();
    workbook.dispose();
    final blob = html.Blob([
      Uint8List.fromList(bytes),
    ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final safeBranch = branch.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    final timestamp = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
    html.AnchorElement(href: url)
      ..setAttribute(
        'download',
        'Availability_KPI_${safeBranch}_$stockDate'
            '_$timestamp.xlsx',
      )
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  static String _selectionReason(AvailabilityKpiItem item) {
    return item.inPareto
        ? 'Top seller — 80% of branch sales value'
        : 'Sold regularly';
  }
}
