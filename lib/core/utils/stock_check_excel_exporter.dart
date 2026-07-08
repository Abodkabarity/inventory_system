// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../domain/entities/stock_check_task.dart';

class StockCheckExcelExporter {
  static Future<void> export({
    required List<StockCheckTask> rows,
    required String title,
  }) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Stock Check Results';
    final showBarcodeSticker = rows.any(
      (row) => row.includeBarcodeStickerCheck,
    );

    final headers = [
      '#',
      'Title',
      'Branch',
      'Item Code',
      'Item Name',
      'System Qty',
      'Actual Qty',
      'Variance',
      if (showBarcodeSticker) 'Barcode Sticker is Correct',
      'Status',
      'Note',
      'Submitted At',
    ];

    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(1, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle
        ..bold = true
        ..fontColor = '#FFFFFF'
        ..backColor = '#2563EB'
        ..hAlign = xlsio.HAlignType.center
        ..vAlign = xlsio.VAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      cell.cellStyle.borders.all.color = '#0F172A';
    }

    final sorted = [...rows]
      ..sort((a, b) {
        final branch = a.branchName.compareTo(b.branchName);
        if (branch != 0) return branch;
        return a.itemCode.compareTo(b.itemCode);
      });

    for (var r = 0; r < sorted.length; r++) {
      final row = sorted[r];
      final values = [
        r + 1,
        row.title,
        row.branchName,
        row.itemCode,
        row.itemName,
        row.systemQty ?? '',
        row.actualQty ?? '',
        row.variance ?? '',
        if (showBarcodeSticker)
          row.includeBarcodeStickerCheck
              ? _yesNo(row.barcodeStickerIsCorrect)
              : '',
        row.isSubmitted ? 'Submitted' : 'Pending',
        row.note,
        _format(row.submittedAt),
      ];

      for (var c = 0; c < values.length; c++) {
        final cell = sheet.getRangeByIndex(r + 2, c + 1);
        final value = values[c];
        if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText(value.toString());
        }
        cell.cellStyle
          ..hAlign = c == 4 || c == (showBarcodeSticker ? 10 : 9)
              ? xlsio.HAlignType.left
              : xlsio.HAlignType.center
          ..vAlign = xlsio.VAlignType.center;
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        cell.cellStyle.borders.all.color = '#CBD5E1';
        if (r.isEven) cell.cellStyle.backColor = '#F8FAFC';
      }
    }

    final widths = <int, double>{
      1: 7,
      2: 30,
      3: 24,
      4: 18,
      5: 44,
      6: 13,
      7: 13,
      8: 12,
      if (showBarcodeSticker) 9: 28,
      showBarcodeSticker ? 10 : 9: 14,
      showBarcodeSticker ? 11 : 10: 34,
      showBarcodeSticker ? 12 : 11: 20,
    };
    widths.forEach((column, width) {
      sheet.getRangeByIndex(1, column).columnWidth = width;
    });

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final safeTitle = _safe(title.isEmpty ? 'Stock Check' : title);
    final today = DateTime.now().toIso8601String().split('T').first;
    final blob = html.Blob([Uint8List.fromList(bytes)]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', '${safeTitle}_Results_$today.xlsx')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  static String _format(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  static String _yesNo(bool? value) {
    if (value == null) return '';
    return value ? 'Yes' : 'No';
  }

  static String _safe(String value) {
    final safe = value.trim().replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-');
    return safe.isEmpty ? 'Stock Check' : safe;
  }
}
