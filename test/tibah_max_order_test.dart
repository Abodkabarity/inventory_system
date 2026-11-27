import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:archive/archive.dart';
import 'package:daily_order/core/utils/print_service.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/core/utils/tibah_max_import.dart';
import 'package:daily_order/data/datasources/remote/tibah_order_remote_ds.dart';
import 'package:daily_order/domain/entities/store_order_item.dart';
import 'package:daily_order/domain/entities/tibah_order.dart';
import 'package:daily_order/presentation/store_dashboard/widgets/order_panel.dart';
import 'package:daily_order/presentation/store_dashboard/widgets/tibah_order_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> header({
  String id = '11111111-1111-1111-1111-111111111111',
  String state = 'ready',
  int total = 2,
}) => {
  'id': id,
  'branch': 'tibah upp',
  'order_type': 'UPP',
  'state': state,
  'total': total,
  'prepared': state == 'ready' ? total : 0,
  'uploaded_at': '2026-11-25T07:30:00Z',
  'run_date': '2026-11-25',
};

Uint8List csv(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  tearDown(() => StoreBranchIdentityRegistry.groups.value = const {});

  test(
    'CSV preserves codes and Qty, rejects duplicate/invalid/empty input',
    () async {
      final rows = await parseTibahMaxFile(
        csv(
          '\uFEFFItem Code,Item Name,Qty\n00123,Product One,20\n00456,Product Two,0\n',
        ),
        fileName: 'request.csv',
      );
      expect(rows, [
        {'item_code': '00123', 'item_name': 'Product One', 'qty': 20},
        {'item_code': '00456', 'item_name': 'Product Two', 'qty': 0},
      ]);
      for (final bad in [
        'Item Code,Item Name,Qty\n1,Product,2\n1,Product,3',
        'Item Code,Item Name,Qty\n1,Product,-1',
        'Item Code,Item Name,Qty\n1,Product,NaN',
        'Item Code,Item Name,Qty\n1,Product,Infinity',
        'Item Code,Item Name,Qty\n,Product,1',
        'Item Code,Item Name,Qty\n',
        'Wrong,Header\n1,2',
        'Item Code,Item Name,Qty\n1,,5',
        'Item Code,Item Name,Qty\n1,=A1,5',
        'Item Code,Item Name,Qty,Qty\n1,Product,5,10',
      ]) {
        await expectLater(
          parseTibahMaxFile(csv(bad), fileName: 'bad.csv'),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'each current read requests its own fixed type and both headers can coexist',
    () async {
      final requestedTypes = <String>[];
      final upp = {...header(), 'branch': 'Tibah UPP'};
      final regular = {
        ...header(id: '22222222-2222-2222-2222-222222222222'),
        'branch': 'tibah regular',
        'order_type': 'Regular',
      };
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test',
        httpClient: MockClient((request) async {
          final payload =
              jsonDecode(request.body)['p_payload'] as Map<String, dynamic>;
          final type = payload['order_type'];
          if (type != null) requestedTypes.add(type as String);
          final result = type == null
              ? {
                  'uploads': [upp, regular],
                }
              : {'upload': type == 'UPP' ? upp : regular};
          return http.Response(
            jsonEncode(result),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final remote = TibahOrderRemoteDs(client);
      expect((await remote.current(TibahOrderType.upp))!.branch, 'Tibah UPP');
      expect(
        (await remote.current(TibahOrderType.regular))!.branch,
        'tibah regular',
      );
      expect(requestedTypes, ['UPP', 'Regular']);
      expect((await remote.currentOrders()).map((o) => o.branch), [
        'Tibah UPP',
        'tibah regular',
      ]);
    },
  );

  test(
    'XLSX reads shared and inline strings, sparse cells, and rejects formulas',
    () async {
      Uint8List workbook({bool formula = false}) {
        final archive = Archive();
        void add(String name, String value) {
          final bytes = utf8.encode(value);
          archive.addFile(ArchiveFile(name, bytes.length, bytes));
        }

        add(
          'xl/sharedStrings.xml',
          '<sst><si><t>Item Code</t></si><si><t>Qty</t></si><si><t>00123</t></si><si><t>Item Name</t></si></sst>',
        );
        add(
          'xl/worksheets/sheet1.xml',
          '<worksheet><sheetData>'
              '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>3</v></c><c r="D1" t="s"><v>1</v></c></row>'
              '<row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2" t="inlineStr"><is><t>Product One</t></is></c><c r="D2">${formula ? '<f>2+3</f>' : ''}<v>5</v></c></row>'
              '<row r="3"><c r="A3" t="inlineStr"><is><t>00456</t></is></c><c r="B3" t="inlineStr"><is><t>Product Two</t></is></c><c r="D3"><v>10</v></c></row>'
              '</sheetData></worksheet>',
        );
        return Uint8List.fromList(ZipEncoder().encode(archive));
      }

      expect(await parseTibahMaxFile(workbook(), fileName: 'file.xlsx'), [
        {'item_code': '00123', 'item_name': 'Product One', 'qty': 5},
        {'item_code': '00456', 'item_name': 'Product Two', 'qty': 10},
      ]);
      await expectLater(
        parseTibahMaxFile(workbook(formula: true), fileName: 'file.xlsx'),
        throwsFormatException,
      );
    },
  );

  test(
    'upload stages 4000 rows then the remainder, commits only a complete file',
    () async {
      final batches = <int>[];
      final actions = <String>[];
      var received = 0;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final action = body['p_action'] as String;
          final payload = body['p_payload'] as Map<String, dynamic>;
          actions.add(action);
          final result = switch (action) {
            'begin' => {'id': 'batch'},
            'stage' => () {
              final size = (payload['rows'] as List).length;
              batches.add(size);
              received += size;
              return {'received': received};
            }(),
            'configure' => {'total': payload['total']},
            'commit' => {'state': 'preparing'},
            _ => throw StateError('Unexpected $action'),
          };
          return http.Response(
            jsonEncode(result),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await TibahOrderRemoteDs(client).replace(
        type: TibahOrderType.regular,
        fileName: 'file.csv',
        rows: [
          for (var i = 0; i < 4001; i++)
            {'item_code': '$i', 'item_name': 'Product $i', 'qty': 5},
        ],
      );
      expect(batches, [4000, 1]);
      expect(actions, ['begin', 'configure', 'stage', 'stage', 'commit']);
    },
  );

  test(
    'failed stage never commits or automatically retries the write',
    () async {
      final actions = <String>[];
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test',
        httpClient: MockClient((request) async {
          final action = jsonDecode(request.body)['p_action'] as String;
          actions.add(action);
          return http.Response(
            jsonEncode(
              action == 'begin'
                  ? {'id': 'batch'}
                  : action == 'configure'
                  ? {'total': 1}
                  : {'message': 'Conflict', 'code': 'PT409'},
            ),
            action == 'stage' ? 409 : 200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        TibahOrderRemoteDs(client).replace(
          type: TibahOrderType.upp,
          fileName: 'file.csv',
          rows: [
            {'item_code': '1', 'item_name': 'Product', 'qty': 5},
          ],
        ),
        throwsA(isA<PostgrestException>()),
      );
      expect(actions, ['begin', 'configure', 'stage']);
    },
  );

  test(
    'old Max is cleared before malformed file parsing and no cleanup write follows failure',
    () async {
      final actions = <String>[];
      var cleared = false;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test',
        httpClient: MockClient((request) async {
          final action = jsonDecode(request.body)['p_action'] as String;
          actions.add(action);
          expect(action, 'begin');
          return http.Response(
            jsonEncode({'id': 'new-upload', 'cleared': true}),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        TibahOrderRemoteDs(client).replaceFromFile(
          type: TibahOrderType.upp,
          fileName: 'invalid.csv',
          onCleared: () => cleared = true,
          readRows: () async {
            expect(cleared, true);
            expect(actions, ['begin']);
            return parseTibahMaxFile(
              csv('Wrong,Header\n1,2'),
              fileName: 'invalid.csv',
            );
          },
        ),
        throwsFormatException,
      );
      expect(actions, ['begin']);
      expect(TibahOrder.fromJson(header(state: 'staging')).isPending, false);
    },
  );

  test(
    'snapshot includes zero Qty in completeness and rejects replacement during loading',
    () async {
      Future<void> check(bool replaced) async {
        final order = TibahOrder.fromJson(header());
        final client = SupabaseClient(
          'https://example.supabase.co',
          'test',
          httpClient: MockClient((request) async {
            final action = jsonDecode(request.body)['p_action'];
            final result = action == 'items'
                ? {
                    'id': order.id,
                    'total': 2,
                    'rows': [
                      {
                        'item_code': '001',
                        'final_reorder_qty_store_stock_gt_0': '7',
                      },
                      {
                        'item_code': '002',
                        'final_reorder_qty_store_stock_gt_0': '0',
                      },
                    ],
                  }
                : {
                    'upload': header(
                      id: replaced
                          ? '22222222-2222-2222-2222-222222222222'
                          : order.id,
                    ),
                  };
            return http.Response(
              jsonEncode(result),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        addTearDown(client.dispose);
        if (replaced) {
          await expectLater(
            TibahOrderRemoteDs(client).items(order),
            throwsStateError,
          );
        } else {
          final items = await TibahOrderRemoteDs(client).items(order);
          expect(items.single.quantity, 7);
        }
      }

      await check(false);
      await check(true);
    },
  );

  testWidgets(
    'UPP / Regular print labels, preparation lock and branch formatting',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(750, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      StoreBranchIdentityRegistry.groups.value = const {
        'TIBAH UPP': '71',
        'TIBAH REGULAR': 'APG',
        'BAWADI': 'APG',
      };
      final captureKey = GlobalKey();
      await tester.runAsync(() async {
        for (final font in {
          'Roboto': 'C:/Windows/Fonts/arial.ttf',
          'MaterialIcons':
              'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        }.entries) {
          final file = File(font.value);
          if (file.existsSync()) {
            await (FontLoader(font.key)..addFont(
                  Future.value(ByteData.sublistView(file.readAsBytesSync())),
                ))
                .load();
          }
        }
      });
      const items = [
        StoreOrderItem(
          itemCode: '1',
          itemName: 'Medicine product',
          barcode: '001234',
          supplier: 'Supplier',
          classification: '01Medicine',
          category: 'MEDICINE',
          quantity: 7,
        ),
        StoreOrderItem(
          itemCode: '2',
          itemName: 'General product',
          barcode: '005678',
          supplier: 'Supplier',
          classification: 'General',
          category: 'GENERAL',
          quantity: 3,
        ),
      ];
      for (final type in TibahOrderType.values) {
        final data = header();
        data['order_type'] = type.label;
        data['branch'] = type.branchName;
        final order = TibahOrder.fromJson(data);
        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(750, 900),
            builder: (_, child) => MaterialApp(
              home: Scaffold(
                body: RepaintBoundary(
                  key: captureKey,
                  child: ColoredBox(
                    color: Colors.white,
                    child: OrdersPanel(
                      branch: type.branchName,
                      items: items,
                      isSubmitted: true,
                      isLoading: false,
                      tibahOrder: order,
                      tibahItemsLoaded: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            type == TibahOrderType.upp ? '71 tibah upp' : 'tibah regular',
          ),
          findsOneWidget,
        );
        expect(find.text('Print ${type.label} Medicine'), findsOneWidget);
        expect(find.text('Print ${type.label} General'), findsOneWidget);
        expect(find.text('Confirm preparation finished'), findsOneWidget);
        expect(
          find.text('Ready to prepare now\nUntil Store confirms completion'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        final output = Directory('tmp/pdfs/tibah');
        output.createSync(recursive: true);
        await tester.runAsync(() async {
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ImageByteFormat.png);
          File(
            '${output.path}/${type.label.toLowerCase()}_panel.png',
          ).writeAsBytesSync(data!.buffer.asUint8List());
          final pdf = await PrintService.buildOrdersPdf(
            branch: type.branchName,
            items: [for (var i = 0; i < 85; i++) items[i % 2]],
            isGeneral: false,
            tibahOrder: order,
          );
          File(
            '${output.path}/${type.label.toLowerCase()}_medicine.pdf',
          ).writeAsBytesSync(pdf);
          final general = await PrintService.buildOrdersPdf(
            branch: type.branchName,
            items: items,
            isGeneral: true,
            tibahOrder: order,
          );
          File(
            '${output.path}/${type.label.toLowerCase()}_general.pdf',
          ).writeAsBytesSync(general);
        });
      }
      await tester.binding.setSurfaceSize(const Size(360, 640));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrdersPanel(
              branch: 'tibah upp',
              items: const [],
              isSubmitted: true,
              isLoading: false,
              tibahOrder: TibahOrder.fromJson(header(state: 'preparing')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Print UPP Medicine'),
      );
      expect(button.onPressed, isNull);
      expect(
        find.text('Next calculation (~9 PM UAE)\nThen until Store confirms'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Max uploaded after the current calculation waits for the next cycle.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Waiting for the next order calculation'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      // Verify the compact timing label in the actual branch card's narrow
      // content area, including selected-card white foregrounds.
      for (final selected in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 250,
                  height: 114,
                  child: ColoredBox(
                    color: selected
                        ? const Color(0xFF122D40)
                        : const Color(0xFFFFEDD5),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 42),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'tibah upp',
                                  style: TextStyle(
                                    color: selected
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'UPP — PREPARING',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: selected
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 7),
                                TibahOrderWindow(
                                  order: TibahOrder.fromJson(
                                    header(state: 'preparing'),
                                  ),
                                  compact: true,
                                  selected: selected,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('Next calculation (~9 PM UAE)\nThen until Store confirms'),
          findsOneWidget,
        );
      }
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OrdersPanel(
              branch: 'tibah upp',
              items: [],
              isSubmitted: true,
              isLoading: false,
              loadError: 'Could not load the current order.',
            ),
          ),
        ),
      );
      expect(find.text('Print Medicine'), findsNothing);
      expect(find.text('Could not load the current order.'), findsOneWidget);
      expect(StoreBranchIdentityRegistry.displayName('BAWADI'), 'BAWADI');
    },
  );
}
