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
  final Map<String, int> additionalTodayBranchCount;
  final String runDate;
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
      ..sort((firstBranch, secondBranch) {
        final firstSubmitted = submittedSet.contains(_branchKey(firstBranch));

        final secondSubmitted = submittedSet.contains(_branchKey(secondBranch));

        if (firstSubmitted != secondSubmitted) {
          return firstSubmitted ? -1 : 1;
        }

        if (firstSubmitted && secondSubmitted) {
          final firstTime = _submittedAtFor(firstBranch);
          final secondTime = _submittedAtFor(secondBranch);

          if (firstTime != null && secondTime != null) {
            return firstTime.compareTo(secondTime);
          }

          if (firstTime != null) return -1;
          if (secondTime != null) return 1;
        }

        return branches
            .indexOf(firstBranch)
            .compareTo(branches.indexOf(secondBranch));
      });

    final submittedCount = sortedBranches.where((branch) {
      return submittedSet.contains(_branchKey(branch));
    }).length;

    final waitingCount = sortedBranches.length - submittedCount;

    return Container(
      margin: const EdgeInsets.only(left: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF4F9FC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCEAF2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          _GridHeader(
            totalCount: sortedBranches.length,
            submittedCount: submittedCount,
            waitingCount: waitingCount,
          ),
          Expanded(
            child: sortedBranches.isEmpty
                ? const _NoBranchesToday()
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = constraints.maxWidth < 400 ? 1 : 2;

                      return GridView.builder(
                        clipBehavior: Clip.none,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          mainAxisExtent: 142,
                        ),
                        itemCount: sortedBranches.length,
                        itemBuilder: (context, index) {
                          final branch = sortedBranches[index];

                          final branchKey = _branchKey(branch);

                          final isSubmitted = submittedSet.contains(branchKey);

                          final isSelected =
                              selectedBranch != null &&
                              _branchKey(selectedBranch!) == branchKey;

                          final edits = _lookupInt(editsCount, branch) ?? 0;

                          final additionalToday =
                              _lookupInt(additionalTodayBranchCount, branch) ??
                              0;

                          final endHour =
                              _lookupInt(submitEndHours, branch) ?? 24;

                          final submittedAt = _submittedAtFor(branch);

                          return _AnimatedBranchCard(
                            key: ValueKey(branchKey),
                            branch: branch,
                            isSubmitted: isSubmitted,
                            isSelected: isSelected,
                            editsCount: edits,
                            additionalCount: additionalToday,
                            deadlineHour: endHour,
                            submittedTime: submittedAt == null
                                ? null
                                : _formatSubmittedTime(submittedAt),
                            onTap: () {
                              _showBranchDialog(
                                context: context,
                                branch: branch,
                                isSubmitted: isSubmitted,
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showBranchDialog({
    required BuildContext context,
    required String branch,
    required bool isSubmitted,
  }) async {
    final inventoryBloc = context.read<InventoryBloc>();

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Branch order confirmation',
      barrierColor: Colors.black.withValues(alpha: 0.48),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return BlocProvider.value(
          value: inventoryBloc,
          child: _SubmitBranchDialog(
            branch: branch,
            runDate: runDate,
            isSubmitted: isSubmitted,
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: curvedAnimation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.93, end: 1).animate(curvedAnimation),
            child: child,
          ),
        );
      },
    );
  }

  String _branchKey(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  DateTime? _submittedAtFor(String branch) {
    final exactValue = submittedBranchTimes[branch];

    if (exactValue != null) {
      return exactValue;
    }

    final key = _branchKey(branch);

    for (final entry in submittedBranchTimes.entries) {
      if (_branchKey(entry.key) == key) {
        return entry.value;
      }
    }

    return null;
  }

  int? _lookupInt(Map<String, int> map, String branch) {
    final exactValue = map[branch];

    if (exactValue != null) {
      return exactValue;
    }

    final key = _branchKey(branch);

    for (final entry in map.entries) {
      if (_branchKey(entry.key) == key) {
        return entry.value;
      }
    }

    return null;
  }

  String _formatSubmittedTime(DateTime value) {
    final localTime = value.toLocal();
    final hour = localTime.hour;
    final minute = localTime.minute.toString().padLeft(2, '0');

    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;

    return '$displayHour:$minute $period';
  }
}

class _GridHeader extends StatelessWidget {
  final int totalCount;
  final int submittedCount;
  final int waitingCount;

  const _GridHeader({
    required this.totalCount,
    required this.submittedCount,
    required this.waitingCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 13),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE9F6FC), Color(0xFFF8FCFE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              _HeaderIcon(),
              SizedBox(width: 11),
              Expanded(
                child: Text(
                  'Branches Ordering Today',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.secondaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _HeaderCounter(
                label: 'Total',
                value: totalCount,
                color: AppColors.primaryColor,
              ),
              const SizedBox(width: 8),
              _HeaderCounter(
                label: 'Submitted',
                value: submittedCount,
                color: const Color(0xFF10B981),
              ),
              const SizedBox(width: 8),
              _HeaderCounter(
                label: 'Waiting',
                value: waitingCount,
                color: const Color(0xFFF59E0B),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 39,
      height: 39,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primaryColor.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.storefront_rounded,
        size: 21,
        color: AppColors.primaryColor,
      ),
    );
  }
}

class _HeaderCounter extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _HeaderCounter({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withValues(alpha: 0.13)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '$label $value',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedBranchCard extends StatefulWidget {
  final String branch;
  final bool isSubmitted;
  final bool isSelected;
  final int editsCount;
  final int additionalCount;
  final int deadlineHour;
  final String? submittedTime;
  final VoidCallback onTap;

  const _AnimatedBranchCard({
    super.key,
    required this.branch,
    required this.isSubmitted,
    required this.isSelected,
    required this.editsCount,
    required this.additionalCount,
    required this.deadlineHour,
    required this.submittedTime,
    required this.onTap,
  });

  @override
  State<_AnimatedBranchCard> createState() {
    return _AnimatedBranchCardState();
  }
}

class _AnimatedBranchCardState extends State<_AnimatedBranchCard> {
  bool _isHovered = false;

  Color get _accentColor {
    if (widget.isSelected) {
      return Colors.white;
    }

    if (widget.isSubmitted) {
      return const Color(0xFF10B981);
    }

    return const Color(0xFFF59E0B);
  }

  void _changeHover(bool value) {
    if (_isHovered == value) {
      return;
    }

    setState(() {
      _isHovered = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _changeHover(true),
      onExit: (_) => _changeHover(false),
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 230),
        curve: Curves.easeOutCubic,
        offset: _isHovered ? const Offset(0, -0.035) : Offset.zero,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 230),
          curve: Curves.easeOutCubic,
          scale: _isHovered ? 1.018 : 1,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(17),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 230),
                curve: Curves.easeOutCubic,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  gradient: _cardGradient(),
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                    color: _borderColor(),
                    width: _isHovered ? 1.4 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _shadowColor(),
                      blurRadius: _isHovered ? 24 : 12,
                      spreadRadius: _isHovered ? 1 : 0,
                      offset: Offset(0, _isHovered ? 10 : 5),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    _BackgroundDecoration(
                      color: _accentColor,
                      isHovered: _isHovered,
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 230),
                        width: _isHovered ? 5 : 4,
                        decoration: BoxDecoration(
                          color: _accentColor,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 13, 13, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _StatusIcon(
                                  isSubmitted: widget.isSubmitted,
                                  isSelected: widget.isSelected,
                                  isHovered: _isHovered,
                                ),
                                const Spacer(),
                                if (widget.additionalCount > 0)
                                  _CardBadge(
                                    icon: Icons.add_rounded,
                                    text: '${widget.additionalCount} req',
                                    color: const Color(0xFFF43F5E),
                                    isSelected: widget.isSelected,
                                  ),
                                if (widget.additionalCount > 0 &&
                                    widget.editsCount > 0)
                                  const SizedBox(width: 5),
                                if (widget.editsCount > 0)
                                  _CardBadge(
                                    icon: Icons.edit_rounded,
                                    text: '${widget.editsCount} edits',
                                    color: const Color(0xFFFF8A24),
                                    isSelected: widget.isSelected,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              widget.branch,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w900,
                                color: widget.isSelected
                                    ? Colors.white
                                    : AppColors.secondaryColor,
                              ),
                            ),
                            const SizedBox(height: 5),
                            _StatusLabel(
                              isSubmitted: widget.isSubmitted,
                              isSelected: widget.isSelected,
                              submittedTime: widget.submittedTime,
                            ),
                            const Spacer(),
                            _DeadlinePill(
                              hour: widget.deadlineHour,
                              isSelected: widget.isSelected,
                              isSubmitted: widget.isSubmitted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  LinearGradient _cardGradient() {
    if (widget.isSelected) {
      return const LinearGradient(
        colors: [Color(0xFF4A74F5), Color(0xFF3155D9)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }

    if (widget.isSubmitted) {
      return LinearGradient(
        colors: [
          Colors.white,
          const Color(0xFFECFDF5).withValues(alpha: _isHovered ? 1 : 0.82),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }

    return LinearGradient(
      colors: [
        Colors.white,
        const Color(0xFFFFFBEB).withValues(alpha: _isHovered ? 1 : 0.75),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  Color _borderColor() {
    if (widget.isSelected) {
      return const Color(0xFF3155D9);
    }

    return _accentColor.withValues(alpha: _isHovered ? 0.42 : 0.18);
  }

  Color _shadowColor() {
    if (widget.isSelected) {
      return const Color(
        0xFF3155D9,
      ).withValues(alpha: _isHovered ? 0.28 : 0.15);
    }

    return _accentColor.withValues(alpha: _isHovered ? 0.20 : 0.08);
  }
}

class _BackgroundDecoration extends StatelessWidget {
  final Color color;
  final bool isHovered;

  const _BackgroundDecoration({required this.color, required this.isHovered});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          right: isHovered ? -23 : -32,
          bottom: isHovered ? -38 : -45,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: isHovered ? 105 : 92,
            height: isHovered ? 105 : 92,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isHovered ? 0.10 : 0.06),
              shape: BoxShape.circle,
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 340),
          curve: Curves.easeOutCubic,
          right: isHovered ? 56 : 49,
          bottom: isHovered ? 15 : 10,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusIcon extends StatelessWidget {
  final bool isSubmitted;
  final bool isSelected;
  final bool isHovered;

  const _StatusIcon({
    required this.isSubmitted,
    required this.isSelected,
    required this.isHovered,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected
        ? Colors.white
        : isSubmitted
        ? const Color(0xFF10B981)
        : const Color(0xFFF59E0B);

    return AnimatedScale(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutBack,
      scale: isHovered ? 1.10 : 1,
      child: AnimatedRotation(
        duration: const Duration(milliseconds: 240),
        turns: isHovered ? 0.025 : 0,
        child: Container(
          width: 31,
          height: 31,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.18)
                : color.withValues(alpha: 0.11),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.20)
                  : color.withValues(alpha: 0.16),
            ),
          ),
          child: Icon(
            isSubmitted ? Icons.check_rounded : Icons.storefront_rounded,
            color: color,
            size: 18,
          ),
        ),
      ),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  final bool isSubmitted;
  final bool isSelected;
  final String? submittedTime;

  const _StatusLabel({
    required this.isSubmitted,
    required this.isSelected,
    required this.submittedTime,
  });

  @override
  Widget build(BuildContext context) {
    final label = isSubmitted
        ? submittedTime == null
              ? 'Order submitted'
              : 'Submitted at $submittedTime'
        : 'Waiting for submission';

    final color = isSelected
        ? Colors.white.withValues(alpha: 0.78)
        : isSubmitted
        ? const Color(0xFF059669)
        : const Color(0xFFB45309);

    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _CardBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final bool isSelected;

  const _CardBadge({
    required this.icon,
    required this.text,
    required this.color,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white.withValues(alpha: 0.18) : color,
        borderRadius: BorderRadius.circular(999),
        border: isSelected
            ? Border.all(color: Colors.white.withValues(alpha: 0.18))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: Colors.white),
          const SizedBox(width: 3),
          Text(
            text,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoBranchesToday extends StatelessWidget {
  const _NoBranchesToday();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(18),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFDCEAF2)),
          boxShadow: [
            BoxShadow(
              blurRadius: 18,
              offset: const Offset(0, 8),
              color: Colors.black.withValues(alpha: 0.05),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.event_available_rounded,
                color: AppColors.primaryColor,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No Branches Ordering Today',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.secondaryColor,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'No active branches are scheduled to place an order on this date.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
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
  State<_SubmitBranchDialog> createState() {
    return _SubmitBranchDialogState();
  }
}

class _SubmitBranchDialogState extends State<_SubmitBranchDialog> {
  bool _submitting = false;

  bool get _alreadySubmitted => widget.isSubmitted;

  Color get _actionColor {
    return _alreadySubmitted
        ? const Color(0xFFF43F5E)
        : const Color(0xFF10B981);
  }

  Future<void> _waitForBranchAction(InventoryBloc bloc) {
    return bloc.stream.firstWhere((state) {
      return !state.isBulkLoading &&
          (state.bulkMessage ?? '').contains(widget.branch);
    });
  }

  Future<void> _executeAction() async {
    if (_submitting) {
      return;
    }

    setState(() {
      _submitting = true;
    });

    final bloc = context.read<InventoryBloc>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      if (_alreadySubmitted) {
        bloc.add(DeleteBranchSubmissionFromInventory(widget.branch));
      } else {
        bloc.add(SubmitBranchFromInventory(widget.branch));
      }

      await _waitForBranchAction(bloc);

      if (!mounted) {
        return;
      }

      final result = bloc.state;
      final success = result.bulkSuccess == true;

      final fallbackMessage = success
          ? _alreadySubmitted
                ? 'The branch submission was reopened successfully.'
                : 'The branch order was submitted successfully.'
          : _alreadySubmitted
          ? 'The branch submission could not be reopened.'
          : 'The branch order could not be submitted.';

      final responseMessage = (result.bulkMessage ?? '').trim();

      Navigator.of(context).pop();

      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          backgroundColor: success
              ? const Color(0xFF059669)
              : const Color(0xFFDC2626),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          margin: const EdgeInsets.all(18),
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
                  responseMessage.isNotEmpty
                      ? responseMessage
                      : fallbackMessage,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _submitting = false;
      });

      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFDC2626),
          content: Text(
            _alreadySubmitted
                ? 'An error occurred while reopening the submission.'
                : 'An error occurred while submitting the order.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _alreadySubmitted
        ? 'Reopen Branch Submission?'
        : 'Submit Branch Order?';

    final subtitle = _alreadySubmitted
        ? 'Return this branch to Waiting Submission'
        : 'Confirm this branch order is complete';

    final message = _alreadySubmitted
        ? 'Reopening this submission will remove the current submission status and return the branch to Waiting Submission. Use this only when the order needs to be reviewed or submitted again.'
        : 'Confirm that this branch has completed its order for the selected date. Once submitted, it will be marked as Submitted and included in the submission tracker.';

    final cancelText = _alreadySubmitted ? 'Keep Submitted' : 'Review Again';

    final actionText = _alreadySubmitted ? 'Reopen Submission' : 'Submit Order';

    return PopScope(
      canPop: !_submitting,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  blurRadius: 40,
                  spreadRadius: 2,
                  offset: const Offset(0, 18),
                  color: Colors.black.withValues(alpha: 0.18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(height: 5, color: _actionColor),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DialogIcon(
                            isSubmitted: _alreadySubmitted,
                            color: _actionColor,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.secondaryColor,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blueGrey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: _submitting
                                ? null
                                : () {
                                    Navigator.of(context).pop();
                                  },
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 21),
                      _BranchDialogInformation(
                        branch: widget.branch,
                        runDate: widget.runDate,
                        isSubmitted: _alreadySubmitted,
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: _actionColor.withValues(alpha: 0.065),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(
                            color: _actionColor.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _alreadySubmitted
                                  ? Icons.warning_amber_rounded
                                  : Icons.info_outline_rounded,
                              size: 20,
                              color: _actionColor,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                message,
                                style: TextStyle(
                                  height: 1.45,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blueGrey.shade700,
                                ),
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
                                  : () {
                                      Navigator.of(context).pop();
                                    },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.secondaryColor,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                side: const BorderSide(
                                  color: Color(0xFFCBD5E1),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                cancelText,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _submitting ? null : _executeAction,
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: _actionColor,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: _actionColor
                                    .withValues(alpha: 0.65),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
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
                                  : Icon(
                                      _alreadySubmitted
                                          ? Icons.restart_alt_rounded
                                          : Icons.check_circle_rounded,
                                      size: 19,
                                    ),
                              label: Text(
                                _submitting
                                    ? _alreadySubmitted
                                          ? 'Reopening...'
                                          : 'Submitting...'
                                    : actionText,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogIcon extends StatelessWidget {
  final bool isSubmitted;
  final Color color;

  const _DialogIcon({required this.isSubmitted, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Icon(
        isSubmitted
            ? Icons.restart_alt_rounded
            : Icons.assignment_turned_in_rounded,
        color: color,
        size: 25,
      ),
    );
  }
}

class _BranchDialogInformation extends StatelessWidget {
  final String branch;
  final String runDate;
  final bool isSubmitted;

  const _BranchDialogInformation({
    required this.branch,
    required this.runDate,
    required this.isSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = isSubmitted
        ? const Color(0xFF10B981)
        : const Color(0xFFF59E0B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            branch,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppColors.secondaryColor,
            ),
          ),
          const SizedBox(height: 11),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InformationPill(
                icon: Icons.calendar_today_rounded,
                text: runDate,
                color: AppColors.primaryColor,
              ),
              _InformationPill(
                icon: isSubmitted
                    ? Icons.check_circle_rounded
                    : Icons.schedule_rounded,
                text: isSubmitted
                    ? 'Currently Submitted'
                    : 'Waiting Submission',
                color: statusColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InformationPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _InformationPill({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.13)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: color,
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
        ? const Color(0xFF047857)
        : const Color(0xFF92400E);

    final backgroundColor = isSelected
        ? Colors.white.withValues(alpha: 0.17)
        : isSubmitted
        ? const Color(0xFFD1FAE5)
        : const Color(0xFFFEF3C7);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.20)
              : textColor.withValues(alpha: 0.10),
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
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatHour(int hour) {
    if (hour >= 24) {
      return '12:00 AM';
    }

    final normalizedHour = hour.clamp(0, 23);
    final period = normalizedHour >= 12 ? 'PM' : 'AM';

    final displayHour = normalizedHour % 12 == 0 ? 12 : normalizedHour % 12;

    return '$displayHour:00 $period';
  }
}
