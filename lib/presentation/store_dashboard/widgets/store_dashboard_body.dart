import 'package:daily_order/presentation/store_dashboard/widgets/stats_cards.dart';
import 'package:flutter/material.dart';

import '../bloc/store_state.dart';
import 'additional_requests_panel.dart';
import 'branch_grid.dart';

class StoreDashboardBody extends StatelessWidget {
  final StoreState state;
  final bool isSubmitted;

  const StoreDashboardBody({
    super.key,
    required this.state,
    required this.isSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 20),

        /// HEADER
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Container(
                  width: 100,
                  height: 50,
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage("assets/images/logo1.png"),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                SizedBox(width: 6),
                Text(
                  "Store Dashboard",
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
              ],
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
              SizedBox(width: 15),

              /// ADDITIONAL REQUESTS
              Expanded(
                child: AdditionalPanel(requests: state.additionalRequests),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
