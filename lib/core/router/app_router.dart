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

        // Not logged in -> always go login
        if (app.status == AppStatus.unauthenticated) {
          return path == '/login' ? null : '/login';
        }

        // Logged in -> prevent staying on /login
        if (app.status == AppStatus.authenticated && path == '/login') {
          return '/';
        }

        // While app is loading (initial) allow current path
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
