import 'package:daily_order/presentation/inventory_dashboard/page/tma_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/remote/inventory_remote_ds.dart';
import '../../../data/repositories/inventory_repository_impl.dart';
import '../../../domain/entities/inventory_page.dart';
import '../../../domain/repositories/inventory_repository.dart';
import '../../items_tracker/page/items_tracker_page.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';
import '../bloc/inventory_state.dart';
import '../widgets/inventory_dashboard_body.dart';
import '../widgets/inventory_drawer.dart';
import 'additional_order_analysis_page.dart';
import 'inventory_additional_orders_page.dart';
import 'allocation_page.dart';
import 'availability_kpi_page.dart';
import 'fill_rate_kpi_page.dart';
import 'assortment_page.dart';
import 'branch_submission_tracker_page.dart';
import 'branch_setting_page.dart';
import 'branches_tracker_page.dart';
import 'formulary_page.dart';
import 'inventory_daily_order_page.dart';
import 'max_adjustment_page.dart';
import 'mismatch_page.dart';
import 'order_edit_analysis_page.dart';
import 'purchase_shortage_page.dart';
import 'stock_check_page.dart';

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
  bool _drawerCollapsed = false;

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
      child: Scaffold(
        backgroundColor: const Color(0xffF4F7FB),
        body: BlocBuilder<InventoryBloc, InventoryState>(
          buildWhen: (previous, current) {
            if (previous.currentPage != current.currentPage) return true;
            if (previous.branches.isEmpty != current.branches.isEmpty) {
              return true;
            }

            if (current.currentPage == InventoryPageType.dashboard) {
              return previous != current;
            }

            return previous.selectedBranch != current.selectedBranch ||
                previous.submittedBranches != current.submittedBranches;
          },
          builder: (context, state) {
            final bool isSubmitted =
                state.selectedBranch != null &&
                state.submittedBranches.contains(state.selectedBranch);

            if (firstLoad && state.isDashboardLoaded) {
              firstLoad = false;
            }

            return Stack(
              children: [
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      width: _drawerCollapsed ? 0 : 270,
                      child: ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: _drawerCollapsed ? 0 : 1,
                          child: const InventoryDrawer(),
                        ),
                      ),
                    ),

                    Expanded(
                      child: _buildPage(state, isSubmitted, widget.runDate),
                    ),
                  ],
                ),

                Positioned(
                  top: 16,
                  left: _drawerCollapsed ? 10 : 252,
                  child: _DrawerToggleButton(
                    collapsed: _drawerCollapsed,
                    onPressed: () {
                      setState(() {
                        _drawerCollapsed = !_drawerCollapsed;
                      });
                    },
                  ),
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
    );
  }
}

class _DrawerToggleButton extends StatelessWidget {
  final bool collapsed;
  final VoidCallback onPressed;

  const _DrawerToggleButton({required this.collapsed, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: collapsed ? 'Show menu' : 'Hide menu',
      child: Material(
        color: Colors.white,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Icon(
              collapsed
                  ? Icons.keyboard_double_arrow_right_rounded
                  : Icons.keyboard_double_arrow_left_rounded,
              color: AppColors.primaryColor,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

Widget _buildPage(InventoryState state, bool isSubmitted, String runDate) {
  switch (state.currentPage) {
    case InventoryPageType.dashboard:
      return InventoryDashboardBody(
        state: state,
        isSubmitted: isSubmitted,
        runDate: runDate,
      );

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

    case InventoryPageType.additionalOrders:
      return const InventoryAdditionalOrdersPage();
    case InventoryPageType.itemsTracker:
      return const ItemsTrackerPage(role: 'inventory', embedded: true);

    case InventoryPageType.dailyOrder:
      return InventoryDailyOrderPage(runDate: runDate);
    case InventoryPageType.additionalOrderAnalysis:
      return const AdditionalOrderAnalysisPage();
    case InventoryPageType.orderEditAnalysis:
      return const OrderEditAnalysisPage();
    case InventoryPageType.branchSubmissionTracker:
      return const BranchSubmissionTrackerPage();
    case InventoryPageType.branchesTracker:
      return const BranchesTrackerPage();
    case InventoryPageType.allocation:
      return AllocationPage(runDate: runDate);
    case InventoryPageType.stockCheck:
      return StockCheckPage(runDate: runDate);
    case InventoryPageType.shortage:
      return PurchaseShortagePage(runDate: runDate);
    case InventoryPageType.availabilityKpi:
      return AvailabilityKpiPage(runDate: runDate);
    case InventoryPageType.fillRateKpi:
      return const FillRateKpiPage();
    case InventoryPageType.branchSetting:
      return const BranchSettingPage();
  }
}
