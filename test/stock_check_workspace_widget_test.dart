// ignore_for_file: depend_on_referenced_packages
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:ui_web' as ui_web;
import 'package:daily_order/core/theme/app_colors.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/stock_check_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<List<http.Request>> showStockCheck(
  WidgetTester tester, {
  String source = 'inventory',
  String? role,
  String? userName = '  Maya  ',
  bool signedIn = false,
  List<Map<String, dynamic>>? campaignSummaries,
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
        result = [
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

Future<void> composeAndSend(WidgetTester tester) async {
  await tester.tap(find.text('Create New Stock Check'));
  await tester.pumpAndSettle();
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
  setUpAll(() async {
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
