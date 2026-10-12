// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import '../../domain/entities/stock_check_task.dart';
import '../../domain/entities/stock_check_campaign.dart';
import '../../domain/entities/stock_check_kpi_comparison.dart';
import '../../domain/entities/stock_check_kpi_report.dart';
import 'stock_check_kpi_export_worker.dart';

const double _stockCheckAccuracyTolerance = 0.01;

class StockCheckProjectComparisonExportRow {
  final String branch;
  final String itemCode;
  final String itemName;
  final String firstProject;
  final bool firstIncluded;
  final num? firstSystemQty;
  final num? firstActualQty;
  final String secondProject;
  final bool secondIncluded;
  final num? secondSystemQty;
  final num? secondActualQty;

  const StockCheckProjectComparisonExportRow({
    required this.branch,
    required this.itemCode,
    required this.itemName,
    required this.firstProject,
    required this.firstIncluded,
    required this.firstSystemQty,
    required this.firstActualQty,
    required this.secondProject,
    required this.secondIncluded,
    required this.secondSystemQty,
    required this.secondActualQty,
  });

  bool get isInBothProjects => firstIncluded && secondIncluded;

  bool get isMatch {
    final first = _normalizedDifference(firstDifference);
    final second = _normalizedDifference(secondDifference);
    return first != null && second != null && (first - second).abs() <= 1e-9;
  }

  num? get firstDifference => firstSystemQty == null || firstActualQty == null
      ? null
      : firstActualQty!.toDouble() - firstSystemQty!.toDouble();

  num? get secondDifference =>
      secondSystemQty == null || secondActualQty == null
      ? null
      : secondActualQty!.toDouble() - secondSystemQty!.toDouble();

  static double? _normalizedDifference(num? value) {
    if (value == null) return null;
    final number = value.toDouble();
    return number.abs() <= _stockCheckAccuracyTolerance + 1e-9 ? 0 : number;
  }

  String get result {
    if (!isInBothProjects) return 'Only in one project';
    if (isMatch) return 'Match';
    return 'Changed';
  }
}

