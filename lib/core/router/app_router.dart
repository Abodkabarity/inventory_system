import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/app/bloc/app_bloc.dart';
import '../../presentation/app/bloc/app_state.dart';
import '../../presentation/auth/pages/login_page.dart';
import '../../role_gate_page.dart';

class AppRouter {
  static GoRouter createRouter() {
    return GoRouter(
      initialLocation: '/login',
      redirect: (context, state) {
        final app = context.read<AppBloc>().state;
        final path = state.uri.path;

        final isAuth = app.status == AppStatus.authenticated;
        final isUnauth = app.status == AppStatus.unauthenticated;
        final isLogin = path == '/login';

        // While app is still initializing, do not redirect.
        if (app.status == AppStatus.initial) {
          return null;
        }

        // Not logged in -> always go to login.
        if (isUnauth) {
          return isLogin ? null : '/login';
        }

        // Logged in -> prevent staying on login.
        if (isAuth && isLogin) {
          return '/';
        }

        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
        GoRoute(path: '/', builder: (_, __) => const RoleGatePage()),

        GoRoute(path: '/home', redirect: (_, __) => '/'),
      ],
    );
  }
}
