import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../bloc/inventory_bloc.dart';
import 'branch_analytics_dialog.dart';

class InventoryBranchGrid extends StatelessWidget {
  final List<String> branches;
  final List<String> submitted;
  final Map<String, DateTime> submittedBranchTimes;
  final Map<String, int> submitEndHours;
  final Map<String, int> editsCount;

  /// NEW
  final Map<String, int> additionalTodayBranchCount;

  final String? selectedBranch;

  const InventoryBranchGrid({
    super.key,
    required this.branches,
    required this.submitted,
    required this.submittedBranchTimes,
    required this.submitEndHours,
    required this.editsCount,
    required this.additionalTodayBranchCount,
    required this.selectedBranch,
  });

  @override
  Widget build(BuildContext context) {
    final submittedSet = submitted.map(_branchKey).toSet();
    final sortedBranches = [...branches]
      ..sort((a, b) {
        final aSubmitted = submittedSet.contains(_branchKey(a));
        final bSubmitted = submittedSet.contains(_branchKey(b));

        if (aSubmitted != bSubmitted) {
          return aSubmitted ? -1 : 1;
        }

        if (aSubmitted && bSubmitted) {
          final aTime = _submittedAtFor(a);
          final bTime = _submittedAtFor(b);

          if (aTime != null && bTime != null) {
            return aTime.compareTo(bTime);
          }
          if (aTime != null) return -1;
          if (bTime != null) return 1;
        }

        return branches.indexOf(a).compareTo(branches.indexOf(b));
      });

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
                childAspectRatio: 1.8,
              ),
              itemCount: sortedBranches.length,

              itemBuilder: (context, i) {
                final branch = sortedBranches[i];

                final isSubmitted = submittedSet.contains(_branchKey(branch));
                final isSelected = selectedBranch == branch;

                final edits = editsCount[branch] ?? 0;
                final endHour = _lookupInt(submitEndHours, branch) ?? 24;

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

                        const SizedBox(height: 8),

                        _DeadlinePill(
                          hour: endHour,
                          isSelected: isSelected,
                          isSubmitted: isSubmitted,
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

  String _branchKey(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  DateTime? _submittedAtFor(String branch) {
    final exact = submittedBranchTimes[branch];
    if (exact != null) return exact;

    final key = _branchKey(branch);
    for (final entry in submittedBranchTimes.entries) {
      if (_branchKey(entry.key) == key) return entry.value;
    }
    return null;
  }

  int? _lookupInt(Map<String, int> map, String branch) {
    final exact = map[branch];
    if (exact != null) return exact;

    final key = _branchKey(branch);
    for (final entry in map.entries) {
      if (_branchKey(entry.key) == key) return entry.value;
    }
    return null;
  }
}

class _DeadlinePill extends StatelessWidget {
  final int hour;
  final bool isSelected;
  final bool isSubmitted;

  const _DeadlinePill({
    required this.hour,
    required this.isSelected,
    required this.isSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isSelected
        ? Colors.white
        : isSubmitted
        ? Colors.green.shade900
        : const Color(0xff475569);
    final bgColor = isSelected
        ? Colors.white.withValues(alpha: .18)
        : isSubmitted
        ? Colors.white.withValues(alpha: .55)
        : const Color(0xffF1F5F9);

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
          Text(
            'Deadline ${_formatHour(hour)}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textColor,
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
