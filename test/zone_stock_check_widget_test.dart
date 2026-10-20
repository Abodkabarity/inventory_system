// ignore_for_file: depend_on_referenced_packages
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:ui_web' as ui_web;

import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:daily_order/domain/entities/app_user.dart';
import 'package:daily_order/domain/repositories/auth_repository.dart';
import 'package:daily_order/domain/usecases/sign_in.dart';
import 'package:daily_order/domain/usecases/sign_out.dart';
import 'package:daily_order/presentation/auth/bloc/auth_bloc.dart';
import 'package:daily_order/presentation/zone_manager/page/zone_manager_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'zone_stock_check_remote_ds_test.dart' show Fixture, task;

class _UnusedAuthRepository implements AuthRepository {
  @override
  AppUser? getCurrentUserBasic() => null;
  @override
  Future<AppUser?> getMe() async => null;
  @override
  Future<void> signIn(String email, String password) async =>
      throw StateError('Unexpected sign-in');
  @override
  Future<void> signOut() async => throw StateError('Unexpected sign-out');
}

Future<void> settle(WidgetTester tester) async {
  // The alert pulse deliberately animates continuously.
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Fixture fixture;
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final key = utf8.decode(message!.buffer.asUint8List());
          if (key == 'AssetManifest.bin.json') {
            final manifest = const StandardMessageCodec().encodeMessage(
              <String, Object>{},
            )!;
            return ByteData.sublistView(
              utf8.encode(
                jsonEncode(
                  base64Encode(
                    manifest.buffer.asUint8List(
                      manifest.offsetInBytes,
                      manifest.lengthInBytes,
                    ),
                  ),
                ),
              ),
            );
          }
          if (key == 'assets/images/logo1.png') {
            return ByteData.sublistView(
              base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a3ioAAAAASUVORK5CYII=',
              ),
            );
          }
          return null;
        });
    ui_web.TestEnvironment.setUp(
      const ui_web.TestEnvironment(
        ignorePlatformMessages: true,
        forceTestFonts: false,
        disableFontFallbacks: true,
        keepSemanticsDisabledOnUpdate: true,
        defaultToTestUrlStrategy: true,
      ),
    );
    final fontBytes = await http.get(Uri.base.resolve('/canvaskit/roboto.ttf'));
    final font = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(fontBytes.bodyBytes)));
    await font.load();
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'key',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/stock_check_tasks')) {
          return fixture.respond(request);
        }
        final result = request.url.path.endsWith('/branches')
            ? [
                {
                  'branch_name': 'Nadd Al Hamar - DXB',
                  'zone': 'Zone7',
                  'branch_group': 'APG',
                  'order_days': [],
                },
                {
                  'branch_name': 'Other Branch',
                  'zone': 'Zone6',
                  'branch_group': '71',
                  'order_days': [],
                },
              ]
            : [];
        return http.Response(
          jsonEncode(result),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets(
    'two-zone alerts and project details have matching counts and refresh labels',
    (tester) async {
      final originalErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        // ignore: avoid_print
        print('ZONE UI ERROR: ${details.exceptionAsString()}');
        originalErrorHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalErrorHandler);
      const size = Size(2000, 1400);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.binding.setSurfaceSize(size);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        StoreBranchIdentityRegistry.groups.value = const {};
        await tester.binding.setSurfaceSize(null);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      fixture = Fixture([
        for (var i = 0; i < 1200; i++)
          {...task(i), 'system_qty': 10, 'actual_qty': 11},
        for (var i = 1200; i < 1205; i++)
          {...task(i, branch: 'Other Branch'), 'status': 'pending'},
      ], cap: 500);
      final authRepo = _UnusedAuthRepository();
      final authBloc = AuthBloc(
        signIn: SignIn(authRepo),
        signOut: SignOut(authRepo),
      );
      addTearDown(authBloc.close);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: size,
          builder: (_, _) => BlocProvider.value(
            value: authBloc,
            child: const MaterialApp(
              home: ZoneManagerPage(
                runDate: '2026-10-20',
                zoneNames: ['Zone6', 'Zone7'],
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      expect(find.text('20 pending'), findsOneWidget);
      expect(find.text('5 pending'), findsOneWidget);
      expect(find.text('25 items'), findsOneWidget);
      StoreBranchIdentityRegistry.groups.value = const {
        'OTHER BRANCH': '71',
        'NADD AL HAMAR - DXB': 'APG',
      };
      await tester.pump();
      expect(find.text('71 Other Branch'), findsWidgets);
      expect(find.text('Nadd Al Hamar - DXB'), findsWidgets);

      // A selected branch must also filter Stock Check dashboard alerts.
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await settle(tester);
      await tester.tap(find.text('Nadd Al Hamar - DXB').last);
      await settle(tester);
      expect(find.text('20 pending'), findsOneWidget);
      expect(find.text('5 pending'), findsNothing);
      expect(find.text('20 items'), findsOneWidget);

      await tester.tap(find.byTooltip('Open Stock Check project'));
      await settle(tester);
      expect(find.text('1205'), findsWidgets);
      expect(find.text('25'), findsWidgets);
      // Only the 1,180 submitted rows count toward Stock Variances.
      expect(find.text('1180'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Back to Projects'));
      await settle(tester);
      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText ==
                'Search project, branch, item code, or item name…',
      );
      await tester.enterText(search, '71 Other Branch');
      await settle(tester);
      expect(find.text('In Progress'), findsOneWidget);
      await tester.enterText(search, 'Unmanaged branch');
      await settle(tester);
      expect(find.text('In Progress'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
