import 'package:flutter/material.dart';

import '../bloc/inventory_state.dart';
import 'inventory_additional_panel.dart';
import 'inventory_branch_grid.dart';
import 'inventory_edits_panel.dart';
import 'inventory_stats_cards.dart';

class InventoryDashboardBody extends StatelessWidget {
  final InventoryState state;
  final bool isSubmitted;

  const InventoryDashboardBody({
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
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Container(
                  width: 100,
                  height: 50,
                  decoration: const BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage("assets/images/logo1.png"),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                const Text(
                  "Inventory Dashboard",
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
          child: InventoryStatsCards(
            totalOrdersToday: state.branches.length,
            submitted: state.submittedCount,
            additionalToday: state.additionalTodayCount,
            additionalMonth: state.additionalMonthCount,
            pendingInventory: state.additionalPendingCount,
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
                child: InventoryBranchGrid(
                  branches: state.branches,
                  submitted: state.submittedBranches,
                  editsCount: state.editsCount,
                  selectedBranch: state.selectedBranch,
                  additionalTodayBranchCount: state.additionalTodayBranchCount,
                ),
              ),

              /// EDITS PANEL
              Expanded(
                child: InventoryEditsPanel(
                  edits: state.edits,
                  branch: state.selectedBranch,
                  isSubmitted: isSubmitted,
                  isLoading: state.isLoading,
                ),
              ),

              /// ADDITIONAL REQUESTS
              Expanded(
                child: InventoryAdditionalPanel(
                  requests: state.additionalRequests,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
