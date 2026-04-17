import 'package:daily_order/presentation/auth/pages/login_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../role_gate_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _init();
  }

  Future<void> _init() async {
    // 🔥 أهم سطر
    await Future.delayed(const Duration(milliseconds: 200));

    final session = Supabase.instance.client.auth.currentSession;

    print('AUTH GATE SESSION: $session');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initFuture,
      builder: (context, snapshot) {
        /// ⏳ loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final session = Supabase.instance.client.auth.currentSession;

        /// 🔐 login
        if (session == null) {
          return const LoginPage();
        }

        /// ✅ logged in
        return const RoleGatePage();
      },
    );
  }
}
