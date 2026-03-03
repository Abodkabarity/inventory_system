import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../bloc/order_bloc/orders_bloc.dart';
import '../bloc/order_bloc/orders_bloc_factory.dart';
import '../widgets/branch_zone_cubit.dart';
import 'branch_orders_screen.dart';

class BranchOrdersPage extends StatelessWidget {
  final String runDate;
  final String branchName;

  const BranchOrdersPage({
    super.key,
    required this.runDate,
    required this.branchName,
  });

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<OrdersBloc>(
          create: (_) => OrdersBlocFactory.create(
            runDate: runDate,
            branchName: branchName,
          ),
        ),
        BlocProvider<BranchZoneCubit>(
          create: (_) => BranchZoneCubit(
            client: Supabase.instance.client,
            branchName: branchName,
          ),
        ),
      ],
      child: const BranchOrdersScreen(),
    );
  }
}
