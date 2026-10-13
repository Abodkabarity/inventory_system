// ignore_for_file: depend_on_referenced_packages
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:async';
import 'dart:ui_web' as ui_web;
import 'package:archive/archive.dart';
import 'package:daily_order/core/theme/app_colors.dart';
import 'package:daily_order/core/utils/stock_check_excel_exporter.dart';
import 'package:daily_order/core/utils/stock_check_kpi_export_worker.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/domain/entities/stock_check_campaign.dart';
import 'package:daily_order/domain/entities/stock_check_kpi_report.dart';
import 'package:daily_order/domain/entities/stock_check_task.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_check_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_check_kpi_analysis_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xml/xml.dart';

var _workerAssetRequests = 0;

StockCheckKpiReport exportFixture({int products = 4, int quarters = 4}) =>
    StockCheckKpiReport(
      projects: [
        for (var q = 1; q <= quarters; q++)
          StockCheckCampaign({
            'batch_id': 'q$q',
            'title': 'Long project title Q$q',
            'kpi_year': 2026,
            'kpi_quarter': q,
          }),
      ],
      rows: [
        for (var i = 0; i < products; i++)
          for (var q = 1; q <= (i == 1 ? 1 : quarters); q++)
            StockCheckTask.fromMap({
              'id': '$q-$i',
              'batch_id': 'q$q',
              'branch_name': 'Branch A',
              'item_code': 'P${i.toString().padLeft(5, '0')}',
              'item_name': 'Medicine $i',
              'system_qty': 10,
              'actual_qty': i == 2 ? null : (i == 0 && q == 2 ? 12 : 10),
              'status': i == 2 ? 'pending' : 'submitted',
            }),
      ],
    );

XmlDocument exportXml(Archive archive, String path) => XmlDocument.parse(
  utf8.decode(archive.findFile(path)!.content as List<int>),
);

String exportCell(XmlDocument sheet, String address, List<String> strings) {
  final cell = sheet
      .findAllElements('c')
      .firstWhere((c) => c.getAttribute('r') == address);
  final value = cell.getElement('v')?.innerText ?? '';
  return cell.getAttribute('t') == 's' ? strings[int.parse(value)] : value;
}

Future<List<http.Request>> showStockCheck(
  WidgetTester tester, {
  String source = 'inventory',
  String? role,
  String? userName = '  Maya  ',
  bool signedIn = false,
  List<Map<String, dynamic>>? campaignSummaries,
  List<Map<String, dynamic>>? taskRows,
  Future<void> Function(http.Request)? beforeResponse,
}) async {
  const size = Size(2000, 1400);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final requests = <http.Request>[];
  final client = SupabaseClient(
    'https://example.supabase.co',
    'key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      requests.add(request);
      await beforeResponse?.call(request);
      Object result = [];
      if (request.url.path.endsWith('/app_users')) {
        result = [
          {'role': role ?? source, 'user_name': userName, 'is_active': true},
        ];
      }
      if (request.url.path.endsWith('/v_item_filters_for_orders')) {
        result = [
          {'item_code': 'TEST-01', 'item_name': 'Sample'},
        ];
      }
      if (request.url.path.endsWith('/branches')) {
        result = [
          {'branch_name': 'Branch A', 'email': 'branch@example.com'},
        ];
      }
      if (request.method == 'GET' &&
          request.url.path.endsWith('/stock_check_campaigns')) {
        result =
            campaignSummaries ??
            [
              for (final origin
                  in source == 'inventory' ? ['inventory', 'store'] : ['store'])
                {
                  'batch_id': '$origin-a',
                  'title': origin == 'inventory' ? 'Inventory A' : 'Store A',
                  'source': origin,
                  'total': 1,
                  'submitted': 1,
                  'branches': 1,
                  'products': 1,
                  'sent_at': '${DateTime.now().year}-01-01T10:00:00Z',
                  'expires_at': '2030-01-01T10:00:00Z',
                },
            ];
      }
      if (request.method == 'GET' &&
          request.url.path.endsWith('/stock_check_tasks')) {
        final batchId = request.url.queryParameters['batch_id'] ?? '';
        result =
            taskRows
                ?.where((row) => batchId == 'eq.${row['batch_id']}')
                .toList() ??
            [
              for (final origin
                  in source == 'inventory' ? ['inventory', 'store'] : ['store'])
                if (batchId == 'eq.$origin-a')
                  {
                    'id': '$origin-item',
                    'batch_id': '$origin-a',
                    'title': origin == 'inventory' ? 'Inventory A' : 'Store A',
                    'source': origin,
                    'branch_name': 'Branch A',
                    'item_code': 'A',
                    'item_name': 'Medicine',
                    'system_qty': 10,
                    'actual_qty': 8,
                    'status': 'submitted',
                    'sent_at': '${DateTime.now().year}-01-01T10:00:00Z',
                    'expires_at': '2030-01-01T10:00:00Z',
                  },
            ];
      }
      if (request.method == 'POST' &&
          request.url.path.endsWith('/stock_check_tasks')) {
        result = [
          for (final row in jsonDecode(request.body) as List)
            {...row as Map<String, dynamic>, 'id': 'created-item'},
        ];
      }
      return http.Response(
        jsonEncode(result),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  if (signedIn) {
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'test-token',
        'token_type': 'bearer',
        'user': {'id': 'maya-id'},
      }),
    );
  }
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await client.dispose();
  });
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: size,
      builder: (_, _) => MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        home: StockCheckPage(
          client: client,
          runDate: '${DateTime.now().year}-10-09',
          source: source,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return requests;
}

