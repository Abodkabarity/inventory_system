import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/operational_date_helper.dart';
import '../bloc/store_bloc.dart';
import '../bloc/store_event.dart';
import '../bloc/store_state.dart';
import 'order_panel.dart';
import 'store_branch_identity.dart';

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
                crossAxisSpacing: 5,
                childAspectRatio: 2.2,
              ),

              itemCount: branches.length,

              itemBuilder: (context, i) {
                final branch = branches[i];

                final isSubmitted = submitted.contains(branch);
                final isSelected = selectedBranch == branch;

                final isPrinted = context
                    .read<StoreBloc>()
                    .state
                    .printedBranches
                    .contains(branch);
                final blocState = context.read<StoreBloc>().state;

                final startHour = blocState.submitStartHours[branch] ?? 0;

                final endHour = blocState.submitEndHours[branch] ?? 24;

                final isLate =
                    OperationalDateHelper.isMissingWindowForBranch(
                      startHour: startHour,
                      endHour: endHour,
                    ) &&
                    !isSubmitted;
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
                                    onClose: () {
                                      Navigator.of(context).pop();
                                    },
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
                          : isPrinted
                          ? Colors.greenAccent.shade100
                          : isLate
                          ? Colors.red.shade100
                          : isSubmitted
                          ? Colors.orange.shade100
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
                            isPrinted
                                ? Icons.check
                                : isSubmitted
                                ? Icons.inventory_2
                                : Icons.store,
                            size: isPrinted ? 25 : 18,
                            color: isSelected
                                ? AppColors.secondaryColor
                                : isPrinted
                                ? Colors.green
                                : isSubmitted
                                ? Colors.orange
                                : AppColors.primaryColor,
                          ),
                        ),

                        const SizedBox(width: 10),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              StoreBranchLabel(
                                branchName: branch,
                                mainAxisAlignment: MainAxisAlignment.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? Colors.white
                                      : AppColors.secondaryColor,
                                ),
                              ),

                              const SizedBox(height: 4),

                              Builder(
                                builder: (_) {
                                  String statusText;
                                  Color statusColor;

                                  if (isPrinted) {
                                    statusText = "PRINTED";
                                    statusColor = Colors.green.shade800;
                                  } else if (isSubmitted) {
                                    statusText = "SUBMITTED";
                                    statusColor = Colors.deepOrange;
                                  } else if (isLate) {
                                    statusText = "BRANCH NOT SUBMIT THE ORDER";
                                    statusColor = Colors.red.shade900;
                                  } else {
                                    statusText = "NOT SUBMITTED YET";
                                    statusColor = Colors.grey;
                                  }

                                  return Text(
                                    statusText,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? Colors.white70
                                          : statusColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  );
                                },
                              ),

                              const SizedBox(height: 7),

                              _DeadlinePill(
                                hour: endHour,
                                isSelected: isSelected,
                                isLate: isLate,
                                isPrinted: isPrinted,
                              ),
                            ],
                          ),
                        ),

                        if (isPrinted)
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

class _DeadlinePill extends StatelessWidget {
  final int hour;
  final bool isSelected;
  final bool isLate;
  final bool isPrinted;

  const _DeadlinePill({
    required this.hour,
    required this.isSelected,
    required this.isLate,
    required this.isPrinted,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isSelected
        ? Colors.white
        : isLate
        ? Colors.red.shade900
        : isPrinted
        ? Colors.green.shade900
        : const Color(0xff475569);
    final bgColor = isSelected
        ? Colors.white.withValues(alpha: .18)
        : Colors.white.withValues(alpha: .72);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isSelected
              ? Colors.white.withValues(alpha: .22)
              : Colors.black.withValues(alpha: .05),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 13, color: textColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Deadline ${_formatHour(hour)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatHour(int hour) {
    if (hour >= 24) return '12:00 AM';
    final normalized = hour.clamp(0, 23);
    final suffix = normalized >= 12 ? 'PM' : 'AM';
    final displayHour = normalized % 12 == 0 ? 12 : normalized % 12;
    return '$displayHour:00 $suffix';
  }
}
