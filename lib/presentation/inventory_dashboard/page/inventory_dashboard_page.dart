import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/remote/inventory_remote_ds.dart';
import '../../../data/repositories/inventory_repository_impl.dart';
import '../../../domain/repositories/inventory_repository.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';
import '../widgets/inventory_dashboard_body.dart';

class InventoryDashboardPage extends StatelessWidget {
  final String runDate;

  const InventoryDashboardPage({super.key, required this.runDate});

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;

    final remote = InventoryRemoteDs(client);

    final InventoryRepository repo = InventoryRepositoryImpl(remote);

    return BlocProvider(
      create: (_) => InventoryBloc(repo)..add(LoadInventoryDashboard(runDate)),
      child: InventoryDashboardView(runDate: runDate),
    );
  }
}

class InventoryDashboardView extends StatefulWidget {
  final String runDate;

  const InventoryDashboardView({super.key, required this.runDate});

  @override
  State<InventoryDashboardView> createState() => _InventoryDashboardViewState();
}

class _InventoryDashboardViewState extends State<InventoryDashboardView> {
  RealtimeChannel? channel;

  bool firstLoad = true;

  @override
  void initState() {
    super.initState();
    _startRealtime();
  }

  void _startRealtime() {
    final client = Supabase.instance.client;

    final bloc = context.read<InventoryBloc>();

    channel = client
        .channel('inventory-dashboard-live')
        /// ORDER SUBMISSIONS
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_submissions',
          callback: (_) {
            bloc.add(LoadInventoryDashboard(widget.runDate, silent: true));
          },
        )
        /// ADDITIONAL REQUESTS
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'additional_requests',
          callback: (_) {
            bloc.add(LoadInventoryDashboard(widget.runDate, silent: true));
          },
        )
        /// ORDER EDITS
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_edits',
          callback: (_) {
            bloc.add(LoadInventoryDashboard(widget.runDate, silent: true));
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF4F7FB),

      body: BlocBuilder<InventoryBloc, InventoryState>(
        builder: (context, state) {
          final bool isSubmitted =
              state.selectedBranch != null &&
              state.submittedBranches.contains(state.selectedBranch);

          if (firstLoad && state.branches.isNotEmpty) {
            firstLoad = false;
          }

          return Stack(
            children: [
              InventoryDashboardBody(state: state, isSubmitted: isSubmitted),

              if (firstLoad)
                Container(
                  color: Colors.black12,
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primaryColor,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
