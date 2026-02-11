import 'package:go_router/go_router.dart';

import '../../presentation/auth/pages/login_page.dart';
import '../../presentation/home/pages/home_page.dart';

class AppRouter {
  static GoRouter createRouter() {
    return GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
        GoRoute(path: '/home', builder: (_, __) => const HomePage()),
      ],
    );
  }
}
