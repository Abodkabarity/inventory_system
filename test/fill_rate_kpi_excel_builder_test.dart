import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:daily_order/core/utils/fill_rate_kpi_excel_builder.dart';
import 'package:daily_order/data/datasources/remote/fill_rate_kpi_remote_ds.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => StoreBranchIdentityRegistry.groups.value = const {});
  test('management export contains all explained report sheets', () {
    StoreBranchIdentityRegistry.groups.value = {'AL AIN MAIN': '71'};
    const summary = FillRateSummary(
      branchName: 'ALL BRANCHES',
      totalItems: 50,
      suppliedItems: 18,
      fullySupplied: 14,
      partiallySupplied: 4,
      notSupplied: 32,
      requiredQty: 210,
      suppliedQty: 95,
      lineFillRate: 34,
      unitFillRate: 45.24,
    );
    const statuses = [
      FillRateStatus(
        name: 'AVAILABLE',
        totalItems: 20,
        suppliedItems: 10,
        share: 40,
        lineFillRate: 50,
        unitFillRate: 60,
        requiredQty: 100,
        suppliedQty: 60,
      ),
      FillRateStatus(
        name: 'Not Assigned',
        totalItems: 20,
        suppliedItems: 8,
        share: 40,
        lineFillRate: 30,
        unitFillRate: 35,
        requiredQty: 100,
        suppliedQty: 35,
      ),
      FillRateStatus(
        name: 'PENDING AGREEMENT',
        totalItems: 10,
        suppliedItems: 0,
        share: 20,
        lineFillRate: 0,
        unitFillRate: 0,
        requiredQty: 10,
        suppliedQty: 0,
      ),
    ];
    final item = FillRateItem(
      totalCount: 1,
      date: DateTime(2026, 8, 11),
      branchName: 'AL AIN MAIN',
      itemCode: '16-01-00275',
      itemName: 'AMARYL 4 MG TAB 30 S',
      originalQty: 6,
      requiredQty: 6,
      wasEdited: false,
      transferredQty: 1,
      suppliedQty: 1,
      fillRate: 16.67,
      fulfillmentStatus: 'Partially Supplied',
      purchaseStatus: 'AVAILABLE',
    );
    final report = FillRateReport(
      summaries: const [summary],
      daily: [
        FillRateDaily(
          date: DateTime(2026, 8, 11),
          totalItems: 50,
          suppliedItems: 18,
          fullySupplied: 14,
          partiallySupplied: 4,
          notSupplied: 32,
          lineFillRate: 34,
          unitFillRate: 45.24,
        ),
      ],
      statuses: statuses,
      items: [item],
    );

    final bytes = FillRateKpiExcelBuilder.build(
      from: DateTime(2026, 8, 11),
      to: DateTime(2026, 8, 11),
      branch: 'AL AIN MAIN',
      report: report,
      items: [item],
    );
    final qaDirectory = Directory('build/qa')..createSync(recursive: true);
    File(
      '${qaDirectory.path}/fill_rate_management_sample.xlsx',
    ).writeAsBytesSync(bytes);
    final archive = ZipDecoder().decodeBytes(bytes);
    String entry(String name) => utf8.decode(
      archive.files.firstWhere((file) => file.name == name).content,
    );
    final workbook = entry('xl/workbook.xml');
    final sharedStrings = entry('xl/sharedStrings.xml');
    expect(sharedStrings, contains('Scope: 71 AL AIN MAIN'));
    expect(sharedStrings, contains('>71 AL AIN MAIN<'));
    expect(item.branchName, 'AL AIN MAIN');

    expect(workbook, contains('Fill Rate Gap Analysis'));
    expect(workbook, contains('Item Details'));
    expect(workbook, isNot(contains('Branch Summary')));
    expect(workbook, isNot(contains('Purchase Status')));
    expect(workbook, isNot(contains('Daily Trend')));
    expect(
      sharedStrings,
      contains('Unfulfilled Gap Breakdown by Purchase Status'),
    );
    expect(sharedStrings, contains('Unfulfilled Gap'));
    expect(sharedStrings, contains('Share of Unfulfilled Gap %'));
    expect(sharedStrings, contains('Of All Reorder Qty %'));
    expect(sharedStrings, isNot(contains('Unit Fill Rate')));
    expect(sharedStrings, isNot(contains('Line Fill Rate')));
    expect(sharedStrings, isNot(contains('Average Product Supply')));
    expect(sharedStrings, isNot(contains('Included in Main Result')));
    expect(sharedStrings, isNot(contains('Management Interpretation')));
    expect(sharedStrings, isNot(contains('Simple Calculation Rules')));
    expect(
      sharedStrings,
      isNot(contains('COMBINED FILL RATE — QUANTITY RECEIVED')),
    );
    expect(sharedStrings, contains('Reorder Qty'));
    expect(sharedStrings, contains('Transfer from Store'));
    expect(sharedStrings, contains('Fill Rate'));
    expect(sharedStrings, isNot(contains('Original Reorder Qty')));
    expect(sharedStrings, isNot(contains('Effective Required Qty')));
    expect(sharedStrings, isNot(contains('Edited Order?')));
    expect(sharedStrings, isNot(contains('Approved Transfer Qty')));
    expect(sharedStrings, isNot(contains('Qty Counted')));
  });
}
