import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:daily_order/core/config/online_overview_local_config.dart';
import 'package:daily_order/domain/entities/inventory_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/stock_management_navigation.dart';
import 'package:daily_order/presentation/inventory_dashboard/widgets/online_overview_user_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'access is restricted to exactly the approved ID in every build mode',
    () {
      expect(OnlineOverviewLocalConfig.actualSalesPreview, isTrue);
      expect(
        OnlineOverviewLocalConfig.canAccess(
          OnlineOverviewLocalConfig.allowedUserId,
        ),
        isTrue,
      );
      for (final id in [
        null,
        '',
        'someone-else',
        OnlineOverviewLocalConfig.allowedUserId.toUpperCase(),
      ]) {
        expect(OnlineOverviewLocalConfig.canAccess(id), isFalse);
      }
    },
  );
  Future<void> navigation(
    WidgetTester tester,
    String? id, {
    bool visible = true,
  }) async {
    tester.view.physicalSize = const Size(500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StockManagementNavigation(
              selectedPage: InventoryPageType.nearExpiry,
              onSelected: (_) {},
              onlineUserId: id,
              showOnlineOverview: visible,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('approved account sees Online Overview below Near Expiry', (
    tester,
  ) async {
    await navigation(tester, OnlineOverviewLocalConfig.allowedUserId);
    expect(find.text('Online Overview'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Online Overview')).dy,
      greaterThan(tester.getTopLeft(find.text('Near Expiry')).dy),
    );
  });
  testWidgets(
    'other accounts never see the entry; existing stock pages remain',
    (tester) async {
      await navigation(tester, 'another-inventory-user');
      expect(find.text('Online Overview'), findsNothing);
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Near Expiry'), findsOneWidget);
    },
  );
  testWidgets('View navigation suppresses the page even for the approved ID', (
    tester,
  ) async {
    await navigation(
      tester,
      OnlineOverviewLocalConfig.allowedUserId,
      visible: false,
    );
    expect(find.text('Online Overview'), findsNothing);
  });
  testWidgets(
    'direct route does not build a page without the approved session',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnlineOverviewUserGate(child: Text('private page')),
        ),
      );
      expect(find.text('private page'), findsNothing);
    },
  );
  testWidgets('live account changes remove the private page and its menu', (
    tester,
  ) async {
    var uid = OnlineOverviewLocalConfig.allowedUserId;
    String jwt(String id) {
      String part(Object value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part({'sub': id, 'role': 'authenticated', 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600})}.test';
    }

    await Supabase.initialize(
      url: 'https://test.invalid',
      anonKey: 'test',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'access_token': jwt(uid),
            'token_type': 'bearer',
            'expires_in': 3600,
            'refresh_token': 'test-refresh',
            'user': {
              'id': uid,
              'aud': 'authenticated',
              'role': 'authenticated',
              'email': 'test@example.invalid',
              'app_metadata': {},
              'user_metadata': {},
              'created_at': '2026-01-01T00:00:00Z',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(() => Supabase.instance.dispose());
    await tester.runAsync(
      () => Supabase.instance.client.auth.setSession('test-refresh'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const OnlineOverviewUserGate(child: Text('private page')),
              StockManagementNavigation(
                selectedPage: InventoryPageType.stockManagement,
                onSelected: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('private page'), findsOneWidget);
    expect(find.text('Online Overview'), findsOneWidget);
    uid = '00000000-0000-4000-8000-000000000001';
    await tester.runAsync(
      () => Supabase.instance.client.auth.setSession('test-refresh'),
    );
    await tester.pumpAndSettle();
    expect(find.text('private page'), findsNothing);
    expect(find.text('Online Overview'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
