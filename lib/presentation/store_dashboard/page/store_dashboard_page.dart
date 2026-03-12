import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/remote/store_remote_ds.dart';
import '../../../data/repositories/store_repository_impl.dart';
import '../../../domain/repositories/store_repository.dart';
import '../bloc/store_bloc.dart';
import '../bloc/store_event.dart';
import '../bloc/store_state.dart';
import '../widgets/store_dashboard_body.dart';

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

  bool firstLoad = true;

  @override
  void initState() {
    super.initState();
    _startRealtime();
  }

  void _startRealtime() {
    final client = Supabase.instance.client;
    final bloc = context.read<StoreBloc>();

    channel = client
        .channel('store-dashboard-live')
        /// ORDER SUBMISSIONS
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_submissions',
          callback: (_) {
            bloc.add(LoadStoreDashboard(widget.runDate, silent: true));
          },
        )
        /// ADDITIONAL REQUESTS
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'additional_requests',
          callback: (_) {
            bloc.add(LoadStoreDashboard(widget.runDate, silent: true));
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

          if (firstLoad && state.branches.isNotEmpty) {
            firstLoad = false;
          }

          return Stack(
            children: [
              StoreDashboardBody(state: state, isSubmitted: isSubmitted),

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
