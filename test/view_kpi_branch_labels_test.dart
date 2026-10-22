import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/data/datasources/remote/fill_rate_kpi_remote_ds.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/fill_rate_kpi_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

void main() {
  tearDown(() => StoreBranchIdentityRegistry.groups.value = const {});
  testWidgets(
    'KPI rows refresh late branch metadata and search displayed names',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final items = [
        for (final branch in ['Alpha', 'Beta'])
          FillRateItem.fromMap({
            'branch_name': branch,
            'item_code': branch,
            'item_name': 'Product $branch',
            'run_date': '2026-10-20',
            'required_qty': 10,
            'total_count': 2,
          }),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FillRateKpiPage(
              previewReport: FillRateReport(
                summaries: [
                  for (final branch in ['ALL BRANCHES', 'Alpha', 'Beta'])
                    FillRateSummary.empty(branch),
                ],
                daily: const [],
                statuses: const [],
                items: items,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      StoreBranchIdentityRegistry.groups.value = {'ALPHA': '71', 'BETA': 'APG'};
      await tester.pumpAndSettle();
      final productGrid = tester
          .widgetList<SfDataGrid>(find.byType(SfDataGrid))
          .singleWhere(
            (grid) => grid.columns.any((c) => c.columnName == 'code'),
          );
      expect(
        productGrid.source.rows.map(
          (row) =>
              row.getCells().firstWhere((c) => c.columnName == 'branch').value,
        ),
        ['71 Alpha', 'Beta'],
      );
      expect(find.text('71 Alpha'), findsWidgets);
      expect(find.text('Beta'), findsWidgets);
      await tester.enterText(find.byType(TextField).first, '71 Alpha');
      await tester.pumpAndSettle();
      expect(productGrid.source.rows.length, 1);
      expect(items.first.branchName, 'Alpha');
      expect(tester.takeException(), isNull);
    },
  );
}
