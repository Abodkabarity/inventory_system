import 'dart:async';

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../domain/entities/purchase_status_record.dart';

class PurchaseStatusExcelWorkbook {
  static Future<List<int>> build(
    List<PurchaseStatusRecord> records,
    List<PurchaseStatusOption> statuses,
  ) async {
    final workbook = xlsio.Workbook(2);
    final sheet = workbook.worksheets[0]..name = 'Purchase Status';
    final statusSheet = workbook.worksheets[1]..name = 'StatusOptions';

    const visibleHeaderCount = 11;
    const headers = [
      'Review Status',
      'Item Code',
      'Item Name',
      'Status',
      'Status Date',
      'Alternative Item Code',
      'Alternative Item Name',
      'Purchase Status',
      'Category',
      'Supplier',
      'Note',
      '_RECORD_ID',
      '_ORIGINAL_STATUS',
      '_ORIGINAL_STATUS_DATE',
      '_ORIGINAL_ALT_CODE',
      '_ORIGINAL_ALT_NAME',
      '_ORIGINAL_NOTE',
    ];

    final title = sheet.getRangeByIndex(1, 1, 1, visibleHeaderCount)..merge();
    title.setText('PURCHASE STATUS REPORT');
    title.cellStyle
      ..backColor = '#4EB0DE'
      ..fontColor = '#FFFFFF'
      ..bold = true
      ..fontSize = 16
      ..hAlign = xlsio.HAlignType.center
      ..vAlign = xlsio.VAlignType.center;
    title.rowHeight = 30;

    final subtitle = sheet.getRangeByIndex(2, 1, 2, visibleHeaderCount)
      ..merge();
    subtitle.setText(
      'Exported ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now())}  •  ${records.length} records',
    );
    subtitle.cellStyle
      ..fontColor = '#475569'
      ..italic = true
      ..hAlign = xlsio.HAlignType.center;
    subtitle.rowHeight = 22;

    for (var column = 0; column < headers.length; column++) {
      final cell = sheet.getRangeByIndex(4, column + 1);
      cell.setText(headers[column]);
      cell.cellStyle
        ..backColor = '#122D40'
        ..fontColor = '#FFFFFF'
        ..bold = true
        ..hAlign = xlsio.HAlignType.center
        ..vAlign = xlsio.VAlignType.center;
      cell.cellStyle.borders.all
        ..lineStyle = xlsio.LineStyle.thin
        ..color = '#0B1B2A';
    }
    sheet.getRangeByIndex(4, 1, 4, headers.length).rowHeight = 26;

    for (var index = 0; index < records.length; index++) {
      final record = records[index];
      final rowNumber = index + 5;
      // Export the persisted value exactly as it is. The review dialog may
      // suggest today's date, but exporting must never create a false change.
      final exportedStatusDate = record.statusDate ?? '';
      final values = <Object>[
        record.isPending
            ? 'PENDING - ${record.wasAlreadyExisting ? 'ALREADY EXISTS' : 'NEW ITEM'}'
            : 'COMPLETE',
        record.itemCode,
        record.itemName,
        record.statusName,
        exportedStatusDate,
        record.alternativeItemCode,
        record.alternativeItemName,
        record.purchaseStatus,
        record.category,
        record.supplier,
        record.note,
        record.id,
        record.statusName,
        exportedStatusDate,
        record.alternativeItemCode,
        record.alternativeItemName,
        record.note,
      ];

      for (var column = 0; column < values.length; column++) {
        final cell = sheet.getRangeByIndex(rowNumber, column + 1);
        final value = values[column];
        if (value is DateTime) {
          cell
            ..setDateTime(value)
            ..numberFormat = 'dd/mm/yyyy';
        } else if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText(value.toString());
        }
        cell.cellStyle
          ..vAlign = xlsio.VAlignType.center
          ..wrapText = true;
        cell.cellStyle.borders.all
          ..lineStyle = xlsio.LineStyle.thin
          ..color = '#CBD5E1';
        if (index.isOdd) cell.cellStyle.backColor = '#F8FAFC';
      }
      sheet.getRangeByIndex(rowNumber, 1, rowNumber, headers.length).rowHeight =
          22;
      if (index > 0 && index % 250 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    const widths = <double>[27, 16, 48, 28, 16, 23, 38, 26, 22, 30, 34];
    for (var i = 0; i < widths.length; i++) {
      sheet.getRangeByIndex(1, i + 1).columnWidth = widths[i];
    }

    final statusNames = statuses
        .map((status) => status.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
    for (var index = 0; index < statusNames.length; index++) {
      statusSheet.getRangeByIndex(index + 1, 1).setText(statusNames[index]);
    }
    if (records.isNotEmpty && statusNames.isNotEmpty) {
      final validation = sheet
          .getRangeByIndex(5, 4, records.length + 4, 4)
          .dataValidation;
      validation
        ..dataRange = statusSheet.getRangeByIndex(1, 1, statusNames.length, 1)
        ..showPromptBox = true
        ..promptBoxTitle = 'Purchase Status'
        ..promptBoxText =
            'Choose an existing status or type a new status manually.'
        ..showErrorBox = false;
    }
    statusSheet.visibility = xlsio.WorksheetVisibility.hidden;
    for (
      var column = visibleHeaderCount + 1;
      column <= headers.length;
      column++
    ) {
      sheet.getRangeByIndex(1, column).columnWidth = 2;
      sheet.columns[column]!.isHidden = true;
    }

    if (records.isNotEmpty) {
      sheet.autoFilters.filterRange = sheet.getRangeByIndex(
        4,
        1,
        records.length + 4,
        visibleHeaderCount,
      );
    }

    await Future<void>.delayed(Duration.zero);
    final bytes = workbook.saveAsStream();
    workbook.dispose();
    return bytes;
  }
}
