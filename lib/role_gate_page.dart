import 'package:daily_order/presentation/store_dashboard/page/store_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/theme/app_colors.dart';
import 'presentation/app/bloc/app_bloc.dart';
import 'presentation/app/bloc/app_state.dart';
import 'presentation/orders/pages/branch_orders_page.dart';

class RoleGatePage extends StatelessWidget {
  const RoleGatePage({super.key});

  String _today() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
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

        if (s.status != AppStatus.authenticated || s.me == null) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primaryColor),
            ),
          );
        }

        final role = (s.me!.role).toString().trim().toLowerCase();
        final runDate = _today();
        final branchName = (s.me!.branchName ?? '').trim();

        if (role == 'store') {
          return StoreDashboardPage(runDate: runDate);
        }
        if (branchName.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('Branch is missing for this user.')),
          );
        }

        return BranchOrdersPage(runDate: runDate, branchName: branchName);
      },
    );
  }
}
