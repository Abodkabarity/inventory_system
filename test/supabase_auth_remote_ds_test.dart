import 'dart:convert';
import 'dart:io';

import 'package:daily_order/data/datasources/remote/supabase_auth_remote_ds.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const userId = '00000000-0000-4000-8000-000000000001';
  late HttpServer server;
  late SupabaseClient client;
  late SupabaseAuthRemoteDs ds;
  Map<String, dynamic>? profile;
  List<Map<String, dynamic>> zones = [];
  late List<Uri> requests;

  setUp(() async {
    profile = {
      'user_id': userId,
      'role': 'store',
      'branch_name': null,
      'zone': null,
      'is_active': true,
    };
    zones = [];
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request.uri);
      request.response.headers.contentType = ContentType.json;
      Object? body;
      switch (request.uri.path) {
        case '/auth/v1/token':
          body = {
            'access_token': 'test-access-token',
            'refresh_token': 'test-refresh-token',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': userId,
              'aud': 'authenticated',
              'role': 'authenticated',
              'email': 'user@example.com',
              'app_metadata': {},
              'user_metadata': {},
              'created_at': '2026-01-01T00:00:00Z',
            },
          };
        case '/rest/v1/app_users':
          body = profile;
        case '/rest/v1/rpc/get_my_effective_zones':
          body = zones;
        default:
          request.response.statusCode = HttpStatus.notFound;
          body = {'message': 'Unexpected request: ${request.uri}'};
      }
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    ds = SupabaseAuthRemoteDs(client);
    await ds.signIn('user@example.com', 'test-password');
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  for (final branch in <String?>[null, '', '   ']) {
    test('store can load its profile with branch_name=$branch', () async {
      profile!['branch_name'] = branch;

      final user = await ds.getMeFromAppUsers();

      expect(user!.userId, userId);
      expect(user.role, 'store');
      expect(user.branchName, branch);
      expect(user.isActive, isTrue);
      final query = requests.singleWhere(
        (uri) => uri.path == '/rest/v1/app_users',
      );
      expect(query.queryParameters['user_id'], 'eq.$userId');
      expect(requests.any((uri) => uri.path.contains('/rpc/')), isFalse);
    });
  }

  for (final role in ['branch', 'store']) {
    test('$role keeps its existing branch assignment', () async {
      profile!['role'] = role;
      profile!['branch_name'] = 'RAWDAH';

      final user = await ds.getMeFromAppUsers();

      expect(user!.role, role);
      expect(user.branchName, 'RAWDAH');
    });
  }

  for (final branch in <String?>[null, '', '   ']) {
    test(
      'branch still requires an assignment with branch_name=$branch',
      () async {
        profile!['role'] = 'branch';
        profile!['branch_name'] = branch;

        await expectLater(
          ds.getMeFromAppUsers(),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'message',
              contains('No branch assigned'),
            ),
          ),
        );
      },
    );
  }

  test('branch role validation still handles spaces and casing', () async {
    profile!['role'] = ' Branch ';

    await expectLater(ds.getMeFromAppUsers(), throwsException);
  });

  for (final role in ['inventory', 'purchase', 'category']) {
    test('$role still logs in without a branch', () async {
      profile!['role'] = role;

      final user = await ds.getMeFromAppUsers();

      expect(user!.role, role);
      expect(user.branchName, isNull);
    });
  }

  for (final role in ['branch', 'store', 'inventory', 'zone_manager']) {
    test('inactive $role account is still rejected', () async {
      profile!['role'] = role;
      profile!['branch_name'] = 'RAWDAH';
      profile!['is_active'] = false;

      await expectLater(
        ds.getMeFromAppUsers(),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('This user is inactive'),
          ),
        ),
      );
    });
  }

  test('zone manager still uses assigned zones without a branch', () async {
    profile!['role'] = 'zone_manager';
    zones = [
      {'zone': 'Zone1'},
      {'zone': 'Zone2'},
    ];

    final user = await ds.getMeFromAppUsers();

    expect(user!.branchName, isNull);
    expect(user.effectiveZones, ['Zone1', 'Zone2']);
  });

  test('zone manager with no assigned zone is still rejected', () async {
    profile!['role'] = 'zone_manager';

    await expectLater(
      ds.getMeFromAppUsers(),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('No zone assigned'),
        ),
      ),
    );
  });

  test('missing app_users profile still returns null', () async {
    profile = null;

    expect(await ds.getMeFromAppUsers(), isNull);
  });
}
