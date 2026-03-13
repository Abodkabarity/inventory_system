import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../bloc/inventory_bloc.dart';
import 'branch_analytics_dialog.dart';

class InventoryBranchGrid extends StatelessWidget {
  final List<String> branches;
  final List<String> submitted;
  final Map<String, int> editsCount;

  /// NEW
  final Map<String, int> additionalTodayBranchCount;

  final String? selectedBranch;

  const InventoryBranchGrid({
    super.key,
    required this.branches,
    required this.submitted,
    required this.editsCount,
    required this.additionalTodayBranchCount,
    required this.selectedBranch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: AppColors.backgroundWidget,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              "Branches Ordering Today",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.secondaryColor,
              ),
            ),
          ),

          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 2.4,
              ),
              itemCount: branches.length,

              itemBuilder: (context, i) {
                final branch = branches[i];

                final isSubmitted = submitted.contains(branch);
                final isSelected = selectedBranch == branch;

                final edits = editsCount[branch] ?? 0;

                /// NEW
                final additionalToday = additionalTodayBranchCount[branch] ?? 0;

                return GestureDetector(
                  onTap: () {
                    final bloc = context.read<InventoryBloc>();

                    showDialog(
                      context: context,
                      builder: (_) => BlocProvider.value(
                        value: bloc,
                        child: BranchAnalyticsDialog(branch: branch),
                      ),
                    );
                  },

                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.all(16),

                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? const LinearGradient(
                              colors: [Color(0xff4a6cf7), Color(0xff2f4dd9)],
                            )
                          : null,

                      color: isSelected
                          ? null
                          : isSubmitted
                          ? Colors.greenAccent.shade100
                          : Colors.white,

                      borderRadius: BorderRadius.circular(14),

                      boxShadow: [
                        BoxShadow(
                          blurRadius: 14,
                          color: Colors.black.withValues(alpha: .06),
                        ),
                      ],
                    ),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isSubmitted ? Icons.check_circle : Icons.store,
                              color: isSelected
                                  ? Colors.white
                                  : isSubmitted
                                  ? Colors.green
                                  : AppColors.primaryColor,
                            ),

                            const Spacer(),

                            /// ADDITIONAL REQUEST BADGE
                            if (additionalToday > 0)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  "$additionalToday req",
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                  ),
                                ),
                              ),

                            /// EDITS BADGE
                            if (edits > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  "$edits edits",
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        Text(
                          branch,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isSelected
                                ? Colors.white
                                : AppColors.secondaryColor,
                          ),
                        ),

                        const SizedBox(height: 6),

                        Text(
                          isSubmitted
                              ? "Order Submitted"
                              : "Waiting Submission",
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected ? Colors.white70 : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
