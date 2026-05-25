import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../bloc/store_bloc.dart';
import '../bloc/store_event.dart';
import '../bloc/store_state.dart';
import 'order_panel.dart';

class BranchGrid extends StatelessWidget {
  final List<String> branches;
  final List<String> submitted;
  final String? selectedBranch;

  const BranchGrid({
    super.key,
    required this.branches,
    required this.submitted,
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
        crossAxisAlignment: CrossAxisAlignment.center,
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
                childAspectRatio: 2.8,
              ),

              itemCount: branches.length,

              itemBuilder: (context, i) {
                final branch = branches[i];

                final isSubmitted = submitted.contains(branch);
                final isSelected = selectedBranch == branch;

                return GestureDetector(
                  onTap: () {
                    final bloc = context.read<StoreBloc>();

                    // =========================
                    // LOAD BRANCH
                    // =========================

                    bloc.add(SelectBranch(branch));

                    // =========================
                    // SHOW DIALOG
                    // =========================

                    showDialog(
                      context: context,

                      barrierDismissible: true,

                      builder: (_) {
                        return BlocProvider.value(
                          value: bloc,

                          child: BlocBuilder<StoreBloc, StoreState>(
                            builder: (_, state) {
                              final isSubmitted =
                                  state.selectedBranch != null &&
                                  state.submittedBranches.contains(
                                    state.selectedBranch,
                                  );

                              return Dialog(
                                backgroundColor: Colors.transparent,

                                insetPadding: const EdgeInsets.all(30),

                                child: Container(
                                  width: 650,

                                  height:
                                      MediaQuery.of(context).size.height * .88,

                                  decoration: BoxDecoration(
                                    color: Colors.white,

                                    borderRadius: BorderRadius.circular(26),
                                  ),

                                  child: OrdersPanel(
                                    items: state.items,

                                    branch: state.selectedBranch,

                                    isSubmitted: isSubmitted,

                                    isLoading: state.isLoading,
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    );
                  },

                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),

                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),

                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primaryColor
                          : isSubmitted
                          ? Colors.greenAccent.shade100
                          : Colors.white,

                      borderRadius: BorderRadius.circular(14),

                      border: Border.all(
                        color: isSelected
                            ? AppColors.primaryColor
                            : Colors.grey.shade200,
                        width: isSelected ? 2 : 1,
                      ),

                      boxShadow: [
                        BoxShadow(
                          blurRadius: 12,
                          color: Colors.black.withValues(alpha: .06),
                        ),
                      ],
                    ),

                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: isSelected
                              ? Colors.white
                              : Colors.blue.shade50,
                          child: Icon(
                            isSubmitted ? Icons.check : Icons.store,
                            size: isSubmitted ? 25 : 18,
                            color: isSelected
                                ? AppColors.secondaryColor
                                : isSubmitted
                                ? Colors.green
                                : AppColors.primaryColor,
                          ),
                        ),

                        const SizedBox(width: 10),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                branch,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? Colors.white
                                      : AppColors.secondaryColor,
                                ),
                              ),

                              const SizedBox(height: 4),

                              Text(
                                isSubmitted ? "Submitted" : "Not Submitted Yet",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isSelected
                                      ? Colors.white70
                                      : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),

                        if (isSubmitted)
                          Icon(
                            Icons.check_circle,
                            color: isSelected ? Colors.white : Colors.green,
                            size: 25,
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
