// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../domain/entities/branch_submission_miss.dart';

class BranchSubmissionTrackerExcelExporter {
  static Future<void> export({
    required List<BranchSubmissionMiss> rows,
    required DateTime from,
    required DateTime to,
  }) async {
    final workbook = xlsio.Workbook();
    final summary = workbook.worksheets[0];
    summary.name = 'Branch Summary';
    final details = workbook.worksheets.addWithName('Missed Details');

    _buildSummary(summary, rows);
    _buildDetails(details, rows);

    final safeFrom = DateFormat('yyyyMMdd').format(from);
    final safeTo = DateFormat('yyyyMMdd').format(to);
    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final blob = html.Blob([
      Uint8List.fromList(bytes),
    ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute(
        'download',
        'Branch_Submission_Tracker_${safeFrom}_to_$safeTo.xlsx',
      )
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  static void _buildSummary(
    xlsio.Worksheet sheet,
    List<BranchSubmissionMiss> rows,
  ) {
    final byBranch = <String, List<BranchSubmissionMiss>>{};
    for (final row in rows) {
      byBranch.putIfAbsent(row.branchName, () => []).add(row);
    }

    _writeHeaders(sheet, const [
      '#',
      'Branch',
      'Zone',
      'Zone Manager',
      'Area',
      'Branch Type',
      'Missed Days',
      'Not Submitted',
      'Not Submitted By Branch',
      'Max Delay Hours',
      'Last Miss Date',
    ]);

    final entries = byBranch.entries.toList()
      ..sort((a, b) {
        final count = b.value.length.compareTo(a.value.length);
        if (count != 0) return count;
        return a.key.compareTo(b.key);
      });

    for (var i = 0; i < entries.length; i++) {
      final rows = entries[i].value;
      rows.sort((a, b) => b.runDate.compareTo(a.runDate));
      final first = rows.first;
      final notSubmitted = rows.where((row) => row.isNotSubmitted).length;
      final lateSubmitted = rows.where((row) => row.isLateSubmitted).length;
      final maxLateMinutes = rows.fold<int>(
        0,
        (max, row) => row.minutesLate > max ? row.minutesLate : max,
      );

      final values = [
        i + 1,
        entries[i].key,
        first.zone,
        first.zoneManager,
        first.area,
        first.branchType,
        rows.length,
        notSubmitted,
        lateSubmitted,
        (maxLateMinutes / 60).toStringAsFixed(1),
        _date(rows.first.runDate),
      ];
      _writeRow(sheet, i + 2, values);
    }

    _finish(sheet, 11);
  }

  static void _buildDetails(
    xlsio.Worksheet sheet,
    List<BranchSubmissionMiss> rows,
  ) {
    _writeHeaders(sheet, const [
      '#',
      'Run Date',
      'Branch',
      'Zone',
      'Zone Manager',
      'Zone Manager Email',
      'Area',
      'Branch Type',
      'Expected Submit By',
      'Submitted At',
      'Status',
      'Delay Minutes',
      'Delay Hours',
    ]);

    final sorted = [...rows]
      ..sort((a, b) {
        final date = b.runDate.compareTo(a.runDate);
        if (date != 0) return date;
        return a.branchName.compareTo(b.branchName);
      });

    for (var i = 0; i < sorted.length; i++) {
      final row = sorted[i];
      _writeRow(sheet, i + 2, [
        i + 1,
        _date(row.runDate),
        row.branchName,
        row.zone,
        row.zoneManager,
        row.zoneManagerEmail,
        row.area,
        row.branchType,
        _dateTime(row.expectedSubmitBy),
        row.submittedAt == null ? '' : _dateTime(row.submittedAt!),
        _status(row.status),
        row.minutesLate,
        (row.minutesLate / 60).toStringAsFixed(1),
      ]);
    }

    _finish(sheet, 13);
  }

  static void _writeHeaders(xlsio.Worksheet sheet, List<String> headers) {
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
  }

  static void _writeRow(xlsio.Worksheet sheet, int row, List<Object?> values) {
    for (var i = 0; i < values.length; i++) {
      final cell = sheet.getRangeByIndex(row, i + 1);
      final value = values[i];
      if (value is num) {
        cell.setNumber(value.toDouble());
      } else {
        cell.setText((value ?? '').toString());
      }
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      cell.cellStyle.borders.all.color = '#CBD5E1';
      cell.cellStyle.vAlign = xlsio.VAlignType.center;
    }
  }

  static void _finish(xlsio.Worksheet sheet, int columns) {
    for (var i = 1; i <= columns; i++) {
      sheet.autoFitColumn(i);
    }
    sheet.autoFilters.filterRange = sheet.getRangeByIndex(
      1,
      1,
      sheet.getLastRow(),
      columns,
    );
  }

  static String _date(DateTime value) => DateFormat('dd/MM/yyyy').format(value);
  static String _dateTime(DateTime value) =>
      DateFormat('dd/MM/yyyy HH:mm').format(value.toLocal());

  static String _status(String _) => 'Not Submitted By Branch';
}
