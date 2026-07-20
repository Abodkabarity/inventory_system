// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../data/datasources/remote/availability_kpi_remote_ds.dart';

class AvailabilityBranchReportExcelExporter {
  static Future<void> export({
    required String stockDate,
    required List<AvailabilityBranchSummary> branches,
  }) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0]..name = 'Branch Report';
    const columnCount = 13;
    const headerRow = 6;

    final sorted = List<AvailabilityBranchSummary>.from(branches)
      ..sort((a, b) {
        final rate = b.availabilityRate.compareTo(a.availabilityRate);
        return rate != 0 ? rate : a.branchName.compareTo(b.branchName);
      });
    final average = sorted.isEmpty
        ? 0.0
        : sorted.fold<num>(0, (sum, item) => sum + item.availabilityRate) /
              sorted.length;
    final atLeast97 = sorted
        .where((item) => item.availabilityRate >= 97)
        .length;

    final title = sheet.getRangeByIndex(1, 1, 1, columnCount)..merge();
    title.setText('Availability KPI — Branch Report');
    title.cellStyle
      ..bold = true
      ..fontSize = 18
      ..fontColor = '#FFFFFF'
      ..backColor = '#122D40'
      ..hAlign = xlsio.HAlignType.center
      ..vAlign = xlsio.VAlignType.center;
    title.rowHeight = 34;

    sheet.getRangeByName('A2').setText('Stock Date');
    sheet.getRangeByName('B2').setText(stockDate);
    sheet.getRangeByName('D2').setText('Exported Branches');
    sheet.getRangeByName('E2').setNumber(sorted.length.toDouble());

    _summaryCell(sheet, 'A3', 'Average Availability', '#E0F2FE');
    final averageCell = sheet.getRangeByName('B3');
    averageCell
      ..setNumber(average / 100)
      ..numberFormat = '0.0%';
    _summaryCell(sheet, 'D3', '97% and Above', '#DCFCE7');
    sheet.getRangeByName('E3').setNumber(atLeast97.toDouble());
    _summaryCell(sheet, 'G3', 'Below 97%', '#FEF3C7');
    sheet
        .getRangeByName('H3')
        .setNumber((sorted.length - atLeast97).toDouble());

    final headers = <String>[
      'Rank',
      'Branch',
      'Availability Rate',
      'Performance Band',
      'KPI Items',
      'Fully Covered Items',
      'Below 7-Day Need',
      'Top Seller Items',
      'Regular Seller Items',
      'Total 7-Day Need',
      'Current Branch Stock',
      'Units Missing',
      'Stock Date',
    ];
    for (var column = 1; column <= headers.length; column++) {
      final cell = sheet.getRangeByIndex(headerRow, column);
      cell.setText(headers[column - 1]);
      cell.cellStyle
        ..bold = true
        ..fontColor = '#FFFFFF'
        ..backColor = '#4EB0DE'
        ..hAlign = xlsio.HAlignType.center
        ..vAlign = xlsio.VAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      cell.cellStyle.borders.all.color = '#2B8DBA';
    }
    sheet.getRangeByIndex(headerRow, 1, headerRow, columnCount).rowHeight = 34;

    for (var index = 0; index < sorted.length; index++) {
      final branch = sorted[index];
      final row = headerRow + index + 1;
      final values = <Object?>[
        index + 1,
        branch.branchName,
        branch.availabilityRate / 100,
        _performanceBand(branch.availabilityRate),
        branch.masterItems,
        branch.fullyAvailableItems,
        branch.shortageItems,
        branch.paretoItems,
        branch.consistentItems,
        branch.weeklyNeed,
        branch.branchStock,
        branch.stockShortage,
        stockDate,
      ];
      for (var column = 1; column <= values.length; column++) {
        final cell = sheet.getRangeByIndex(row, column);
        final value = values[column - 1];
        if (value is num) {
          cell.setNumber(value.toDouble());
          cell.numberFormat = column == 3 ? '0.0%' : '#,##0.0';
        } else {
          cell.setText((value ?? '').toString());
        }
        cell.cellStyle
          ..vAlign = xlsio.VAlignType.center
          ..hAlign = column == 2
              ? xlsio.HAlignType.left
              : xlsio.HAlignType.center
          ..backColor = index.isOdd ? '#F8FAFC' : '#FFFFFF';
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        cell.cellStyle.borders.all.color = '#CBD5E1';
      }

      final rateCell = sheet.getRangeByIndex(row, 3);
      rateCell.cellStyle
        ..fontColor = branch.availabilityRate >= 97
            ? '#059669'
            : branch.availabilityRate >= 90
            ? '#D97706'
            : '#DC2626'
        ..bold = true;
      if (branch.stockShortage > 0) {
        sheet.getRangeByIndex(row, 12).cellStyle
          ..fontColor = '#DC2626'
          ..bold = true;
      }
    }

    sheet.getRangeByIndex(1, 1).columnWidth = 10;
    sheet.getRangeByIndex(1, 2).columnWidth = 30;
    sheet.getRangeByIndex(1, 3).columnWidth = 20;
    sheet.getRangeByIndex(1, 4).columnWidth = 20;
    for (var column = 5; column <= 12; column++) {
      sheet.getRangeByIndex(1, column).columnWidth = 20;
    }
    sheet.getRangeByIndex(1, 13).columnWidth = 16;
    if (sorted.isNotEmpty) {
      sheet.autoFilters.filterRange = sheet.getRangeByIndex(
        headerRow,
        1,
        headerRow + sorted.length,
        columnCount,
      );
    }

    final bytes = workbook.saveAsStream();
    workbook.dispose();
    final blob = html.Blob([
      Uint8List.fromList(bytes),
    ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    html.AnchorElement(href: url)
      ..setAttribute('download', 'Availability_Branch_Report_$timestamp.xlsx')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  static void _summaryCell(
    xlsio.Worksheet sheet,
    String address,
    String label,
    String color,
  ) {
    final cell = sheet.getRangeByName(address);
    cell.setText(label);
    cell.cellStyle
      ..bold = true
      ..backColor = color
      ..hAlign = xlsio.HAlignType.center
      ..vAlign = xlsio.VAlignType.center;
  }

  static String _performanceBand(num rate) {
    if (rate >= 97) return '97% and Above';
    if (rate >= 95) return '95% to 96.9%';
    if (rate >= 90) return '90% to 94.9%';
    return 'Below 90%';
  }
}