class StockCheckExcelExporter {
  static Future<void> exportKpiAnalysis({
    required StockCheckKpiReport report,
    KpiExportJob? job,
    void Function(KpiExportProgress)? onProgress,
  }) async {
    final exportJob = job ?? KpiExportJob();
    final bytes = await buildKpiAnalysisBytes(
      report: report,
      job: exportJob,
      onProgress: onProgress,
    );
    exportJob.checkCancelled();
    onProgress?.call(
      KpiExportProgress(
        KpiExportStage.downloading,
        processed: report.total,
        total: report.total,
      ),
    );
    final today = DateTime.now().toIso8601String().split('T').first;
    final url = html.Url.createObjectUrlFromBlob(
      html.Blob([
        bytes,
      ], 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'),
    );
    html.AnchorElement(href: url)
      ..setAttribute('download', 'Stock_Check_KPI_Analysis_$today.xlsx')
      ..click();
    // Allow the browser to consume the blob before releasing it.
    Future<void>.delayed(
      const Duration(seconds: 1),
      () => html.Url.revokeObjectUrl(url),
    );
  }

  static const _kpiSummaryHeaders = [
    'Branch',
    'Unique Products',
    'Scored',
    '100%',
    '0%',
    'Shared',
    'Single Project',
    'Awaiting or Review',
    'Accuracy %',
  ];

  // Header, odd-row tint, even-row tint. Keep a quarter's color stable even
  // when only some quarters are selected or projects span multiple years.
  static const _kpiQuarterColors = [
    ['2563EB', 'F2F7FF', 'E7EFFC'], // Q1: blue
    ['0F766E', 'EFFAF7', 'E0F2EC'], // Q2: teal
    ['7C3AED', 'F8F3FF', 'F0E6FC'], // Q3: purple
    ['B45309', 'FFF8EF', 'FFF0DB'], // Q4: amber
  ];

  static List<List<String>> _kpiProjectColors(StockCheckKpiReport report) => [
    for (var i = 0; i < report.projects.length; i++)
      _kpiQuarterColors[((report.projects[i].quarter ?? (i % 4 + 1)) - 1) % 4],
  ];

  static List<String> _kpiHeaders(StockCheckKpiReport report) => [
    'Branch',
    'Item Code',
    'Item Name',
    'Included Projects',
    'Type',
    'Result',
    for (final project in report.projects) ...[
      '${project.period.isEmpty ? project.title : project.period} | System Qty',
      '${project.period.isEmpty ? project.title : project.period} | Actual Qty',
      '${project.period.isEmpty ? project.title : project.period} | Difference',
    ],
    'Difference | ${report.projects.map((project) => project.period.isEmpty ? project.title : project.period).join(' vs ')}',
    'Accuracy %',
  ];

  static List<Object> _kpiTotals(String branch, StockCheckKpiTotals totals) => [
    branch,
    totals.total,
    totals.scored,
    totals.correct,
    totals.failed,
    totals.shared,
    totals.standalone,
    totals.awaiting,
    totals.accuracy ?? '',
  ];

  static List<Object> _kpiValues(
    StockCheckKpiItem item,
    StockCheckKpiReport report,
  ) => [
    item.branch,
    item.code,
    item.name,
    item.projectCount,
    item.shared ? 'Shared' : 'Single project',
    item.result,
    for (final project in report.projects) ...[
      item.rowFor(project.id)?.systemQty ?? '',
      item.rowFor(project.id)?.actualQty ?? '',
      if (item.rowFor(project.id) case final row?
          when StockCheckKpiItem.counted(row))
        row.variance!
      else
        '',
    ],
    item.comparisonDifference ?? '',
    item.score ?? '',
  ];

  static Future<Uint8List> buildKpiAnalysisBytes({
    required StockCheckKpiReport report,
    KpiExportJob? job,
    void Function(KpiExportProgress)? onProgress,
  }) {
    final headers = _kpiHeaders(report);
    return StockCheckKpiExportWorker.build(
      summaryHeaders: _kpiSummaryHeaders,
      detailHeaders: headers,
      projectColors: _kpiProjectColors(report),
      summaryWidths: [35, ...List.filled(8, 16)],
      detailWidths: [
        for (var i = 0; i < headers.length; i++)
          i == 0
              ? 35
              : i == 2
              ? 45
              : i == 5
              ? 55
              : i == headers.length - 2
              ? 42
              : 16,
      ],
      summaryRows: [
        _kpiTotals('ALL BRANCHES', report),
        for (final branch in report.branches.entries)
          _kpiTotals(branch.key, branch.value),
      ],
      detailRows: report.items.map((item) => _kpiValues(item, report)),
      totalRows: report.total,
      job: job ?? KpiExportJob(),
      onProgress: onProgress,
    );
  }

  static xlsio.Workbook buildKpiAnalysisWorkbook(StockCheckKpiReport report) {
    final workbook = xlsio.Workbook(2);
    final summary = workbook.worksheets[0]..name = 'KPI Summary';
    final details = workbook.worksheets[1]..name = 'Product Comparison';
    const summaryHeaders = _kpiSummaryHeaders;
    _writeHeader(summary, summaryHeaders, '#142D4E');
    void writeTotals(int row, String branch, StockCheckKpiTotals totals) {
      _writeRow(summary, row, _kpiTotals(branch, totals), leftColumns: {1});
    }

    writeTotals(2, 'ALL BRANCHES', report);
    var index = 3;
    for (final branch in report.branches.entries) {
      writeTotals(index++, branch.key, branch.value);
    }
    _setColumnWidths(summary, summaryHeaders, {'Branch': 35});
    final headers = _kpiHeaders(report);
    final projectColors = _kpiProjectColors(report);
    _writeHeader(details, headers, '#087E8B');
    for (var project = 0; project < projectColors.length; project++) {
      details
              .getRangeByIndex(1, 7 + project * 3, 1, 9 + project * 3)
              .cellStyle
              .backColor =
          '#${projectColors[project][0]}';
    }
    index = 2;
    for (final item in report.items) {
      final values = _kpiValues(item, report);
      _writeRow(details, index, values, leftColumns: {1, 2, 3, 6});
      for (var project = 0; project < projectColors.length; project++) {
        details
                .getRangeByIndex(index, 7 + project * 3, index, 9 + project * 3)
                .cellStyle
                .backColor =
            '#${projectColors[project][index.isEven ? 2 : 1]}';
      }
      final differenceCell = details.getRangeByIndex(index, headers.length - 1);
      if (item.comparisonDifference != null &&
          item.comparisonDifference!.abs() > StockCheckKpiItem.tolerance) {
        differenceCell.cellStyle.fontColor = '#B91C1C';
        differenceCell.cellStyle.bold = true;
      }
      final scoreCell = details.getRangeByIndex(index, headers.length);
      scoreCell.numberFormat = '0"%"';
      if (item.score != null) {
        scoreCell.cellStyle
          ..fontColor = item.score == 100 ? '#15803D' : '#B91C1C'
          ..backColor = item.score == 100 ? '#DCFCE7' : '#FEE2E2'
          ..bold = true;
      }
      index++;
    }
    _setColumnWidths(details, headers, {
      'Branch': 35,
      'Item Name': 45,
      'Result': 55,
      headers[headers.length - 2]: 42,
    });
    details.getRangeByIndex(1, 1, 1, headers.length).rowHeight = 60;
    details.getRangeByIndex(1, 1, 1, headers.length).cellStyle.wrapText = true;
    return workbook;
  }

  static Future<void> exportQuarterlyKpi({
    required StockCheckKpiComparison comparison,
    required StockCheckCampaign previous,
    required StockCheckCampaign current,
  }) async {
    final workbook = xlsio.Workbook(2);
    final summary = workbook.worksheets[0]..name = 'Quarterly KPI';
    final details = workbook.worksheets[1]..name = 'All Item Pairs';
    const summaryHeaders = [
      'Branch',
      'Baseline period',
      'Baseline campaign',
      'Baseline sender',
      'Current period',
      'Current campaign',
      'Current sender',
      'Comparable pairs',
      'Baseline accuracy %',
      'Current accuracy %',
      'Change pp',
      'Added',
      'Removed',
      'Awaiting counts',
    ];
    const detailHeaders = [
      'Branch',
      'Item Code',
      'Item Name',
      'Baseline period',
      'Baseline system',
      'Baseline actual',
      'Baseline variance',
      'Baseline status',
      'Current period',
      'Current system',
      'Current actual',
      'Current variance',
      'Current status',
      'Comparable',
      'Result',
    ];
    _writeHeader(summary, summaryHeaders, '#142D4E');
    _writeHeader(details, detailHeaders, '#087E8B');
    var index = 2;
    for (final entry in comparison.branches.entries) {
      final r = entry.value;
      _writeRow(
        summary,
        index++,
        [
          entry.key,
          previous.period,
          previous.title,
          previous.senderLabel,
          current.period,
          current.title,
          current.senderLabel,
          r.comparable.length,
          r.previousAccuracy ?? '',
          r.currentAccuracy ?? '',
          r.delta ?? '',
          r.items.where((e) => e.previous == null).length,
          r.items.where((e) => e.current == null).length,
          r.items
              .where(
                (e) => e.previous != null && e.current != null && !e.comparable,
              )
              .length,
        ],
        leftColumns: {1, 3, 4, 6, 7},
      );
    }
    index = 2;
    for (final item in comparison.items) {
      _writeRow(
        details,
        index++,
        [
          item.branch,
          item.code,
          item.name,
          previous.period,
          item.previous?.systemQty ?? '',
          item.previous?.actualQty ?? '',
          item.previous?.variance ?? '',
          item.previous?.status ?? 'Not included',
          current.period,
          item.current?.systemQty ?? '',
          item.current?.actualQty ?? '',
          item.current?.variance ?? '',
          item.current?.status ?? 'Not included',
          item.comparable ? 'Yes' : 'No',
          item.result,
        ],
        leftColumns: {1, 2, 3, 8, 13, 15},
      );
    }
    _setColumnWidths(summary, summaryHeaders, {
      'Branch': 28,
      'Baseline campaign': 40,
      'Current campaign': 40,
      'Baseline sender': 24,
      'Current sender': 24,
    });
    _setColumnWidths(details, detailHeaders, {
      'Branch': 28,
      'Item Code': 20,
      'Item Name': 48,
      'Result': 22,
    });
    summary.autoFilters.filterRange = summary.getRangeByIndex(
      1,
      1,
      comparison.branches.length + 1,
      summaryHeaders.length,
    );
    details.autoFilters.filterRange = details.getRangeByIndex(
      1,
      1,
      comparison.items.length + 1,
      detailHeaders.length,
    );
    summary.getRangeByName('A2').freezePanes();
    details.getRangeByName('A2').freezePanes();
    final bytes = workbook.saveAsStream();
    workbook.dispose();
    final blob = html.Blob([Uint8List.fromList(bytes)]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute(
        'download',
        'KPI_${_safe(previous.period)}_vs_${_safe(current.period)}.xlsx',
      )
      ..click();
    html.Url.revokeObjectUrl(url);
  }

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
    final showItemStatus = rows.any((row) => row.includeItemStatus);

    final headers = [
      '#',
      'Title',
      'Branch',
      'Item Code',
      'Item Name',
      'System Qty',
      'Actual Qty',
      'Variance',
      if (showItemStatus) 'Item Status',
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
        if (showItemStatus) row.includeItemStatus ? row.itemStatusDisplay : '',
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
          ..hAlign = headers[c] == 'Item Name' || headers[c] == 'Note'
              ? xlsio.HAlignType.left
              : xlsio.HAlignType.center
          ..vAlign = xlsio.VAlignType.center;
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        cell.cellStyle.borders.all.color = '#CBD5E1';
        if (r.isEven) cell.cellStyle.backColor = '#F8FAFC';
      }
    }

    _setColumnWidths(sheet, headers, const {
      '#': 7,
      'Title': 30,
      'Branch': 24,
      'Item Code': 18,
      'Item Name': 44,
      'System Qty': 13,
      'Actual Qty': 13,
      'Variance': 12,
      'Item Status': 22,
      'Barcode Sticker is Correct': 28,
      'Status': 14,
      'Note': 34,
      'Submitted By': 22,
      'Employee ID': 16,
      'Submitted At': 20,
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

  static Future<void> exportBranchResult({
    required List<StockCheckTask> rows,
    required String title,
  }) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'Branch Stock Check';
    final showItemStatus = rows.any((row) => row.includeItemStatus);

    final headers = [
      'Branch',
      'Item Code',
      'Item Name',
      'System Qty',
      'Actual Qty',
      'Difference',
      if (showItemStatus) 'Item Status',
      'Submitted By',
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
        final status = a.isPending == b.isPending
            ? 0
            : a.isPending
            ? -1
            : 1;
        if (status != 0) return status;
        return a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase());
      });

    for (var r = 0; r < sorted.length; r++) {
      final row = sorted[r];
      final values = [
        row.branchName,
        row.itemCode,
        row.itemName,
        row.systemQty ?? '',
        row.actualQty ?? '',
        row.variance ?? '',
        if (showItemStatus) row.includeItemStatus ? row.itemStatusDisplay : '',
        row.submittedByName,
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
          ..hAlign = c == 2 ? xlsio.HAlignType.left : xlsio.HAlignType.center
          ..vAlign = xlsio.VAlignType.center;
        cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
        cell.cellStyle.borders.all.color = '#CBD5E1';
        if (r.isEven) cell.cellStyle.backColor = '#F8FAFC';
      }
    }

    _setColumnWidths(sheet, headers, const {
      'Branch': 24,
      'Item Code': 18,
      'Item Name': 52,
      'System Qty': 14,
      'Actual Qty': 14,
      'Difference': 14,
      'Item Status': 22,
      'Submitted By': 28,
    });

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final safeTitle = _safe(title.isEmpty ? 'Stock Check' : title);
    final today = DateTime.now().toIso8601String().split('T').first;
    final blob = html.Blob([Uint8List.fromList(bytes)]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', '${safeTitle}_Branch_Result_$today.xlsx')
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

  static Future<void> exportProjectComparison({
    required List<StockCheckProjectComparisonExportRow> rows,
    required String title,
  }) async {
    final workbook = xlsio.Workbook(2);
    final summary = workbook.worksheets[0]..name = 'Branch Comparison';
    final details = workbook.worksheets[1]..name = 'Item Differences';
    final grouped = <String, List<StockCheckProjectComparisonExportRow>>{};
    for (final row in rows) {
      grouped.putIfAbsent(row.branch, () => []).add(row);
    }
    final branches = grouped.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    const summaryHeaders = [
      '#',
      'Branch',
      'First Project',
      'Second Project',
      'Compared Items',
      'Matching Items',
      'Different Items',
      'Match %',
      'Result',
    ];
    _writeHeader(summary, summaryHeaders, '#2563EB');
    for (var index = 0; index < branches.length; index++) {
      final branchRows = grouped[branches[index]]!;
      final matching = branchRows.where((row) => row.isMatch).length;
      final total = branchRows.length;
      final different = total - matching;
      final rate = total == 0 ? 100.0 : matching * 100 / total;
      final values = [
        index + 1,
        branches[index],
        branchRows.first.firstProject,
        branchRows.first.secondProject,
        total,
        matching,
        different,
        double.parse(rate.toStringAsFixed(1)),
        different == 0 ? '100% Match' : '${rate.toStringAsFixed(1)}% Match',
      ];
      _writeRow(summary, index + 2, values, leftColumns: const {2, 3, 4, 9});
      if (different == 0) {
        summary.getRangeByIndex(index + 2, 9).cellStyle
          ..fontColor = '#15803D'
          ..bold = true;
      }
    }
    const detailHeaders = [
      'Branch',
      'Item Code',
      'Item Name',
      'First Project',
      'First System',
      'First Actual',
      'First Difference',
      'Second Project',
      'Second System',
      'Second Actual',
      'Second Difference',
      'Result',
    ];
    _writeHeader(details, detailHeaders, '#0F766E');
    final differences = rows.where((row) => !row.isMatch).toList()
      ..sort((a, b) {
        final branch = a.branch.toLowerCase().compareTo(b.branch.toLowerCase());
        return branch != 0
            ? branch
            : a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase());
      });
    for (var index = 0; index < differences.length; index++) {
      final row = differences[index];
      _writeRow(
        details,
        index + 2,
        [
          row.branch,
          row.itemCode,
          row.itemName,
          row.firstProject,
          row.firstSystemQty ?? '',
          row.firstActualQty ?? '',
          row.firstDifference ?? '',
          row.secondProject,
          row.secondSystemQty ?? '',
          row.secondActualQty ?? '',
          row.secondDifference ?? '',
          row.result,
        ],
        leftColumns: const {1, 2, 3, 4, 8, 12},
      );
    }
    if (differences.isEmpty) {
      details
          .getRangeByIndex(2, 1)
          .setText('All branches and items match 100%.');
      details.getRangeByIndex(2, 1).cellStyle
        ..fontColor = '#15803D'
        ..bold = true;
    }

    <int, double>{
      1: 7,
      2: 28,
      3: 34,
      4: 34,
      5: 16,
      6: 16,
      7: 16,
      8: 13,
      9: 18,
    }.forEach(
      (column, width) => summary.getRangeByIndex(1, column).columnWidth = width,
    );
    <int, double>{
      1: 28,
      2: 18,
      3: 46,
      4: 34,
      5: 14,
      6: 14,
      7: 16,
      8: 34,
      9: 14,
      10: 14,
      11: 16,
      12: 22,
    }.forEach(
      (column, width) => details.getRangeByIndex(1, column).columnWidth = width,
    );

    final bytes = workbook.saveAsStream();
    workbook.dispose();
    final safeTitle = _safe(title.isEmpty ? 'Stock Check Comparison' : title);
    final today = DateTime.now().toIso8601String().split('T').first;
    final blob = html.Blob([Uint8List.fromList(bytes)]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', '${safeTitle}_$today.xlsx')
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  static void _writeHeader(
    xlsio.Worksheet sheet,
    List<String> headers,
    String color,
  ) {
    for (var index = 0; index < headers.length; index++) {
      final cell = sheet.getRangeByIndex(1, index + 1);
      cell.setText(headers[index]);
      cell.cellStyle
        ..bold = true
        ..fontColor = '#FFFFFF'
        ..backColor = color
        ..hAlign = xlsio.HAlignType.center
        ..vAlign = xlsio.VAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
    }
  }

  static void _setColumnWidths(
    xlsio.Worksheet sheet,
    List<String> headers,
    Map<String, double> widths,
  ) {
    for (var index = 0; index < headers.length; index++) {
      sheet.getRangeByIndex(1, index + 1).columnWidth =
          widths[headers[index]] ?? 16;
    }
  }

  static void _writeRow(
    xlsio.Worksheet sheet,
    int rowIndex,
    List<Object> values, {
    Set<int> leftColumns = const {},
  }) {
    for (var index = 0; index < values.length; index++) {
      final cell = sheet.getRangeByIndex(rowIndex, index + 1);
      final value = values[index];
      if (value is num) {
        cell.setNumber(value.toDouble());
      } else {
        cell.setText(value.toString());
      }
      cell.cellStyle
        ..hAlign = leftColumns.contains(index + 1)
            ? xlsio.HAlignType.left
            : xlsio.HAlignType.center
        ..vAlign = xlsio.VAlignType.center;
      cell.cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;
      cell.cellStyle.borders.all.color = '#CBD5E1';
      if (rowIndex.isEven) cell.cellStyle.backColor = '#F8FAFC';
    }
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
