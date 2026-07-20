// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../data/datasources/remote/availability_kpi_remote_ds.dart';

class AvailabilityAllocationExcelExporter {
  static Future<void> export({
    required String stockDate,
    required List<AvailabilityAllocationRow> rows,
  }) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0]..name = 'Branch Allocation';
    const columnCount = 5;
    const headerRow = 4;

    final title = sheet.getRangeByIndex(1, 1, 1, columnCount)..merge();
    title.setText('Availability KPI — Branch Allocation');
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
    sheet.getRangeByName('C2').setText('Transfers');
    sheet.getRangeByName('D2').setNumber(rows.length.toDouble());
    sheet
        .getRangeByName('E2')
        .setText(
          'Total Qty: ${rows.fold<int>(0, (sum, row) => sum + row.qty)}',
        );

    const headers = <String>[
      'From Branch',
      'Item Code',
      'Item Name',
      'Qty',
      'To Branch',
    ];
    for (var column = 1; column <= columnCount; column++) {
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
    sheet.getRangeByIndex(headerRow, 1, headerRow, columnCount).rowHeight = 32;

    for (var index = 0; index < rows.length; index++) {
      final allocation = rows[index];
      final row = headerRow + index + 1;
      final values = <Object>[
        allocation.fromBranch,
        allocation.itemCode,
        allocation.itemName,
        allocation.qty,
        allocation.toBranch,
      ];
      for (var column = 1; column <= columnCount; column++) {
        final cell = sheet.getRangeByIndex(row, column);
        final value = values[column - 1];
        if (value is num) {
          cell.setNumber(value.toDouble());
          cell.numberFormat = '0';
        } else {
          cell.setText(value.toString());
        }
        cell.cellStyle
          ..hAlign = column == 3
              ? xlsio.HAlignType.left
              : xlsio.HAlignType.center
          ..vAlign = xlsio.VAlignType.center
          ..backColor = index.isOdd ? '#F8FAFC' : '#FFFFFF';
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        cell.cellStyle.borders.all.color = '#CBD5E1';
      }
    }

    sheet.getRangeByIndex(1, 1).columnWidth = 28;
    sheet.getRangeByIndex(1, 2).columnWidth = 18;
    sheet.getRangeByIndex(1, 3).columnWidth = 48;
    sheet.getRangeByIndex(1, 4).columnWidth = 12;
    sheet.getRangeByIndex(1, 5).columnWidth = 28;
    if (rows.isNotEmpty) {
      sheet.autoFilters.filterRange = sheet.getRangeByIndex(
        headerRow,
        1,
        headerRow + rows.length,
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
      ..setAttribute(
        'download',
        'Availability_Allocation_${stockDate}_$timestamp.xlsx',
      )
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}
