import 'package:daily_order/presentation/auth/pages/login_page.dart';
import 'package:daily_order/presentation/inventory_dashboard/page/inventory_dashboard_page.dart';
import 'package:daily_order/presentation/store_dashboard/page/store_shell_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/app_colors.dart';
import 'presentation/app/bloc/app_bloc.dart';
import 'presentation/app/bloc/app_state.dart';
import 'presentation/orders/pages/branch_orders_page.dart';

class RoleGatePage extends StatelessWidget {
  const RoleGatePage({super.key});
  String getBusinessDate() {
    final now = DateTime.now();

    final cutoff = DateTime(
      now.year,
      now.month,
      now.day,
      21, // 9 PM
    );

    final businessDate = now.isBefore(cutoff)
        ? now.subtract(const Duration(days: 1))
        : now;

    return businessDate.toIso8601String().split('T').first;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppBloc, AppState>(
      builder: (context, s) {
        if (s.status == AppStatus.failure) {
          return Scaffold(
            body: Center(child: Text('App error: ${s.error ?? ""}')),
          );
        }

        // 🔥 مهم جداً
        if (s.status == AppStatus.initial || s.status == AppStatus.loading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primaryColor),
            ),
          );
        }

        if (s.status == AppStatus.unauthenticated) {
          return const LoginPage();
        }

        if (s.me == null) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primaryColor),
            ),
          );
        }

        final role = s.me!.role.toString().trim().toLowerCase();
        final runDate = s.runDate!;
        final branchName = (s.me!.branchName ?? '').trim();

        if (role == 'store') {
          return StoreShellPage(runDate: runDate);
        }

        if (role == 'inventory') {
          return InventoryDashboardPage(runDate: runDate);
        }

        if (branchName.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('Branch is missing for this user.')),
          );
        }

        return BranchOrdersPage(branchName: branchName);
      },
    );
  }
}
