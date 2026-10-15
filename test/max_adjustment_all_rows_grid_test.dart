import 'package:daily_order/presentation/inventory_dashboard/widgets/max_adj_data_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

void main() {
  testWidgets('all 8627 adjustments remain reachable by scrolling one grid', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final scroll = ScrollController();
    final source = MaxAdjDataSource(
      data: [
        for (var i = 0; i < 8627; i++)
          {
            'id': i,
            'branch_name': 'City',
            'item_code': '$i',
            'item_name': 'Item $i',
            'adjustment_type': 'INCREASE',
            'update_date': '2026-10-15',
            'added_by': 'inventory',
          },
      ],
      onHistory: (_) {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SfDataGrid(
            source: source,
            verticalScrollController: scroll,
            rowHeight: 52,
            columns: [
              for (final cell in source.rows.first.getCells())
                GridColumn(
                  columnName: cell.columnName,
                  width: 110,
                  label: Text(cell.columnName),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(source.effectiveRows.length, 8627);
    expect(find.text('Item 0'), findsOneWidget);
    expect(find.text('Item 8626'), findsNothing);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Item 8626'), findsOneWidget);
    expect(find.text('Item 0'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    source.dispose();
    scroll.dispose();
  });
}
