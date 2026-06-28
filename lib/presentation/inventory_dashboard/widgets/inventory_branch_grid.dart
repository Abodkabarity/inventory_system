import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../bloc/inventory_bloc.dart';
import '../bloc/inventory_event.dart';

class InventoryBranchGrid extends StatelessWidget {
  final List<String> branches;
  final List<String> submitted;
  final Map<String, DateTime> submittedBranchTimes;
  final Map<String, int> submitEndHours;
  final Map<String, int> editsCount;
  final String runDate;

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
    required this.runDate,
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
            child: sortedBranches.isEmpty
                ? const _NoBranchesToday()
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 1.8,
                        ),
                    itemCount: sortedBranches.length,

                    itemBuilder: (context, i) {
                      final branch = sortedBranches[i];

                      final isSubmitted = submittedSet.contains(
                        _branchKey(branch),
                      );
                      final isSelected = selectedBranch == branch;

                      final edits = editsCount[branch] ?? 0;
                      final endHour = _lookupInt(submitEndHours, branch) ?? 24;

                      /// NEW
                      final additionalToday =
                          additionalTodayBranchCount[branch] ?? 0;

                      return GestureDetector(
                        onTap: () {
                          final bloc = context.read<InventoryBloc>();

                          showDialog(
                            context: context,
                            builder: (_) => BlocProvider.value(
                              value: bloc,
                              child: _SubmitBranchDialog(
                                branch: branch,
                                runDate: runDate,
                                isSubmitted: isSubmitted,
                              ),
                            ),
                          );
                        },

                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          padding: const EdgeInsets.all(16),

                          decoration: BoxDecoration(
                            gradient: isSelected
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xff4a6cf7),
                                      Color(0xff2f4dd9),
                                    ],
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
                                    isSubmitted
                                        ? Icons.check_circle
                                        : Icons.store,
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
                                  color: isSelected
                                      ? Colors.white70
                                      : Colors.grey,
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

class _NoBranchesToday extends StatelessWidget {
  const _NoBranchesToday();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(18),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .76),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white),
          boxShadow: [
            BoxShadow(
              blurRadius: 18,
              offset: const Offset(0, 8),
              color: Colors.black.withValues(alpha: .05),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xffE0F2FE),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.event_available_rounded,
                color: AppColors.primaryColor,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'No Branches Ordering Today',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.secondaryColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'There are no active branches scheduled for this order date.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.blueGrey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmitBranchDialog extends StatefulWidget {
  final String branch;
  final String runDate;
  final bool isSubmitted;

  const _SubmitBranchDialog({
    required this.branch,
    required this.runDate,
    required this.isSubmitted,
  });

  @override
  State<_SubmitBranchDialog> createState() => _SubmitBranchDialogState();
}

class _SubmitBranchDialogState extends State<_SubmitBranchDialog> {
  bool _submitting = false;

  Future<void> _waitForBranchAction(InventoryBloc bloc) {
    return bloc.stream.firstWhere(
      (state) =>
          !state.isBulkLoading &&
          (state.bulkMessage ?? '').contains(widget.branch),
    );
  }

  void _showResultSnack(InventoryBloc bloc) {
    final result = bloc.state;
    final success = result.bulkSuccess == true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: success ? const Color(0xff16A34A) : Colors.red,
        content: Row(
          children: [
            Icon(
              success
                  ? Icons.check_circle_rounded
                  : Icons.error_outline_rounded,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                result.bulkMessage ??
                    (success ? 'Action completed' : 'Action failed'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_submitting || widget.isSubmitted) return;

    setState(() => _submitting = true);

    final bloc = context.read<InventoryBloc>();
    bloc.add(SubmitBranchFromInventory(widget.branch));

    await _waitForBranchAction(bloc);

    if (!mounted) return;

    Navigator.of(context).pop();
    _showResultSnack(bloc);
  }

  Future<void> _deleteSubmit() async {
    if (_submitting || !widget.isSubmitted) return;

    setState(() => _submitting = true);

    final bloc = context.read<InventoryBloc>();
    bloc.add(DeleteBranchSubmissionFromInventory(widget.branch));

    await _waitForBranchAction(bloc);

    if (!mounted) return;

    Navigator.of(context).pop();
    _showResultSnack(bloc);
  }

  @override
  Widget build(BuildContext context) {
    final alreadySubmitted = widget.isSubmitted;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                blurRadius: 28,
                offset: const Offset(0, 14),
                color: Colors.black.withValues(alpha: .14),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: alreadySubmitted
                          ? const Color(0xffDCFCE7)
                          : const Color(0xffE0F2FE),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      alreadySubmitted
                          ? Icons.undo_rounded
                          : Icons.assignment_turned_in_rounded,
                      color: alreadySubmitted
                          ? Colors.red
                          : AppColors.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alreadySubmitted
                              ? 'Delete Branch Submit?'
                              : 'Submit Branch Order?',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppColors.secondaryColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.runDate,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.blueGrey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xffF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xffE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.branch,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.secondaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      alreadySubmitted
                          ? 'This branch is currently submitted. If you continue, its submit row will be deleted from order_submissions and it will return to Waiting Submission.'
                          : '',
                      style: TextStyle(
                        height: 1.35,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.blueGrey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  if (alreadySubmitted) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _submitting ? null : _deleteSubmit,
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.delete_outline_rounded),
                        label: Text(
                          _submitting ? 'Removing...' : 'Delete Submit',
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _submitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: const Color(0xff16A34A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_circle_rounded),
                        label: Text(
                          _submitting ? 'Submitting...' : 'Yes, Submit',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
