import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/theme/app_colors.dart';
import '../app/bloc/app_bloc.dart';
import '../orders/pages/branch_orders_page.dart';
import 'bloc/branch_entry_bloc.dart';
import 'bloc/branch_entry_bloc_factory.dart';
import 'bloc/branch_entry_event.dart';
import 'bloc/branch_entry_state.dart';

class BranchOrdersEntryPage extends StatelessWidget {
  const BranchOrdersEntryPage({super.key});

  String _today() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppBloc>().state;
    final branchId = app.me?.branchName?.toString().trim() ?? '';

    if (branchId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('This user has no branch_id.')),
      );
    }

    return BlocProvider(
      create: (_) =>
          BranchEntryBlocFactory.create()
            ..add(LoadMyBranchEntry(branchId: branchId)),
      child: BlocBuilder<BranchEntryBloc, BranchEntryState>(
        builder: (context, s) {
          if (s.status == BranchEntryStatus.loading ||
              s.status == BranchEntryStatus.initial) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: AppColors.primaryColor),
              ),
            );
          }

          if (s.status == BranchEntryStatus.failure) {
            return Scaffold(
              body: Center(child: Text('Branch load error: ${s.error ?? ""}')),
            );
          }

          final name = (s.branchName ?? '').trim();
          if (name.isEmpty) {
            return const Scaffold(
              body: Center(child: Text('Branch name is empty.')),
            );
          }

          return BranchOrdersPage(branchName: name);
        },
      ),
    );
  }
}
