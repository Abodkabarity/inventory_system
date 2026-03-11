import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/datasources/remote/store_remote_ds.dart';
import '../../../data/repositories/store_repository_impl.dart';
import '../../../domain/repositories/store_repository.dart';
import '../bloc/store_bloc.dart';
import '../bloc/store_event.dart';
import '../bloc/store_state.dart';
import '../widgets/additional_requests_panel.dart';
import '../widgets/branch_grid.dart';
import '../widgets/order_panel.dart';
import '../widgets/stats_cards.dart';

class StoreDashboardPage extends StatelessWidget {
  final String runDate;

  const StoreDashboardPage({super.key, required this.runDate});

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;

    final remote = StoreRemoteDs(client);
    final StoreRepository repo = StoreRepositoryImpl(remote);

    return BlocProvider(
      create: (_) => StoreBloc(repo)..add(LoadStoreDashboard(runDate)),
      child: StoreDashboardView(runDate: runDate),
    );
  }
}

class StoreDashboardView extends StatefulWidget {
  final String runDate;

  const StoreDashboardView({super.key, required this.runDate});

  @override
  State<StoreDashboardView> createState() => _StoreDashboardViewState();
}

class _StoreDashboardViewState extends State<StoreDashboardView> {
  RealtimeChannel? channel;

  @override
  void initState() {
    super.initState();
    _startRealtime();
  }

  void _startRealtime() {
    final bloc = context.read<StoreBloc>();

    channel = Supabase.instance.client
        .channel('store-dashboard-live')
        /// DAILY ORDER CHANGES
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'daily_order',
          callback: (payload) {
            bloc.add(LoadStoreDashboard(widget.runDate));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'daily_order',
          callback: (payload) {
            bloc.add(LoadStoreDashboard(widget.runDate));
          },
        )
        /// ADDITIONAL REQUESTS
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'additional_requests',
          callback: (payload) {
            bloc.add(LoadStoreDashboard(widget.runDate));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'additional_requests',
          callback: (payload) {
            bloc.add(LoadStoreDashboard(widget.runDate));
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

      body: BlocBuilder<StoreBloc, StoreState>(
        builder: (context, state) {
          final bool isSubmitted =
              state.selectedBranch != null &&
              state.submittedBranches.contains(state.selectedBranch);

          return Column(
            children: [
              const SizedBox(height: 20),

              /// HEADER
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Store Dashboard",
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              /// KPI CARDS
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: StatsCards(
                  totalOrdersToday: state.branches.length,
                  submitted: state.submittedCount,
                  additional: state.additionalCount,
                  additionalPending: state.additionalPendingCount,
                  additionalDone: state.additionalDoneCount,
                ),
              ),

              const SizedBox(height: 20),

              /// MAIN LAYOUT
              Expanded(
                child: Row(
                  children: [
                    /// BRANCH GRID
                    SizedBox(
                      width: 600,
                      child: BranchGrid(
                        branches: state.branches,
                        submitted: state.submittedBranches,
                        selectedBranch: state.selectedBranch,
                      ),
                    ),

                    /// ORDERS PANEL
                    Expanded(
                      child: OrdersPanel(
                        items: state.items,
                        branch: state.selectedBranch,
                        isSubmitted: isSubmitted,
                      ),
                    ),

                    /// ADDITIONAL REQUESTS
                    Expanded(
                      child: AdditionalPanel(
                        requests: state.additionalRequests,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