Future<void> composeAndSend(WidgetTester tester, {bool kpi = false}) async {
  await tester.tap(find.text('Create New Stock Check'));
  await tester.pumpAndSettle();
  if (kpi) {
    await tester.tap(find.text('KPI Stock Check'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.textContaining('0 of').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Branch A').last);
  await tester.tap(find.text('Apply'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Choose Items'));
  await tester.pumpAndSettle();
  final search = find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == 'Search item code or item name...',
  );
  await tester.enterText(search, 'Sample');
  await tester.pumpAndSettle();
  await tester.tap(find.text('Sample').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Apply Items'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Send Stock Check'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'KPI project loading retains the dashboard, previous results and retry',
    (tester) async {
      final firstLoad = Completer<void>();
      final secondLoad = Completer<void>();
      var secondAttempts = 0;
      await showStockCheck(
        tester,
        signedIn: true,
        campaignSummaries: [
          for (var q = 1; q <= 2; q++)
            {
              'batch_id': 'q$q',
              'title': 'KPI Q$q',
              'source': 'inventory',
              'check_kind': 'kpi',
              'kpi_year': 2026,
              'kpi_quarter': q,
              'total': 1,
              'submitted': 1,
              'branches': 1,
              'products': 1,
              'sent_at': '${DateTime.now().year}-10-10T10:00:00Z',
            },
        ],
        taskRows: [
          for (var q = 1; q <= 2; q++)
            {
              'id': 'q$q-A',
              'batch_id': 'q$q',
              'branch_name': 'Branch A',
              'item_code': 'A',
              'item_name': 'Shared medicine',
              'system_qty': 10,
              'actual_qty': q == 1 ? 10 : 12,
              'status': 'submitted',
            },
        ],
        beforeResponse: (request) async {
          if (!request.url.path.endsWith('/stock_check_tasks') ||
              request.method != 'GET') {
            return;
          }
          if (request.url.queryParameters['batch_id'] == 'eq.q1') {
            await firstLoad.future;
          }
          if (request.url.queryParameters['batch_id'] == 'eq.q2') {
            secondAttempts++;
            await secondLoad.future;
            if (secondAttempts == 1) throw StateError('Temporary test failure');
          }
        },
      );
      await tester.tap(find.text('KPI Stock Checks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accuracy Analysis'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0 Projects'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'KPI Q1'));
      await tester.pump();
      await tester.tap(find.text('Apply 1 project(s)'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Stock Check KPI Analysis'), findsOneWidget);
      expect(find.text('Updating KPI analysis'), findsOneWidget);
      expect(find.text('Final KPI accuracy'), findsOneWidget);
      expect(find.text('Loading selected projects...'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == 'Loading branch performance',
        ),
        findsWidgets,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Export KPI Report'),
            )
            .onPressed,
        isNull,
      );
      firstLoad.complete();
      await tester.pumpAndSettle();
      expect(find.text('100.0%'), findsNWidgets(2));
      await tester.tap(find.text('1 Projects'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'KPI Q2'));
      await tester.pump();
      await tester.tap(find.text('Apply 2 project(s)'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('100.0%'), findsNWidgets(2));
      expect(
        find.text('Showing previous results until the update completes.'),
        findsOneWidget,
      );
      expect(find.textContaining('1 of 2 projects loaded'), findsOneWidget);
      final search = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Search branch',
      );
      await tester.enterText(search, 'Branch A');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Product details'), findsOneWidget);
      secondLoad.complete();
      await tester.pumpAndSettle();
      expect(find.text('Could not update KPI analysis'), findsOneWidget);
      expect(find.text('100.0%'), findsNWidgets(2));
      expect(find.text('Stock Check KPI Analysis'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(secondAttempts, 2);
      expect(find.text('0.0%'), findsNWidgets(2));
      expect(find.text('100.0%'), findsNothing);
      expect(find.text('Updating KPI analysis'), findsNothing);
      expect(find.text('Could not update KPI analysis'), findsNothing);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: search, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        'Branch A',
      );
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'KPI Summary shows shared items for multiple projects without review',
    () async {
      for (var quarters = 1; quarters <= 4; quarters++) {
        final report = exportFixture(quarters: quarters);
        final expectedHeaders = [
          'Branch',
          'Unique Products',
          'Scored',
          '100%',
          '0%',
          if (quarters > 1)
            'Shared Items (${List.generate(quarters, (i) => 'Q${i + 1}').join(' - ')})',
          'Single Project',
          'Accuracy %',
        ];
        final expectedTotals = [
          'ALL BRANCHES',
          '${report.total}',
          '${report.scored}',
          '${report.correct}',
          '${report.failed}',
          if (quarters > 1) '${report.shared}',
          '${report.standalone}',
        ];
        final bytes = await StockCheckExcelExporter.buildKpiAnalysisBytes(
          report: report,
        );
        final archive = ZipDecoder().decodeBytes(bytes);
        final summary = exportXml(archive, 'xl/worksheets/sheet1.xml');
        final strings = exportXml(
          archive,
          'xl/sharedStrings.xml',
        ).findAllElements('si').map((e) => e.innerText).toList();
        final columns = List.generate(
          expectedHeaders.length,
          (i) => String.fromCharCode(65 + i),
        );
        expect([
          for (final col in columns) exportCell(summary, '${col}1', strings),
        ], expectedHeaders);
        expect(
          summary.findAllElements('row').first.findElements('c').length,
          expectedHeaders.length,
        );
        expect([
          for (final col in columns.take(columns.length - 1))
            exportCell(summary, '${col}2', strings),
        ], expectedTotals);
        expect(
          double.parse(exportCell(summary, '${columns.last}2', strings)),
          closeTo(report.accuracy!, .001),
        );
        final workbook = StockCheckExcelExporter.buildKpiAnalysisWorkbook(
          report,
        );
        try {
          final sheet = workbook.worksheets[0];
          expect([
            for (var col = 1; col <= expectedHeaders.length; col++)
              sheet.getRangeByIndex(1, col).getText(),
          ], expectedHeaders);
          expect(
            sheet.getRangeByIndex(2, expectedHeaders.length).getNumber(),
            report.accuracy,
          );
          expect(
            sheet.getRangeByIndex(3, expectedHeaders.length).getNumber(),
            report.branches.values.single.accuracy,
          );
        } finally {
          workbook.dispose();
        }
      }
    },
  );
  test(
    'branch 71 prefix appears in both KPI export paths without changing identity',
    () async {
      final originalGroups = StoreBranchIdentityRegistry.groups.value;
      addTearDown(
        () => StoreBranchIdentityRegistry.groups.value = originalGroups,
      );
      StoreBranchIdentityRegistry.groups.value = const {
        'BRANCH A': '71',
        'BRANCH B': 'APG',
      };
      final fixture = exportFixture();
      final report = StockCheckKpiReport(
        projects: fixture.projects,
        rows: [
          for (final item in fixture.items)
            for (final project in fixture.projects) ?item.rowFor(project.id),
          StockCheckTask.fromMap({
            'id': 'other-branch',
            'batch_id': 'q1',
            'branch_name': 'Branch B',
            'item_code': 'P00000',
            'item_name': 'Other branch medicine',
            'system_qty': 10,
            'actual_qty': 10,
            'status': 'submitted',
          }),
        ],
      );
      final total = report.total;
      final accuracy = report.accuracy;
      final bytes = await StockCheckExcelExporter.buildKpiAnalysisBytes(
        report: report,
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      final strings = exportXml(
        archive,
        'xl/sharedStrings.xml',
      ).findAllElements('si').map((e) => e.innerText).toList();
      final summary = exportXml(archive, 'xl/worksheets/sheet1.xml');
      final details = exportXml(archive, 'xl/worksheets/sheet2.xml');
      expect(exportCell(summary, 'A2', strings), 'ALL BRANCHES');
      expect(exportCell(summary, 'A3', strings), '71 Branch A');
      expect(exportCell(summary, 'A4', strings), 'Branch B');
      expect(exportCell(details, 'A2', strings), '71 Branch A');
      expect(exportCell(details, 'A6', strings), 'Branch B');
      final workbook = StockCheckExcelExporter.buildKpiAnalysisWorkbook(report);
      try {
        expect(
          workbook.worksheets[0].getRangeByIndex(3, 1).getText(),
          '71 Branch A',
        );
        expect(
          workbook.worksheets[0].getRangeByIndex(4, 1).getText(),
          'Branch B',
        );
        expect(
          workbook.worksheets[1].getRangeByIndex(2, 1).getText(),
          '71 Branch A',
        );
        expect(
          workbook.worksheets[1].getRangeByIndex(6, 1).getText(),
          'Branch B',
        );
      } finally {
        workbook.dispose();
      }
      expect(report.branches.keys, ['Branch A', 'Branch B']);
      expect(report.items.first.rowFor('q1')!.branchName, 'Branch A');
      expect(report.total, total);
      expect(report.accuracy, accuracy);
    },
  );
  testWidgets(
    'branch 71 labels update after metadata loads and support prefixed search',
    (tester) async {
      final originalGroups = StoreBranchIdentityRegistry.groups.value;
      addTearDown(
        () => StoreBranchIdentityRegistry.groups.value = originalGroups,
      );
      StoreBranchIdentityRegistry.groups.value = const {};
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = exportFixture();
      final rows = [
        for (final item in fixture.items)
          for (final project in fixture.projects) ?item.rowFor(project.id),
        StockCheckTask.fromMap({
          'id': 'other-branch',
          'batch_id': 'q1',
          'branch_name': 'Branch B',
          'item_code': 'P00000',
          'item_name': 'Other branch medicine',
          'system_qty': 10,
          'actual_qty': 10,
          'status': 'submitted',
        }),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StockCheckKpiAnalysisPanel(
              projects: fixture.projects,
              rows: rows,
              onSelectProjects: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Branch A'), findsOneWidget);
      expect(find.text('Branch B'), findsOneWidget);
      await tester.tap(find.text('Product details').first);
      await tester.pumpAndSettle();
      StoreBranchIdentityRegistry.groups.value = const {
        'BRANCH A': '71',
        'BRANCH B': 'APG',
      };
      await tester.pumpAndSettle();
      expect(find.textContaining('71 Branch A —'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('71 Branch A'), findsOneWidget);
      expect(find.text('Branch B'), findsOneWidget);
      expect(find.text('Branch A'), findsNothing);
      final search = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Search branch',
      );
      await tester.enterText(search, '71 Branch A');
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == '71 Branch A'),
        findsOneWidget,
      );
      expect(find.text('Branch B'), findsNothing);
      expect(rows.first.branchName, 'Branch A');
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'worker Excel preserves quarter values, exclusions, final scores and colors',
    () async {
      final bytes = await StockCheckExcelExporter.buildKpiAnalysisBytes(
        report: exportFixture(),
      );
      final archive = ZipDecoder().decodeBytes(bytes);
      final summary = exportXml(archive, 'xl/worksheets/sheet1.xml');
      final detail = exportXml(archive, 'xl/worksheets/sheet2.xml');
      final strings = exportXml(
        archive,
        'xl/sharedStrings.xml',
      ).findAllElements('si').map((e) => e.innerText).toList();
      expect(exportCell(summary, 'C2', strings), '3');
      expect(exportCell(summary, 'D2', strings), '2');
      expect(
        double.parse(exportCell(summary, 'H2', strings)),
        closeTo(200 / 3, .001),
      );
      expect(exportCell(detail, 'R1', strings), 'Q4 2026 | Difference');
      expect(
        exportCell(detail, 'S1', strings),
        'Difference | Q1 2026 vs Q2 2026 vs Q3 2026 vs Q4 2026',
      );
      expect(exportCell(detail, 'L2', strings), '2');
      expect(exportCell(detail, 'S2', strings), '2');
      expect(exportCell(detail, 'T2', strings), '0');
      expect(exportCell(detail, 'T3', strings), '100');
      expect(exportCell(detail, 'T4', strings), '');
      expect(
        exportCell(detail, 'M3', strings),
        '',
      ); // Absent quarter stays blank.
      expect(
        strings.where(
          (s) => s.contains('Status') || s.contains('Change in Difference'),
        ),
        isEmpty,
      );
      final styles = exportXml(archive, 'xl/styles.xml');
      final xfs = styles.rootElement
          .getElement('cellXfs')!
          .findElements('xf')
          .toList();
      final fonts = styles.rootElement
          .getElement('fonts')!
          .findElements('font')
          .toList();
      final fills = styles.rootElement
          .getElement('fills')!
          .findElements('fill')
          .toList();
      XmlElement style(String address) =>
          xfs[int.parse(
            detail
                .findAllElements('c')
                .firstWhere((c) => c.getAttribute('r') == address)
                .getAttribute('s')!,
          )];
      String? color(String address) =>
          fonts[int.parse(style(address).getAttribute('fontId')!)]
              .getElement('color')
              ?.getAttribute('rgb');
      String? fill(String address) =>
          fills[int.parse(style(address).getAttribute('fillId')!)]
              .getElement('patternFill')
              ?.getElement('fgColor')
              ?.getAttribute('rgb');
      for (final (columns, header, even, odd) in [
        (['G', 'H', 'I'], 'FF2563EB', 'FFE7EFFC', 'FFF2F7FF'),
        (['J', 'K', 'L'], 'FF0F766E', 'FFE0F2EC', 'FFEFFAF7'),
        (['M', 'N', 'O'], 'FF7C3AED', 'FFF0E6FC', 'FFF8F3FF'),
        (['P', 'Q', 'R'], 'FFB45309', 'FFFFF0DB', 'FFFFF8EF'),
      ]) {
        for (final column in columns) {
          expect(fill('${column}1'), header);
          expect(fill('${column}2'), even);
          expect(fill('${column}3'), odd);
        }
      }
      expect(color('S2'), 'FFB91C1C');
      expect(color('T2'), 'FFB91C1C');
      expect(color('T3'), 'FF15803D');
      expect(
        fills[int.parse(style('T3').getAttribute('fillId')!)]
            .getElement('patternFill')!
            .getElement('fgColor')!
            .getAttribute('rgb'),
        'FFDCFCE7',
      );
      expect(
        styles
            .findAllElements('numFmt')
            .any((n) => n.getAttribute('formatCode') == '0"%"'),
        isTrue,
      );
    },
  );

  test(
    'each export reloads worker assets and keeps colors for selected quarters',
    () async {
      final requestsBefore = _workerAssetRequests;
      for (var attempt = 0; attempt < 2; attempt++) {
        final original = exportFixture();
        final report = StockCheckKpiReport(
          projects: original.projects
              .where((p) => p.quarter == 2 || p.quarter == 4)
              .toList(),
          rows: [
            for (final item in original.items)
              for (final id in ['q2', 'q4'])
                if (item.rowFor(id) != null) item.rowFor(id)!,
          ],
        );
        final bytes = await StockCheckExcelExporter.buildKpiAnalysisBytes(
          report: report,
        );
        final archive = ZipDecoder().decodeBytes(bytes);
        final detail = exportXml(archive, 'xl/worksheets/sheet2.xml');
        final styles = exportXml(archive, 'xl/styles.xml');
        final xfs = styles.rootElement
            .getElement('cellXfs')!
            .findElements('xf')
            .toList();
        final fills = styles.rootElement
            .getElement('fills')!
            .findElements('fill')
            .toList();
        String? fill(String address) {
          final cell = detail
              .findAllElements('c')
              .firstWhere((c) => c.getAttribute('r') == address);
          final xf = xfs[int.parse(cell.getAttribute('s')!)];
          return fills[int.parse(xf.getAttribute('fillId')!)]
              .getElement('patternFill')!
              .getElement('fgColor')!
              .getAttribute('rgb');
        }

        expect(fill('G1'), 'FF0F766E'); // Q2 remains teal when Q1 is absent.
        expect(fill('J1'), 'FFB45309'); // Q4 remains amber when Q3 is absent.
      }
      expect(_workerAssetRequests - requestsBefore, 2);
    },
  );

  test(
    'large four-quarter export keeps the browser event loop running',
    () async {
      final report = exportFixture(products: 15000);
      var ticks = 0, ticksAtPackaging = 0;
      final timer = Timer.periodic(
        const Duration(milliseconds: 16),
        (_) => ticks++,
      );
      addTearDown(timer.cancel);
      final watch = Stopwatch()..start();
      final stages = <KpiExportStage>{};
      final bytes = await StockCheckExcelExporter.buildKpiAnalysisBytes(
        report: report,
        onProgress: (p) {
          stages.add(p.stage);
          if (p.stage == KpiExportStage.packaging) ticksAtPackaging = ticks;
        },
      );
      expect(
        stages,
        containsAll([KpiExportStage.writing, KpiExportStage.packaging]),
      );
      expect(ticksAtPackaging, greaterThan(0));
      expect(
        ticks - ticksAtPackaging,
        greaterThan(5),
        reason: 'The UI thread must run while Excel is compressed.',
      );
      expect(bytes.length, greaterThan(100000));
      // Useful real browser evidence without asserting fragile machine timings.
      debugPrint(
        'KPI worker: 15,000 products, 4 quarters, ${watch.elapsedMilliseconds} ms, $ticks UI heartbeat ticks.',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'worker cancellation and errors allow a subsequent successful export',
    () async {
      final job = KpiExportJob();
      await expectLater(
        StockCheckExcelExporter.buildKpiAnalysisBytes(
          report: exportFixture(products: 1000),
          job: job,
          onProgress: (p) {
            if (p.stage == KpiExportStage.packaging) job.cancel();
          },
        ),
        throwsA(isA<KpiExportCancelled>()),
      );
      await expectLater(
        StockCheckKpiExportWorker.build(
          summaryHeaders: ['Branch'],
          detailHeaders: ['Product'],
          summaryWidths: [20],
          detailWidths: [20],
          summaryRows: [],
          detailRows: [],
          totalRows: 1,
          job: KpiExportJob(),
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        (await StockCheckExcelExporter.buildKpiAnalysisBytes(
          report: exportFixture(),
        )).length,
        greaterThan(1000),
      );
    },
  );

  testWidgets(
    'export feedback paints immediately, browsing works and errors can be retried',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 1200);
      tester.view.devicePixelRatio = 1;
      await tester.binding.setSurfaceSize(const Size(1500, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final report = exportFixture();
      var pending = Completer<void>();
      KpiExportJob? currentJob;
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StockCheckKpiAnalysisPanel(
              projects: report.projects,
              rows: [
                for (final item in report.items)
                  for (final project in report.projects)
                    if (item.rowFor(project.id) != null)
                      item.rowFor(project.id)!,
              ],
              onSelectProjects: () {},
              exportReport: ({required report, job, onProgress}) {
                attempts++;
                currentJob = job;
                onProgress?.call(
                  const KpiExportProgress(
                    KpiExportStage.packaging,
                    total: 4,
                    processed: 4,
                  ),
                );
                return pending.future;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export KPI Report'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('kpi-export-status')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is CircularProgressIndicator && w.value == null,
        ),
        findsNWidgets(2),
      );
      expect(find.text('Compressing and finishing your file'), findsOneWidget);
      final search = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Search branch',
      );
      await tester.enterText(search, 'not a branch');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Product details'), findsNothing);
      await tester.enterText(search, 'Branch A');
      await tester.pump(const Duration(milliseconds: 900));
      await tester.tap(find.text('Product details'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pump(const Duration(milliseconds: 300));
      pending.completeError(StateError('Test failure'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('kpi-export-status')), findsNothing);
      expect(
        find.textContaining('Could not export KPI report'),
        findsOneWidget,
      );
      pending = Completer<void>();
      await tester.tap(find.text('Export KPI Report'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      expect(currentJob!.cancelled, isTrue);
      pending.completeError(const KpiExportCancelled());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Export KPI Report'), findsOneWidget);
      expect(attempts, 2);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'KPI Excel includes all quarters, union products and the same final score',
    () {
      final report = StockCheckKpiReport(
        projects: [
          for (var q = 1; q <= 4; q++)
            StockCheckCampaign({
              'batch_id': 'q$q',
              'title': 'KPI Q$q',
              'kpi_year': 2026,
              'kpi_quarter': q,
            }),
        ],
        rows: [
          for (var q = 1; q <= 4; q++)
            StockCheckTask.fromMap({
              'id': 'q$q-A',
              'batch_id': 'q$q',
              'branch_name': 'Branch A',
              'item_code': 'A',
              'item_name': 'Shared medicine',
              'system_qty': 10,
              'actual_qty': q == 2 ? 12 : 10,
              'status': 'submitted',
            }),
          StockCheckTask.fromMap({
            'id': 'q1-B',
            'batch_id': 'q1',
            'branch_name': 'Branch A',
            'item_code': 'B',
            'item_name': 'Single medicine',
            'system_qty': 10,
            'actual_qty': 10,
            'status': 'submitted',
          }),
        ],
      );
      final workbook = StockCheckExcelExporter.buildKpiAnalysisWorkbook(report);
      addTearDown(workbook.dispose);
      final summary = workbook.worksheets[0];
      final details = workbook.worksheets[1];
      expect(summary.getRangeByIndex(2, 3).getNumber(), 2);
      expect(summary.getRangeByIndex(2, 4).getNumber(), 1);
      expect(summary.getRangeByIndex(2, 8).getNumber(), 50);
      expect(details.getRangeByIndex(2, 20).getNumber(), 0);
      expect(details.getRangeByIndex(3, 20).getNumber(), 100);
      expect(details.getRangeByIndex(2, 12).getNumber(), 2);
      expect(details.getRangeByIndex(2, 19).getNumber(), 2);
      expect(details.getRangeByIndex(1, 18).getText(), 'Q4 2026 | Difference');
      expect(
        details.getRangeByIndex(1, 19).getText(),
        'Difference | Q1 2026 vs Q2 2026 vs Q3 2026 vs Q4 2026',
      );
      expect(details.getRangeByIndex(1, 20).getText(), 'Accuracy %');
      expect(
        details.getRangeByIndex(2, 19).cellStyle.fontColor.toUpperCase(),
        endsWith('B91C1C'),
      );
      expect(
        details.getRangeByIndex(2, 20).cellStyle.fontColor.toUpperCase(),
        endsWith('B91C1C'),
      );
      expect(
        details.getRangeByIndex(3, 20).cellStyle.fontColor.toUpperCase(),
        endsWith('15803D'),
      );
      expect(details.getRangeByIndex(3, 20).numberFormat, '0"%"');
      for (var col = 1; col <= 20; col++) {
        expect(
          details.getRangeByIndex(1, col).getText(),
          isNot(contains('Status')),
        );
        expect(
          details.getRangeByIndex(1, col).getText(),
          isNot(contains('Change in Difference')),
        );
      }
      expect(workbook.saveAsStream().length, greaterThan(1000));
    },
  );
  testWidgets(
    'KPI analysis compares all four quarters and includes unique products',
    (tester) async {
      await showStockCheck(
        tester,
        signedIn: true,
        campaignSummaries: [
          for (var q = 1; q <= 4; q++)
            {
              'batch_id': 'q$q',
              'title': 'KPI Q$q',
              'source': 'inventory',
              'check_kind': 'kpi',
              'kpi_year': 2026,
              'kpi_quarter': q,
              'total': q == 1 ? 3 : 1,
              'submitted': q == 1 ? 3 : 1,
              'branches': 1,
              'products': q == 1 ? 3 : 1,
              'sent_at': '${DateTime.now().year}-10-10T10:00:00Z',
            },
        ],
        taskRows: [
          for (var q = 1; q <= 4; q++)
            {
              'id': 'q$q-A',
              'batch_id': 'q$q',
              'branch_name': 'Branch A',
              'item_code': 'A',
              'item_name': 'Shared medicine',
              'system_qty': 10,
              'actual_qty': q == 2 ? 12 : 10,
              'status': 'submitted',
            },
          for (final code in ['B', 'C'])
            {
              'id': 'q1-$code',
              'batch_id': 'q1',
              'branch_name': 'Branch A',
              'item_code': code,
              'item_name': 'Single medicine $code',
              'system_qty': 10,
              'actual_qty': 10,
              'status': 'submitted',
            },
        ],
      );
      await tester.tap(find.text('KPI Stock Checks'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accuracy Analysis'));
      await tester.pumpAndSettle();
      expect(find.text('Stock Check KPI Analysis'), findsOneWidget);
      await tester.tap(find.text('0 Projects'));
      await tester.pumpAndSettle();
      for (var q = 1; q <= 4; q++) {
        await tester.tap(find.widgetWithText(CheckboxListTile, 'KPI Q$q'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Apply 4 project(s)'));
      await tester.pumpAndSettle();
      expect(find.text('4 Projects'), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('66.7%'), findsNWidgets(2));
      await tester.tap(find.text('Product details'));
      await tester.pumpAndSettle();
      for (var q = 1; q <= 4; q++) {
        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('Q$q 2026'),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('Shared medicine'), findsOneWidget);
      expect(find.text('Single medicine B'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('100%'), findsNWidgets(2));
      expect(find.text('Not included'), findsNWidgets(6));
      expect(find.text('Difference: 2'), findsOneWidget);
      expect(find.text('Difference between quarters'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(Dialog), matching: find.text('2')),
        findsOneWidget,
      );
      expect(find.textContaining('Δ Difference:'), findsNothing);
      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.labelText == 'Search item code or name',
        ),
        'Single medicine B',
      );
      await tester.pumpAndSettle();
      expect(find.text('Shared medicine'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == 'Single medicine B',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('66.7% KPI accuracy'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  setUpAll(() async {
    // The test engine ignores platform messages; serve the real worker assets
    // through Flutter's local test server instead of leaving rootBundle pending.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (data) async {
          final key = utf8.decode(data!.buffer.asUint8List());
          if (!key.startsWith('assets/workers/')) return null;
          if (key.endsWith('stock_check_kpi_export_worker.js')) {
            _workerAssetRequests++;
          }
          final response = await http.get(
            Uri.base.resolve('/workers/${key.split('/').last}'),
          );
          if (response.statusCode != 200) return null;
          return ByteData.sublistView(response.bodyBytes);
        });
    final font = await http.get(Uri.base.resolve('/canvaskit/roboto.ttf'));
    expect(font.statusCode, 200);
    ui_web.TestEnvironment.setUp(
      const ui_web.TestEnvironment(
        ignorePlatformMessages: true,
        forceTestFonts: false,
        disableFontFallbacks: true,
        keepSemanticsDisabledOnUpdate: true,
        defaultToTestUrlStrategy: true,
      ),
    );
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(font.bodyBytes)));
    await loader.load();
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });
  testWidgets(
    'Git layout exposes analysis, Store and original campaign controls',
    (tester) async {
      final requests = await showStockCheck(tester);
      expect(tester.takeException(), isNull);
      expect(
        requests.where((r) => r.url.path.endsWith('/stock_check_campaigns')),
        hasLength(1),
      );
      expect(
        requests.where((r) => r.url.path.endsWith('/stock_check_tasks')),
        isEmpty,
      );
      expect(find.text('Accuracy Analysis'), findsOneWidget);
      expect(find.text('Create New Stock Check'), findsOneWidget);
      expect(find.textContaining('Created by'), findsNothing);
      expect(
        tester.getRect(find.text('Export')).right,
        lessThan(
          tester
              .getRect(
                find.widgetWithText(FilledButton, 'Create New Stock Check'),
              )
              .left,
        ),
      );
      expect(find.text('Choose Items'), findsNothing);
      await tester.tap(find.text('Create New Stock Check'));
      await tester.pumpAndSettle();
      final titleField = tester.widget<TextField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText == 'Stock check title',
        ),
      );
      expect(
        titleField.controller?.text,
        'Stock Check 09-10-${DateTime.now().year}',
      );
      final panel = tester.getRect(
        find.byKey(const ValueKey('create-stock-check-side-panel')),
      );
      expect(panel.left, greaterThan(900));
      expect(panel.right, closeTo(2000, 1));
      expect(panel.height, greaterThan(1000));
      final destinations = tester.getRect(
        find.byKey(const ValueKey('stock-check-destinations')),
      );
      final items = tester.getRect(
        find.byKey(const ValueKey('stock-check-items')),
      );
      expect(destinations.top, closeTo(items.top, 1));
      expect(destinations.right, lessThan(items.left));
      await tester.tap(find.text('Completion window'));
      await tester.pumpAndSettle();
      expect(find.text('QUICK SELECT'), findsOneWidget);
      expect(find.text('From'), findsOneWidget);
      expect(find.text('To'), findsOneWidget);
      expect(find.text('2 Days'), findsOneWidget);
      expect(find.text('Last Month'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Choose Items'), findsOneWidget);
      expect(find.text('Check each item sticker'), findsOneWidget);
      expect(find.text('Add optional choices'), findsOneWidget);
      final importButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Import Items'),
      );
      expect(
        importButton.style?.backgroundColor?.resolve({}),
        AppColors.primaryColor,
      );
      expect(importButton.style?.foregroundColor?.resolve({}), Colors.white);
      expect(
        tester.getRect(find.widgetWithText(FilledButton, 'Import Items')).top,
        lessThan(destinations.top),
      );
      await tester.tap(find.byTooltip('Close create stock check'));
      await tester.pumpAndSettle();
      expect(find.text('Choose Items'), findsNothing);
      expect(find.byTooltip('Edit deadline'), findsOneWidget);
      expect(find.byTooltip('Delete stock check'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit deadline'));
      await tester.pumpAndSettle();
      expect(find.text('QUICK SELECT'), findsOneWidget);
      expect(find.text('Last Month'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete stock check'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Stock Check'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(requests.where((r) => r.method == 'DELETE'), isEmpty);
      await tester.tap(find.text('Store'));
      await tester.pumpAndSettle();
      expect(find.text('Store A'), findsWidgets);
      expect(find.byTooltip('Edit deadline'), findsNothing);
      await tester.tap(find.text('Inventory'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Inventory A'));
      await tester.pumpAndSettle();
      final detailRequests = requests
          .where(
            (r) =>
                r.method == 'GET' && r.url.path.endsWith('/stock_check_tasks'),
          )
          .toList();
      expect(detailRequests, hasLength(1));
      expect(
        detailRequests.single.url.queryParameters['batch_id'],
        'eq.inventory-a',
      );
      await tester.tap(find.text('Inventory A').first);
      await tester.pumpAndSettle();
      expect(
        requests.where(
          (r) => r.method == 'GET' && r.url.path.endsWith('/stock_check_tasks'),
        ),
        hasLength(1),
      );
      await tester.tap(find.text('Accuracy Analysis'));
      await tester.pumpAndSettle();
      expect(find.text('Stock Check Accuracy Analysis'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'sent cards follow creation date even when older work is pending',
    (tester) async {
      final now = DateTime.now().toUtc();
      await showStockCheck(
        tester,
        campaignSummaries: [
          {
            'batch_id': 'older',
            'title': 'Z older pending',
            'source': 'inventory',
            'total': 2,
            'submitted': 0,
            'branches': 1,
            'products': 1,
            'sent_at': now.subtract(const Duration(days: 1)).toIso8601String(),
          },
          {
            'batch_id': 'newer',
            'title': 'A newer completed',
            'source': 'inventory',
            'total': 2,
            'submitted': 2,
            'branches': 1,
            'products': 1,
            'sent_at': now.toIso8601String(),
          },
        ],
      );
      expect(
        tester.getTopLeft(find.text('A newer completed')).dy,
        lessThan(tester.getTopLeft(find.text('Z older pending')).dy),
      );
    },
  );
  for (final source in ['inventory', 'store']) {
    testWidgets(
      '$source sends with automatic app_users sender in restored layout',
      (tester) async {
        final requests = await showStockCheck(
          tester,
          source: source,
          signedIn: true,
        );
        await composeAndSend(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Created by Maya'), findsOneWidget);
        expect(
          requests
              .where(
                (r) =>
                    r.method == 'GET' &&
                    r.url.path.endsWith('/stock_check_tasks'),
              )
              .length,
          0,
        );
        final insert = requests.singleWhere(
          (r) =>
              r.method == 'POST' && r.url.path.endsWith('/stock_check_tasks'),
        );
        final row = (jsonDecode(insert.body) as List).single as Map;
        expect(row['source'], source);
        expect(row['sender_user_id'], 'maya-id');
        expect(row['sender_name'], 'Maya');
        expect(row['branch_name'], 'Branch A');
        expect(row['item_code'], 'TEST-01');
        expect(row.containsKey('team_name'), isFalse);
        expect(row.containsKey('owner_name'), isFalse);
      },
    );
  }
  testWidgets('Inventory creates a quarterly KPI in its own list', (
    tester,
  ) async {
    final requests = await showStockCheck(tester, signedIn: true);
    await composeAndSend(tester, kpi: true);
    expect(tester.takeException(), isNull);
    final insert = requests.singleWhere(
      (r) => r.method == 'POST' && r.url.path.endsWith('/stock_check_tasks'),
    );
    final row = (jsonDecode(insert.body) as List).single as Map;
    expect(row['check_kind'], 'kpi');
    expect(row['kpi_year'], DateTime.now().year);
    expect(row['kpi_quarter'], (DateTime.now().month - 1) ~/ 3 + 1);
    expect(find.textContaining('KPI  ·'), findsOneWidget);
    await tester.tap(find.text('Regular Stock Checks'));
    await tester.pumpAndSettle();
    expect(find.textContaining('KPI  ·'), findsNothing);
  });
  testWidgets('KPI creation is hidden outside the Inventory role', (
    tester,
  ) async {
    await showStockCheck(tester, role: 'branch', signedIn: true);
    await tester.tap(find.text('Create New Stock Check'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stock-check-kpi-option')), findsNothing);
    expect(find.text('KPI Stock Checks'), findsNothing);
  });
  testWidgets('branch role without user_name skips sender identity fields', (
    tester,
  ) async {
    final requests = await showStockCheck(
      tester,
      role: 'branch',
      userName: null,
      signedIn: true,
    );
    await composeAndSend(tester);
    expect(tester.takeException(), isNull);
    final insert = requests.singleWhere(
      (r) => r.method == 'POST' && r.url.path.endsWith('/stock_check_tasks'),
    );
    final row = (jsonDecode(insert.body) as List).single as Map;
    expect(row.containsKey('sender_user_id'), isFalse);
    expect(row.containsKey('sender_name'), isFalse);
  });
  testWidgets(
    'non-branch missing user_name cannot send unattributed campaign',
    (tester) async {
      final requests = await showStockCheck(
        tester,
        userName: null,
        signedIn: true,
      );
      await composeAndSend(tester);
      expect(tester.takeException(), isNull);
      expect(
        requests.where(
          (r) =>
              r.method == 'POST' && r.url.path.endsWith('/stock_check_tasks'),
        ),
        isEmpty,
      );
      expect(find.textContaining('user_name before sending'), findsOneWidget);
    },
  );
}
