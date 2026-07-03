// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../domain/entities/branch_allocation_task.dart';

class BranchAllocationExcelExporter {
  static Future<void> export({
    required List<BranchAllocationTask> rows,
    required String mode,
    required String branchName,
    required String title,
  }) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = mode == 'incoming' ? 'Incoming' : 'To Send';

    final headers = mode == 'incoming'
        ? const [
            '#',
            'Batch',
            'Run Date',
            'From Branch',
            'Item Code',
            'Item Name',
            'Original Qty',
            'Qty Send',
            'Status',
            'Sender Note',
            'Sent At',
          ]
        : const [
            '#',
            'Batch',
            'Run Date',
            'To Branch',
            'Item Code',
            'Item Name',
            'Original Qty',
            'Qty Send',
            'Status',
            'Sender Note',
            'Sent At',
          ];

    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.getRangeByIndex(1, c + 1);
      cell.setText(headers[c]);
      cell.cellStyle.bold = true;
      cell.cellStyle.fontColor = '#FFFFFF';
      cell.cellStyle.backColor = mode == 'incoming' ? '#0EA5E9' : '#F59E0B';
      cell.cellStyle.hAlign = xlsio.HAlignType.center;
      cell.cellStyle.vAlign = xlsio.VAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      cell.cellStyle.borders.all.color = '#0F172A';
    }

    final sorted = [...rows]
      ..sort((a, b) {
        final branchCompare = mode == 'incoming'
            ? a.fromBranch.compareTo(b.fromBranch)
            : a.toBranch.compareTo(b.toBranch);
        if (branchCompare != 0) return branchCompare;
        return a.itemName.compareTo(b.itemName);
      });

    for (var r = 0; r < sorted.length; r++) {
      final row = sorted[r];
      final values = mode == 'incoming'
          ? [
              r + 1,
              row.batchId,
              row.runDate,
              row.fromBranch,
              row.itemCode,
              row.itemName,
              row.qty,
              row.qtySend,
              _statusText(row),
              row.senderNote,
              _formatDateTime(row.sentAt),
            ]
          : [
              r + 1,
              row.batchId,
              row.runDate,
              row.toBranch,
              row.itemCode,
              row.itemName,
              row.qty,
              row.qtySend,
              _statusText(row),
              row.senderNote,
              _formatDateTime(row.sentAt),
            ];

      for (var c = 0; c < values.length; c++) {
        final cell = sheet.getRangeByIndex(r + 2, c + 1);
        final value = values[c];

        if (value is num) {
          cell.setNumber(value.toDouble());
        } else {
          cell.setText(value.toString());
        }

        cell.cellStyle.hAlign = (c == 5 || c == 9)
            ? xlsio.HAlignType.left
            : xlsio.HAlignType.center;
        cell.cellStyle.vAlign = xlsio.VAlignType.center;
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        cell.cellStyle.borders.all.color = '#CBD5E1';
        if (r.isEven) {
          cell.cellStyle.backColor = '#F8FAFC';
        }
      }
    }

    final widths = <int, double>{
      1: 7,
      2: 28,
      3: 14,
      4: 24,
      5: 18,
      6: 46,
      7: 14,
      8: 14,
      9: 16,
      10: 38,
      11: 18,
    };
    widths.forEach((index, width) {
      sheet.getRangeByIndex(1, index).columnWidth = width;
    });

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final safeBranch = _safeFileName(branchName);
    final safeTitle = _safeFileName(title.isEmpty ? 'Allocation' : title);
    final today = DateTime.now().toIso8601String().split('T').first;
    final fileName =
        '${safeBranch}_${safeTitle}_${mode == 'incoming' ? 'Incoming' : 'To Send'}_$today.xlsx';

    final blob = html.Blob([Uint8List.fromList(bytes)]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  static String _statusText(BranchAllocationTask row) {
    if (row.isSenderConfirmed) return 'Confirmed';
    if (row.isNoSend) return 'Rejected';
    return 'Pending';
  }

  static String _formatDateTime(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }

  static String _safeFileName(String value) {
    final safe = value.trim().replaceAll(RegExp(r'[\\/:*?"<>|]+'), '-');
    return safe.isEmpty ? 'Allocation' : safe;
  }
}
