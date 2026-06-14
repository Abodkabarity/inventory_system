import 'package:daily_order/presentation/inventory_dashboard/page/tma_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/remote/inventory_remote_ds.dart';
import '../../../data/repositories/inventory_repository_impl.dart';
import '../../../domain/entities/inventory_page.dart';
import '../../../domain/repositories/inventory_repository.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';
import '../widgets/inventory_dashboard_body.dart';
import '../widgets/inventory_drawer.dart';
import 'additional_order_analysis_page.dart';
import 'assortment_page.dart';
import 'branches_tracker_page.dart';
import 'formulary_page.dart';
import 'inventory_daily_order_page.dart';
import 'max_adjustment_page.dart';
import 'mismatch_page.dart';

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
    return Theme(
      data: Theme.of(context).copyWith(
        textSelectionTheme: const TextSelectionThemeData(
          selectionColor: AppColors.primaryColor,
          selectionHandleColor: AppColors.primaryColor,
          cursorColor: AppColors.primaryColor,
        ),
      ),
      child: SelectionArea(
        child: Scaffold(
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
                  Row(
                    children: [
                      const InventoryDrawer(),

                      Expanded(
                        child: _buildPage(state, isSubmitted, widget.runDate),
                      ),
                    ],
                  ),

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
        ),
      ),
    );
  }
}

Widget _buildPage(InventoryState state, bool isSubmitted, String runDate) {
  switch (state.currentPage) {
    case InventoryPageType.dashboard:
      return InventoryDashboardBody(state: state, isSubmitted: isSubmitted);

    case InventoryPageType.mismatch:
      return const MismatchPage();

    case InventoryPageType.maxAdjustment:
      return const MaxAdjustmentPage();

    case InventoryPageType.formulary:
      return const FormularyPage();

    case InventoryPageType.assortment:
      return const AssortmentPage();
    case InventoryPageType.tma:
      return const TmaPage();

    case InventoryPageType.dailyOrder:
      return InventoryDailyOrderPage(runDate: runDate);
    case InventoryPageType.additionalOrderAnalysis:
      return const AdditionalOrderAnalysisPage();
    case InventoryPageType.branchesTracker:
      return const BranchesTrackerPage();
  }
}
