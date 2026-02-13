import 'package:daily_order/presentation/app/bloc/app_bloc.dart';
import 'package:daily_order/presentation/app/bloc/app_state.dart';
import 'package:daily_order/presentation/home/pages/home_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/inventory_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class RoleGatePage extends StatelessWidget {
  const RoleGatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppBloc, AppState>(
      builder: (context, s) {
        if (s.status == AppStatus.failure) {
          return Scaffold(
            body: Center(child: Text('App error: ${s.error ?? ""}')),
          );
        }

        if (s.status != AppStatus.authenticated || s.me == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final role = (s.me!.role ?? '').toString().trim().toLowerCase();

        if (role == 'inventory') {
          return const InventoryHomePage();
        }

        return const HomePage();
      },
    );
  }
}
