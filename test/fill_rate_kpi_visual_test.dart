import 'package:daily_order/data/datasources/remote/fill_rate_kpi_remote_ds.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/fill_rate_kpi_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Fill Rate management layout', (tester) async {
    tester.view.physicalSize = const Size(1600, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, fontFamily: 'Roboto'),
        home: Scaffold(body: FillRateKpiPage(previewReport: _report())),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(FillRateKpiPage),
      matchesGoldenFile('goldens/fill_rate_kpi_redesign.png'),
    );

    await tester.tap(find.text('Management Report'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(FillRateKpiPage),
      matchesGoldenFile('goldens/fill_rate_kpi_management.png'),
    );

    await tester.ensureVisible(
      find.text('Calculate Available + Empty Fill Rate'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calculate Available + Empty Fill Rate'));
    await tester.pumpAndSettle();
    expect(
      find.text('Combined Fill Rate — Available & Empty Statuses'),
      findsOneWidget,
    );
    expect(find.text('Combined Unit Fill Rate'), findsOneWidget);
    expect(find.text('Combined Line Fill Rate'), findsOneWidget);
    expect(
      find.text('INCLUDES: AVAILABLE + AVAILABLE N.E + EMPTY / NOT ASSIGNED'),
      findsNWidgets(2),
    );
    expect(
      find.textContaining('supplier-status products excluded'),
      findsWidgets,
    );
    expect(find.text('24.98%'), findsWidgets);
    expect(find.text('24.16%'), findsWidgets);
    expect(find.textContaining('13101 products are included'), findsOneWidget);
    expect(find.textContaining('8223 products'), findsNothing);
    await expectLater(
      find.byType(FillRateKpiPage),
      matchesGoldenFile('goldens/fill_rate_kpi_status_focus.png'),
    );
  });
}

FillRateReport _report() {
  final date = DateTime(2026, 8, 10);
  final summaries = <FillRateSummary>[
    _summary(
      'ALL BRANCHES',
      15824,
      3864,
      3102,
      762,
      11960,
      55199,
      10982,
      21.53,
      19.90,
    ),
    _summary(
      'AIN-(Br 02)-Zakher 02',
      311,
      88,
      85,
      3,
      223,
      787,
      117,
      27.87,
      14.87,
    ),
    _summary(
      'AIN-(Br02)-Bateen 02',
      893,
      246,
      213,
      33,
      647,
      2652,
      610,
      25.32,
      23,
    ),
    _summary('AL AIN MAIN', 905, 230, 169, 61, 675, 2795, 601, 21.10, 21.50),
    _summary('Al Noud - Ain', 566, 141, 116, 25, 425, 1528, 239, 22.18, 15.64),
    _summary('AL WUTAH - AIN', 295, 72, 66, 6, 223, 483, 98, 23.28, 20.29),
    _summary('AlainMall', 492, 107, 93, 14, 385, 1091, 208, 19.98, 19.07),
    _summary('Arabian M.C.', 358, 170, 124, 46, 188, 2225, 1030, 39.03, 46.29),
  ];
  final items = List<FillRateItem>.generate(14, (index) {
    final partial = index % 4 == 0;
    final full = index % 3 == 0 && !partial;
    final required = 1 + index % 5;
    final transferred = full
        ? required
        : partial
        ? mathMax(1, required - 1)
        : 0;
    return FillRateItem(
      totalCount: 15824,
      date: date,
      branchName: index.isEven ? 'AL AIN MAIN' : 'Arabian M.C.',
      itemCode: '16-01-${(2500 + index).toString().padLeft(5, '0')}',
      itemName: const [
        'PANADOL COLD & FLU ALL IN ONE TAB 24 S',
        'NOVALAC 1 MILK 400 G',
        'AVENE THERMAL WATER 50 ML',
        'NEXCARE MICROPORE TAPE 1.25 CM X 5 M',
      ][index % 4],
      originalQty: index == 2 ? required + 2 : required,
      requiredQty: required,
      wasEdited: index == 2,
      transferredQty: transferred,
      suppliedQty: transferred,
      fillRate: required == 0 ? 0 : transferred / required * 100,
      fulfillmentStatus: full
          ? 'Fully Supplied'
          : partial
          ? 'Partially Supplied'
          : 'Not Supplied',
      purchaseStatus: const [
        'AVAILABLE',
        'No Purchase Status',
        'ALLOCATE',
        'Out Of Stock - No Alternative',
      ][index % 4],
    );
  });
  return FillRateReport(
    summaries: summaries,
    daily: [
      FillRateDaily(
        date: date,
        totalItems: 15824,
        suppliedItems: 3864,
        fullySupplied: 3102,
        partiallySupplied: 762,
        notSupplied: 11960,
        lineFillRate: 21.53,
        unitFillRate: 19.90,
      ),
    ],
    statuses: const [
      FillRateStatus(
        name: 'No Purchase Status',
        totalItems: 8223,
        suppliedItems: 2030,
        share: 51.97,
        lineFillRate: 22.65,
        unitFillRate: 26.87,
        requiredQty: 20000,
        suppliedQty: 5374,
      ),
      FillRateStatus(
        name: 'AVAILABLE',
        totalItems: 4878,
        suppliedItems: 1543,
        share: 30.83,
        lineFillRate: 26.70,
        unitFillRate: 21.20,
        requiredQty: 10000,
        suppliedQty: 2120,
      ),
      FillRateStatus(
        name: 'Out Of Stock - No Alternative',
        totalItems: 1167,
        suppliedItems: 97,
        share: 7.37,
        lineFillRate: 6.98,
        unitFillRate: 7.88,
      ),
    ],
    items: items,
  );
}

FillRateSummary _summary(
  String branch,
  int total,
  int supplied,
  int full,
  int partial,
  int missing,
  num requiredQty,
  num suppliedQty,
  num line,
  num unit,
) => FillRateSummary(
  branchName: branch,
  totalItems: total,
  suppliedItems: supplied,
  fullySupplied: full,
  partiallySupplied: partial,
  notSupplied: missing,
  requiredQty: requiredQty,
  suppliedQty: suppliedQty,
  lineFillRate: line,
  unitFillRate: unit,
);

int mathMax(int left, int right) => left > right ? left : right;
