// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../domain/entities/stock_check_task.dart';

const double _stockCheckAccuracyTolerance = 0.01;

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
      'Submitted By',
      'Employee ID',
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
        row.submittedByName,
        row.submittedByEmployeeId,
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
      showBarcodeSticker ? 12 : 11: 22,
      showBarcodeSticker ? 13 : 12: 16,
      showBarcodeSticker ? 14 : 13: 20,
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

  static Future<void> exportAnalysis({
    required List<StockCheckTask> rows,
    required String title,
  }) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Accuracy Analysis';

    final branchRows = _buildBranchAnalysis(rows);
    final headers = [
      '#',
      'Branch',
      'Projects',
      'Total Items',
      'Submitted',
      'Pending',
      'Counted Items',
      'Correct Items',
      'Different Items',
      'Accuracy %',
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

    for (var r = 0; r < branchRows.length; r++) {
      final row = branchRows[r];
      final values = [
        r + 1,
        row.branch,
        row.projects,
        row.total,
        row.submitted,
        row.pending,
        row.counted,
        row.correct,
        row.different,
        row.accuracyRate,
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
          ..hAlign = c == 1 ? xlsio.HAlignType.left : xlsio.HAlignType.center
          ..vAlign = xlsio.VAlignType.center;
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        cell.cellStyle.borders.all.color = '#CBD5E1';
        if (r.isEven) {
          cell.cellStyle.backColor = '#F8FAFC';
        }
      }
    }

    final detailSheet = workbook.worksheets.addWithName('Compared Rows');
    final detailHeaders = [
      'Branch',
      'Item Code',
      'Item Name',
      'System Qty',
      'Actual Qty',
      'Difference',
      'Project',
      'Submitted By',
      'Employee ID',
      'Note',
    ];
    for (var i = 0; i < detailHeaders.length; i++) {
      final cell = detailSheet.getRangeByIndex(1, i + 1);
      cell.setText(detailHeaders[i]);
      cell.cellStyle
        ..bold = true
        ..fontColor = '#FFFFFF'
        ..backColor = '#0F766E'
        ..hAlign = xlsio.HAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
    }
    final sortedRows = [...rows]
      ..sort((a, b) {
        final branch = a.branchName.compareTo(b.branchName);
        if (branch != 0) return branch;
        final item = a.itemCode.compareTo(b.itemCode);
        if (item != 0) return item;
        return a.title.compareTo(b.title);
      });
    for (var r = 0; r < sortedRows.length; r++) {
      final row = sortedRows[r];
      final values = [
        row.branchName,
        row.itemCode,
        row.itemName,
        row.systemQty ?? '',
        row.actualQty ?? '',
        row.variance ?? '',
        row.title,
        row.submittedByName,
        row.submittedByEmployeeId,
        row.note,
      ];
      for (var c = 0; c < values.length; c++) {
        final cell = detailSheet.getRangeByIndex(r + 2, c + 1);
        final value = values[c];
        if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText(value.toString());
        }
        cell.cellStyle
          ..hAlign = c == 2 || c == 6 || c == 9
              ? xlsio.HAlignType.left
              : xlsio.HAlignType.center
          ..vAlign = xlsio.VAlignType.center;
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        cell.cellStyle.borders.all.color = '#CBD5E1';
        if (_isCounted(row) && !_isCorrect(row)) {
          cell.cellStyle.backColor = '#FFF7ED';
        }
      }
    }

    final widths = <int, double>{
      1: 7,
      2: 26,
      3: 12,
      4: 12,
      5: 12,
      6: 12,
      7: 14,
      8: 12,
      9: 12,
      10: 12,
    };
    widths.forEach((column, width) {
      sheet.getRangeByIndex(1, column).columnWidth = width;
    });
    <int, double>{
      1: 24,
      2: 18,
      3: 44,
      4: 13,
      5: 13,
      6: 12,
      7: 32,
      8: 22,
      9: 16,
      10: 34,
    }.forEach((column, width) {
      detailSheet.getRangeByIndex(1, column).columnWidth = width;
    });

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final safeTitle = _safe(title.isEmpty ? 'Stock Check Analysis' : title);
    final today = DateTime.now().toIso8601String().split('T').first;
    final blob = html.Blob([Uint8List.fromList(bytes)]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', '${safeTitle}_$today.xlsx')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  static List<_BranchAnalysisExportRow> _buildBranchAnalysis(
    List<StockCheckTask> rows,
  ) {
    final byBranch = <String, List<StockCheckTask>>{};
    for (final row in rows) {
      byBranch.putIfAbsent(row.branchName, () => []).add(row);
    }
    final result = byBranch.entries.map((entry) {
      final branchRows = entry.value;
      final submitted = branchRows.where((row) => row.isSubmitted).length;
      final pending = branchRows.length - submitted;
      final counted = branchRows.where(_isCounted).length;
      final correct = branchRows.where(_isCorrect).length;
      return _BranchAnalysisExportRow(
        branch: entry.key,
        projects: branchRows.map((row) => row.batchId).toSet().length,
        total: branchRows.length,
        submitted: submitted,
        pending: pending,
        counted: counted,
        correct: correct,
        different: counted - correct,
        accuracyRate: counted == 0
            ? 0
            : double.parse((correct * 100 / counted).toStringAsFixed(1)),
      );
    }).toList();
    result.sort((a, b) {
      final accuracy = a.accuracyRate.compareTo(b.accuracyRate);
      if (accuracy != 0) return accuracy;
      return a.pending.compareTo(b.pending);
    });
    return result;
  }

  static bool _isCounted(StockCheckTask row) {
    if (row.systemQty == null || row.actualQty == null) return false;
    return true;
  }

  static bool _isCorrect(StockCheckTask row) {
    return _isCounted(row) &&
        (row.variance ?? 0).toDouble().abs() <=
            _stockCheckAccuracyTolerance + 1e-9;
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

class _BranchAnalysisExportRow {
  final String branch;
  final int projects;
  final int total;
  final int submitted;
  final int pending;
  final int counted;
  final int correct;
  final int different;
  final double accuracyRate;

  const _BranchAnalysisExportRow({
    required this.branch,
    required this.projects,
    required this.total,
    required this.submitted,
    required this.pending,
    required this.counted,
    required this.correct,
    required this.different,
    required this.accuracyRate,
  });
}
