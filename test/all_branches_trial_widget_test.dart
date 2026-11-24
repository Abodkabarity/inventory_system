import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daily_order/data/datasources/remote/all_branches_trial_remote_ds.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/all_branches_trial_page.dart';

class TrialSource implements AllBranchesTrialDataSource {
  int calls = 0;
  final rows = <Map<String, dynamic>>[
    for (var i = 0; i < 30; i++)
      {
        'code': 'p$i',
        'name': 'Product $i',
        'rank': i == 0 ? 'B' : 'A',
        'online_rank': 'C',
        'online_sales': 10.0,
        'other_sales': 20.5,
        'total_sales': 30.5,
        'actual_value': 305.0,
        'stock': 60.0,
        'stock_complete': true,
        'store_stock': 5.0,
        'retail': 10.0,
        'selling_branches': 43,
        'total_branches': 61,
        'selling_months': 6,
        'purchase_status': 'Available',
        'supplier': 'Supplier',
        'reason':
            'Sold 30.5 Qty across selling branches. It gets A because it sells a high Qty.',
      },
  ];
  @override
  Future<AllBranchesTrialSnapshot> load() async {
    calls++;
    return AllBranchesTrialSnapshot({
      'generation': 'test',
      'scope': 'all_branches_trial',
      'items': 30,
      'counts': {'A': 29, 'B': 1},
      'sales_from': '2026-05-01',
      'sales_through': '2026-10-31',
      'stock_day': '2026-11-23',
      'changed': 30,
      'branches': [
        {'name': 'Main', 'group': '71', 'type': 'Online'},
      ],
      'missing_stock_branches': [],
      'thresholds': {'minimum_A_branches': 43},
      'availability': [
        {'name':'Main','ranks':{
          'A':{'total':29,'available':15,'missing':0,'percent':1500/29},
          'B':{'total':1,'available':0,'missing':1,'percent':0},
          'C':{'total':0,'available':0,'missing':0,'percent':null},
        }},
      ],
      'transitions': [
        {'before': 'C', 'after': 'A', 'count': 29},
        {'before': 'C', 'after': 'B', 'count': 1},
      ],
    }, rows);
  }

  @override
  Future<Map<String, dynamic>> details(String generation, String code) async =>
      {
        'code': code,
        'generation': generation,
        'branches': [
          {'name': 'Main', 'stock': 60, 'online': 10, 'other': 20.5},
        ],
        'monthly': [
          {'month': 'Oct 2026', 'online': 10, 'other': 20.5},
        ],
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in {
      'Roboto': 'roboto-regular.ttf',
      'Ahem': 'roboto-regular.ttf',
      'MaterialIcons': 'materialicons-regular.otf',
    }.entries) {
      final file = File(
        'C:/flutter/bin/cache/artifacts/material_fonts/${entry.value}',
      );
      if (file.existsSync()) {
        await (FontLoader(
          entry.key,
        )..addFont(file.readAsBytes().then(ByteData.sublistView))).load();
      }
    }
  });
  testWidgets(
    'branch availability keeps whole-rank denominators when the page is filtered',
    (tester) async {
      tester.view.physicalSize=const Size(1440,1100);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home:Scaffold(body:AllBranchesTrialPage(dataSource:TrialSource()))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B · Medium sales'));await tester.pumpAndSettle();
      await tester.tap(find.text('Branch availability'));await tester.pumpAndSettle();
      expect(find.text('15 of 29 · Missing 0'),findsOneWidget);
      expect(find.text('A · 51.7%'),findsOneWidget);
      expect(find.text('C · No products'),findsOneWidget);
      expect(find.text('71 Main'),findsOneWidget);
      expect(tester.takeException(),isNull);
    },
  );

  testWidgets(
    'trial compares channels and exports all filtered rows beyond the visible page',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = TrialSource();
      List<Map<String, dynamic>>? exported;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AllBranchesTrialPage(
              dataSource: source,
              export: (rows, _) async {
                exported = rows;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Online sales\n6 months (Qty)'), findsOneWidget);
      expect(
        find.text('Cash + Insurance sales\n6 months (Qty)'),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('Cash + Insurance sales\n6 months (Qty)')),
        Offset(
          tester
              .getTopLeft(find.text('Cash + Insurance sales\n6 months (Qty)'))
              .dx,
          tester.getTopLeft(find.text('Online sales\n6 months (Qty)')).dy,
        ),
      );
      await tester.tap(find.text('Export Excel'));
      await tester.pumpAndSettle();
      expect(exported, hasLength(30));
      expect(exported!.first['Online sales (Qty)'], 10.0);
      expect(exported!.first['Cash + Insurance sales (Qty)'], 20.5);
      expect(exported!.first['All sales (Qty)'], 30.5);
      await tester.enterText(find.byType(TextField), 'Product 29');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export Excel'));
      await tester.pumpAndSettle();
      expect(exported, hasLength(1));
      expect(exported!.single['Code'], 'p29');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('trial detail uses authoritative 71 labels and white modal', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AllBranchesTrialPage(dataSource: TrialSource())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Product 0\np0'));
    await tester.pumpAndSettle();
    expect(find.text('71 Main'), findsOneWidget);
    expect(find.text('Cash + Insurance 20.5'), findsOneWidget);
    expect(
      tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
      Colors.white,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile trial supports large text without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.2)),
          child: child!,
        ),
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: AllBranchesTrialPage(dataSource: TrialSource()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final out = File('outputs/online_overview/all_branches_trial/mobile.png');
      await out.parent.create(recursive: true);
      await out.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
