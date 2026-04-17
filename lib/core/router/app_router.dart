import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../presentation/app/bloc/app_bloc.dart';
import '../../presentation/app/bloc/app_state.dart';
import '../../presentation/auth/pages/login_page.dart';
import '../../role_gate_page.dart';

class AppRouter {
  static GoRouter createRouter() {
    return GoRouter(
      // 🔥 أهم تعديل
      initialLocation: '/',

      redirect: (context, state) {
        final app = context.read<AppBloc>().state;
        final path = state.uri.path;

        final session = Supabase.instance.client.auth.currentSession;

        final isLogin = path == '/login';

        print('ROUTER SESSION: $session');
        print('APP STATUS: ${app.status}');

        // ⏳ أثناء التحميل لا تعمل redirect
        if (app.status == AppStatus.initial ||
            app.status == AppStatus.loading) {
          return null;
        }

        if (session == null) {
          return isLogin ? null : '/login';
        }

        if (isLogin) {
          return '/';
        }

        return null;
      },

      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginPage()),

        GoRoute(path: '/', builder: (_, __) => const RoleGatePage()),
      ],
    );
  }
}
