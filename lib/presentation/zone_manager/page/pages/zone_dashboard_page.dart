part of '../zone_manager_page.dart';

extension _ZoneDashboardPageView on _ZoneManagerPageState {
  Widget buildZoneDashboardPage() {
    final submittedCount = _branches
        .where(
          (branch) => _submissions.containsKey(_zdKey(branch['branch_name'])),
        )
        .length;

    final rejectedCount = _additional.where((row) {
      return _zdString(row['status']).toLowerCase().contains('reject');
    }).length;

    final pendingCount = _additional.where((row) {
      return _zdString(row['status']).toLowerCase().contains('pending');
    }).length;

    final sentToStoreCount = _additional.where((row) {
      return _zdString(row['status']).toLowerCase() == 'sent_to_store';
    }).length;

    final visibleAdditionalRows = _filtered(_additional, 'branch_name');

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1050;

        return CustomPaint(
          painter: const _ZdDotPatternPainter(),
          child: Column(
            children: [
              _ZdStatsSection(
                stats: [
                  _ZdStat(
                    icon: Icons.account_tree_outlined,
                    title: 'Zone Branches',
                    value: '${_branches.length}',
                    color: _zdPurple,
                  ),
                  _ZdStat(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'Submitted Orders',
                    value: '$submittedCount / ${_branches.length}',
                    color: _zdGreen,
                    showProgress: true,
                  ),
                  _ZdStat(
                    icon: Icons.add_box_outlined,
                    title: 'Additional Today',
                    value: '${_additional.length}',
                    color: _zdOrange,
                  ),
                  _ZdStat(
                    icon: Icons.cancel_outlined,
                    title: 'Rejected Additional',
                    value: '$rejectedCount',
                    color: _zdRed,
                  ),
                  _ZdStat(
                    icon: Icons.more_horiz_rounded,
                    title: 'Pending / Sent To Store',
                    value: '$pendingCount / $sentToStoreCount',
                    color: _zdAmber,
                    subtitle: 'Additional workflow',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: isDesktop
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: constraints.maxWidth * 0.44,
                            child: _ZdBranchGrid(
                              branches: _branches,
                              submissions: _submissions,
                              edits: _edits,
                              additional: _additional,
                              selectedBranch: _selectedBranch,
                              onOpen: _openBranch,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _ZdAdditionalPanel(
                              rows: visibleAdditionalRows,
                              onViewAll: () => _changePage(4),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(
                            flex: 5,
                            child: _ZdBranchGrid(
                              branches: _branches,
                              submissions: _submissions,
                              edits: _edits,
                              additional: _additional,
                              selectedBranch: _selectedBranch,
                              onOpen: _openBranch,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            flex: 6,
                            child: _ZdAdditionalPanel(
                              rows: visibleAdditionalRows,
                              onViewAll: () => _changePage(4),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Dashboard design tokens
// -----------------------------------------------------------------------------

const Color _zdSurface = Color(0xFFFFFFFF);
const Color _zdSurfaceSoft = Color(0xFFF4F7FB);
const Color _zdBorder = Color(0xFFD1DAE6);
const Color _zdBorderStrong = Color(0xFFAEBBCC);
const Color _zdText = Color(0xFF0B1220);
const Color _zdTextSubtle = Color(0xFF334155);
const Color _zdTextMuted = Color(0xFF64748B);

const Color _zdBlue = Color(0xFF3730A3);
const Color _zdBlueSoft = Color(0xFFEEF2FF);
const Color _zdBlueBorder = Color(0xFFA5B4FC);

const Color _zdPurple = Color(0xFF7E22CE);
const Color _zdPurpleSoft = Color(0xFFFAF5FF);
const Color _zdPurpleBorder = Color(0xFFD8B4FE);

const Color _zdGreen = Color(0xFF059669);
const Color _zdGreenDark = Color(0xFF065F46);
const Color _zdGreenSoft = Color(0xFFECFDF5);
const Color _zdGreenCard = Color(0xFFD1FAE5);
const Color _zdGreenBorder = Color(0xFF6EE7B7);

const Color _zdOrange = Color(0xFFEA580C);
const Color _zdOrangeSoft = Color(0xFFFFF7ED);
const Color _zdOrangeBorder = Color(0xFFFDBA74);

const Color _zdRed = Color(0xFFDC2626);
const Color _zdRedSoft = Color(0xFFFEF2F2);
const Color _zdRedBorder = Color(0xFFFCA5A5);

const Color _zdAmber = Color(0xFFD97706);
const Color _zdAmberSoft = Color(0xFFFFFBEB);
const Color _zdAmberBorder = Color(0xFFFCD34D);

const Color _zdCyan = Color(0xFF0E7490);
const Color _zdCyanSoft = Color(0xFFECFEFF);
const Color _zdCyanBorder = Color(0xFF67E8F9);

// -----------------------------------------------------------------------------
// Statistics
// -----------------------------------------------------------------------------

class _ZdStat {
  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final String? subtitle;
  final bool showProgress;

  const _ZdStat({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    this.subtitle,
    this.showProgress = false,
  });
}

class _ZdStatsSection extends StatelessWidget {
  final List<_ZdStat> stats;

  const _ZdStatsSection({required this.stats});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 14.0;

        if (constraints.maxWidth >= 1100) {
          return SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < stats.length; index++) ...[
                  Expanded(child: _ZdStatCard(stat: stats[index])),
                  if (index < stats.length - 1) const SizedBox(width: gap),
                ],
              ],
            ),
          );
        }

        final columns = constraints.maxWidth >= 720
            ? 3
            : constraints.maxWidth >= 480
            ? 2
            : 1;

        final cardWidth =
            (constraints.maxWidth - ((columns - 1) * gap)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final stat in stats)
              SizedBox(
                width: cardWidth,
                height: 150,
                child: _ZdStatCard(stat: stat),
              ),
          ],
        );
      },
    );
  }
}

class _ZdStatCard extends StatefulWidget {
  final _ZdStat stat;

  const _ZdStatCard({required this.stat});

  @override
  State<_ZdStatCard> createState() => _ZdStatCardState();
}

class _ZdStatCardState extends State<_ZdStatCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final stat = widget.stat;
    final parsedValue = _ZdParsedValue.parse(stat.value);

    final progress = stat.showProgress && parsedValue.denominatorValue > 0
        ? (parsedValue.mainValue / parsedValue.denominatorValue)
              .clamp(0.0, 1.0)
              .toDouble()
        : null;

    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) {
        if (!_hovered) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) {
        if (_hovered) {
          setState(() => _hovered = false);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: _zdSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hovered ? stat.color.withValues(alpha: 0.50) : _zdBorder,
            width: _hovered ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xFF0F172A,
              ).withValues(alpha: _hovered ? 0.13 : 0.065),
              blurRadius: _hovered ? 22 : 13,
              offset: Offset(0, _hovered ? 8 : 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 5, color: stat.color),
              ),
              Positioned(
                right: -24,
                bottom: -38,
                child: Container(
                  width: 105,
                  height: 105,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: stat.color.withValues(alpha: 0.05),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 15, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            stat.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _zdText,
                              fontSize: 13,
                              height: 1.15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: stat.color.withValues(
                              alpha: _hovered ? 0.16 : 0.10,
                            ),
                            border: Border.all(
                              color: stat.color.withValues(
                                alpha: _hovered ? 0.40 : 0.24,
                              ),
                            ),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(stat.icon, color: stat.color, size: 18),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Text(
                            parsedValue.mainText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _zdText,
                              fontSize: 34,
                              height: 0.95,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.8,
                            ),
                          ),
                        ),
                        if (parsedValue.denominatorText != null) ...[
                          const SizedBox(width: 5),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              parsedValue.denominatorText!,
                              style: const TextStyle(
                                color: _zdTextSubtle,
                                fontSize: 13,
                                height: 1,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (progress != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          minHeight: 7,
                          value: progress,
                          backgroundColor: const Color(0xFFDDE4ED),
                          valueColor: AlwaysStoppedAnimation<Color>(stat.color),
                        ),
                      ),
                    ] else ...[
                      Container(
                        width: 34,
                        height: 4,
                        decoration: BoxDecoration(
                          color: stat.color,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      progress != null
                          ? '${(progress * 100).round()}% COMPLETED'
                          : (stat.subtitle ?? 'LIVE ZONE OVERVIEW')
                                .toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _zdTextSubtle,
                        fontSize: 9,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZdParsedValue {
  final String mainText;
  final String? denominatorText;
  final double mainValue;
  final double denominatorValue;

  const _ZdParsedValue({
    required this.mainText,
    required this.denominatorText,
    required this.mainValue,
    required this.denominatorValue,
  });

  factory _ZdParsedValue.parse(String rawValue) {
    final parts = rawValue.split('/');
    final mainText = parts.first.trim();
    final denominatorText = parts.length > 1 ? '/ ${parts[1].trim()}' : null;

    return _ZdParsedValue(
      mainText: mainText,
      denominatorText: denominatorText,
      mainValue: double.tryParse(mainText) ?? 0,
      denominatorValue: parts.length > 1
          ? double.tryParse(parts[1].trim()) ?? 0
          : 0,
    );
  }
}

// -----------------------------------------------------------------------------
// Branches section
// -----------------------------------------------------------------------------

class _ZdBranchGrid extends StatelessWidget {
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> edits;
  final List<Map<String, dynamic>> additional;
  final Map<String, Map<String, dynamic>> submissions;
  final String selectedBranch;
  final ValueChanged<String> onOpen;

  const _ZdBranchGrid({
    required this.branches,
    required this.submissions,
    required this.edits,
    required this.additional,
    required this.selectedBranch,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final visibleBranches = branches
        .where((row) {
          final branchName = _zdString(row['branch_name']);
          return selectedBranch == 'ALL' || branchName == selectedBranch;
        })
        .toList(growable: false);

    final waitingCount = visibleBranches.where((row) {
      final branchName = _zdString(row['branch_name']);
      return !submissions.containsKey(_zdKey(branchName));
    }).length;

    return Container(
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _zdSurface,
        border: Border.all(color: _zdBorder),
        borderRadius: BorderRadius.circular(13),

        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.045),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 25,
            child: Row(
              children: [
                const Text(
                  'Branches Ordering Today',
                  style: TextStyle(
                    color: _zdText,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(width: 8),
                _ZdCountBadge(count: waitingCount),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 470 ? 2 : 1;

                if (visibleBranches.isEmpty) {
                  return const _ZdEmptyBranches();
                }

                return Scrollbar(
                  child: GridView.builder(
                    padding: const EdgeInsets.only(right: 5, bottom: 4),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 133,
                    ),
                    itemCount: visibleBranches.length,
                    itemBuilder: (context, index) {
                      final branchName = _zdString(
                        visibleBranches[index]['branch_name'],
                      );
                      final branchKey = _zdKey(branchName);
                      final submitted = submissions.containsKey(branchKey);

                      final editCount = edits.where((row) {
                        return _zdKey(row['branch_name']) == branchKey;
                      }).length;

                      final additionalCount = additional.where((row) {
                        return _zdKey(row['branch_name']) == branchKey;
                      }).length;

                      return _ZdBranchCard(
                        branch: branchName,
                        submitted: submitted,
                        editCount: editCount,
                        additionalCount: additionalCount,
                        onTap: () => onOpen(branchName),
                      );
                    },
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

class _ZdBranchCard extends StatefulWidget {
  final String branch;
  final bool submitted;
  final int editCount;
  final int additionalCount;
  final VoidCallback onTap;

  const _ZdBranchCard({
    required this.branch,
    required this.submitted,
    required this.editCount,
    required this.additionalCount,
    required this.onTap,
  });

  @override
  State<_ZdBranchCard> createState() => _ZdBranchCardState();
}

class _ZdBranchCardState extends State<_ZdBranchCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final submitted = widget.submitted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
        decoration: BoxDecoration(
          gradient: submitted
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_zdGreenSoft, _zdGreenCard],
                )
              : null,
          color: submitted ? null : _zdSurface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: submitted
                ? _zdGreenBorder
                : (_hovered ? _zdBorderStrong : _zdBorder),
          ),
          boxShadow: [
            BoxShadow(
              color: submitted
                  ? _zdGreen.withValues(alpha: _hovered ? 0.16 : 0.09)
                  : const Color(
                      0xFF0F172A,
                    ).withValues(alpha: _hovered ? 0.09 : 0.045),
              blurRadius: _hovered ? 16 : 9,
              offset: Offset(0, _hovered ? 6 : 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(11),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: submitted
                              ? const Color(0xFFCCFBF1)
                              : const Color(0xFFF1F5F9),
                          border: Border.all(
                            color: submitted ? _zdGreenBorder : _zdBorder,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          submitted
                              ? Icons.check_circle_outline_rounded
                              : Icons.storefront_outlined,
                          size: 17,
                          color: submitted ? _zdGreen : _zdTextSubtle,
                        ),
                      ),
                      const Spacer(),
                      if (widget.additionalCount > 0)
                        _ZdMiniBadge(
                          text: '${widget.additionalCount} ADD',
                          color: _zdRed,
                          background: _zdRedSoft,
                          border: _zdRedBorder,
                        ),
                      if (widget.additionalCount > 0 && widget.editCount > 0)
                        const SizedBox(width: 5),
                      if (widget.editCount > 0)
                        _ZdMiniBadge(
                          text: '${widget.editCount} EDITS',
                          color: _zdOrange,
                          background: _zdOrangeSoft,
                          border: _zdOrangeBorder,
                        ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Text(
                    widget.branch,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: submitted ? _zdGreenDark : _zdText,
                      fontSize: 14,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    submitted ? 'ORDER SUBMITTED' : 'WAITING SUBMISSION',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: submitted ? _zdGreen : _zdTextMuted,
                      fontSize: 10.5,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.45,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 11,
                        color: submitted
                            ? _zdGreen.withValues(alpha: 0.72)
                            : _zdTextMuted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Open branch overview',
                        style: TextStyle(
                          color: submitted
                              ? _zdGreen.withValues(alpha: 0.78)
                              : _zdTextMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ZdCountBadge extends StatelessWidget {
  final int count;

  const _ZdCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _zdSurfaceSoft,
        border: Border.all(color: _zdBorder),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: _zdTextSubtle,
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ZdMiniBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color background;
  final Color border;

  const _ZdMiniBadge({
    required this.text,
    required this.color,
    required this.background,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          height: 1,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.25,
        ),
      ),
    );
  }
}

class _ZdEmptyBranches extends StatelessWidget {
  const _ZdEmptyBranches();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _zdSurface,
        border: Border.all(color: _zdBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Text(
          'No branches match the current selection.',
          style: TextStyle(
            color: _zdTextMuted,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Additional requests panel
// -----------------------------------------------------------------------------

class _ZdAdditionalPanel extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final VoidCallback onViewAll;

  const _ZdAdditionalPanel({required this.rows, required this.onViewAll});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _zdSurface,
        border: Border.all(color: _zdBorder),
        borderRadius: BorderRadius.circular(13),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.045),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 16, 12),
            child: Row(
              children: [
                const Text(
                  'Zone Additional Requests',
                  style: TextStyle(
                    color: _zdText,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),

                const Spacer(),
                FilledButton(
                  onPressed: onViewAll,
                  style: FilledButton.styleFrom(
                    backgroundColor: _zdBlue,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shadowColor: _zdBlue.withValues(alpha: 0.25),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  child: const Text('View All'),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _zdBorder),
          Expanded(
            child: rows.isEmpty
                ? const _ZdEmptyAdditional()
                : Scrollbar(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(17, 14, 14, 14),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return _ZdAdditionalRequestCard(row: rows[index]);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ZdAdditionalRequestCard extends StatefulWidget {
  final Map<String, dynamic> row;

  const _ZdAdditionalRequestCard({required this.row});

  @override
  State<_ZdAdditionalRequestCard> createState() =>
      _ZdAdditionalRequestCardState();
}

class _ZdAdditionalRequestCardState extends State<_ZdAdditionalRequestCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final status = _zdString(row['status']);
    final theme = _ZdRequestTheme.fromStatus(status);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        transform: Matrix4.translationValues(0, _hovered ? -1 : 0, 0),
        decoration: BoxDecoration(
          color: _zdSurface,
          border: Border.all(color: _hovered ? _zdBorderStrong : _zdBorder),
          borderRadius: BorderRadius.circular(11),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xFF0F172A,
              ).withValues(alpha: _hovered ? 0.075 : 0.025),
              blurRadius: _hovered ? 14 : 7,
              offset: Offset(0, _hovered ? 5 : 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: theme.accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(19, 14, 14, 13),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              _zdString(row['item_code']),
                              style: const TextStyle(
                                color: _zdBlue,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _zdString(row['item_name']),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _zdText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _ZdStatusBadge(
                              text: _zdPrettyStatus(status).toUpperCase(),
                              theme: theme,
                            ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        Row(
                          children: [
                            const Icon(
                              Icons.storefront_outlined,
                              size: 11,
                              color: _zdTextMuted,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                _zdString(row['branch_name']),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _zdTextSubtle,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            _ZdRequestQtyBadge(
                              value: _zdNumberText(row['request_qty']),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          height: 58,
                          decoration: BoxDecoration(
                            color: _zdSurfaceSoft,
                            border: Border.all(color: _zdBorder),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              _ZdMetricCell(
                                label: 'BR STOCK',
                                value: row['branch_stock'],
                              ),
                              _ZdMetricCell(
                                label: 'STR STOCK',
                                value: row['store_stock'],
                              ),
                              _ZdMetricCell(
                                label: 'SALES',
                                value: row['sales_45d'],
                              ),
                              _ZdMetricCell(
                                label: 'REORDER',
                                value: row['final_reorder_qty'],
                              ),
                              _ZdMetricCell(
                                label: 'INVENT',
                                value: row['inventory_qty'],
                              ),
                              _ZdMetricCell(
                                label: 'FULFILL',
                                value: row['fulfilled_qty'],
                                isLast: true,
                              ),
                            ],
                          ),
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
    );
  }
}

class _ZdRequestTheme {
  final Color accent;
  final Color background;
  final Color border;
  final Color text;

  const _ZdRequestTheme({
    required this.accent,
    required this.background,
    required this.border,
    required this.text,
  });

  factory _ZdRequestTheme.fromStatus(String status) {
    final normalized = status.trim().toLowerCase();

    if (normalized.contains('reject')) {
      return const _ZdRequestTheme(
        accent: _zdRed,
        background: _zdRedSoft,
        border: _zdRedBorder,
        text: _zdRed,
      );
    }

    if (normalized.contains('done') ||
        normalized.contains('complete') ||
        normalized.contains('approved')) {
      return const _ZdRequestTheme(
        accent: _zdGreen,
        background: _zdGreenSoft,
        border: _zdGreenBorder,
        text: _zdGreenDark,
      );
    }

    if (normalized == 'sent_to_store' || normalized.contains('sent')) {
      return const _ZdRequestTheme(
        accent: _zdCyan,
        background: _zdCyanSoft,
        border: _zdCyanBorder,
        text: _zdCyan,
      );
    }

    return const _ZdRequestTheme(
      accent: _zdAmber,
      background: _zdAmberSoft,
      border: _zdAmberBorder,
      text: _zdAmber,
    );
  }
}

class _ZdStatusBadge extends StatelessWidget {
  final String text;
  final _ZdRequestTheme theme;

  const _ZdStatusBadge({required this.text, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: theme.background,
        border: Border.all(color: theme.border),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: theme.text,
          fontSize: 9.5,
          height: 1,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.45,
        ),
      ),
    );
  }
}

class _ZdRequestQtyBadge extends StatelessWidget {
  final String value;

  const _ZdRequestQtyBadge({required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: _zdOrangeSoft,
          border: Border.all(color: _zdOrange, width: 1.2),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: _zdOrange.withValues(alpha: 0.10),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _zdOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.shopping_cart_checkout_rounded,
                size: 15,
                color: _zdOrange,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'REQUEST QTY',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _zdOrange,
                      fontSize: 8,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _zdText,
                      fontSize: 19,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZdMetricCell extends StatelessWidget {
  final String label;
  final dynamic value;
  final bool isLast;

  const _ZdMetricCell({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: double.infinity,
        decoration: isLast
            ? null
            : const BoxDecoration(
                border: Border(right: BorderSide(color: _zdBorder)),
              ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _zdTextMuted,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _zdNumberText(value),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _zdTextSubtle,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZdEmptyAdditional extends StatelessWidget {
  const _ZdEmptyAdditional();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 35, color: _zdTextMuted),
          SizedBox(height: 10),
          Text(
            'No additional requests found.',
            style: TextStyle(
              color: _zdTextMuted,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Background painter
// -----------------------------------------------------------------------------

class _ZdDotPatternPainter extends CustomPainter {
  const _ZdDotPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF94A3B8).withValues(alpha: 0.34)
      ..style = PaintingStyle.fill;

    const spacing = 18.0;
    const radius = 0.75;

    for (double y = 5; y < size.height; y += spacing) {
      for (double x = 5; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ZdDotPatternPainter oldDelegate) => false;
}

// -----------------------------------------------------------------------------
// Local helpers
// -----------------------------------------------------------------------------

String _zdString(dynamic value) => (value ?? '').toString().trim();

String _zdKey(dynamic value) {
  return _zdString(value).replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}

String _zdNumberText(dynamic value) {
  if (value == null || _zdString(value).isEmpty) return '0';

  final number = value is num ? value : num.tryParse(_zdString(value));
  if (number == null) return _zdString(value);

  if (number == number.roundToDouble()) {
    return number.toInt().toString();
  }

  return number.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

String _zdPrettyStatus(String value) {
  final words = value
      .replaceAll('_', ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty);

  if (words.isEmpty) return 'Pending';

  return words
      .map(
        (word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}
