part of '../zone_manager_page.dart';

extension _ZoneDashboardPageView on _ZoneManagerPageState {
  Future<void> _openDashboardStockCheck(String batchId) async {
    _search.clear();
    // The extension is scoped to the owning State and performs its navigation.
    // ignore: invalid_use_of_protected_member
    setState(() {
      _query = '';
      _selectedBranch = 'ALL';
      _selectedStockCheckBatchId = batchId;
      _page = 6;
    });
    final hasProject = _stockChecks.any((task) => task.batchId == batchId);
    if (!hasProject) await _loadStockChecks();
  }

  Widget buildZoneDashboardPage() {
    final orderingBranches = _branches
        .where(
          (branch) => _submissions.containsKey(_zdKey(branch['branch_name'])),
        )
        .toList(growable: false);
    final visibleOrderingBranches = orderingBranches
        .where((branch) {
          final branchName = _zdString(branch['branch_name']);
          return _selectedBranch == 'ALL' || branchName == _selectedBranch;
        })
        .toList(growable: false);
    final submittedCount = visibleOrderingBranches.length;

    final branchAdditionalRows = _additional
        .where((row) {
          final branchName = _zdString(row['branch_name']);
          return _selectedBranch == 'ALL' || branchName == _selectedBranch;
        })
        .toList(growable: false);

    final rejectedCount = branchAdditionalRows.where((row) {
      return _zdString(row['status']).toLowerCase().contains('reject');
    }).length;

    final pendingCount = branchAdditionalRows.where((row) {
      return _zdString(row['status']).toLowerCase().contains('pending');
    }).length;

    final sentToStoreCount = branchAdditionalRows.where((row) {
      return _zdString(row['status']).toLowerCase() == 'sent_to_store';
    }).length;

    final normalizedQuery = _query.trim().toLowerCase();
    final zoneAdditionalRows = _additional
        .where((row) {
          final branchName = _zdString(row['branch_name']);
          if (_selectedBranch != 'ALL' && branchName != _selectedBranch) {
            return false;
          }
          if (normalizedQuery.isEmpty) return true;
          return [
            row['branch_name'],
            row['item_code'],
            row['item_name'],
            row['status'],
          ].join(' ').toLowerCase().contains(normalizedQuery);
        })
        .toList(growable: false);
    final visibleActivities = _liveActivities
        .where((activity) {
          final matchesBranch =
              _selectedBranch == 'ALL' ||
              activity.branchName == _selectedBranch;
          return matchesBranch && activity.matches(_query);
        })
        .toList(growable: false);
    final stockCheckAlerts = _ZdStockCheckAlert.fromTasks(
      _dashboardStockChecks,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1050;
        final desktopPanelsHeight = constraints.maxHeight
            .clamp(620.0, 780.0)
            .toDouble();

        return CustomPaint(
          painter: const _ZdDotPatternPainter(),
          child: SingleChildScrollView(
            primary: false,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(right: 4, bottom: 8),
            child: Column(
              children: [
                _ZdStatsSection(
                  stats: [
                    _ZdStat(
                      icon: Icons.account_tree_outlined,
                      title: 'Zone Branches',
                      value: '$submittedCount',
                      color: _zdPurple,
                      subtitle: 'Branches ordered today',
                    ),
                    _ZdStat(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'Submitted Orders',
                      value: '$submittedCount / $submittedCount',
                      color: _zdGreen,
                      showProgress: true,
                    ),
                    _ZdStat(
                      icon: Icons.add_box_outlined,
                      title: 'Additional Today',
                      value: '${branchAdditionalRows.length}',
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
                if (stockCheckAlerts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ZdStockCheckAlertStrip(
                    alerts: stockCheckAlerts,
                    onOpen: _openDashboardStockCheck,
                  ),
                ],
                const SizedBox(height: 12),
                _ZoneTableToolbar(
                  controller: _search,
                  onChanged: _onSearchChanged,
                  accent: AppColors.primaryColor,
                  resultCount:
                      submittedCount +
                      zoneAdditionalRows.length +
                      visibleActivities.length,
                  hintText:
                      'Search branches, live activity, requests, item codes, or items…',
                ),
                const SizedBox(height: 12),
                if (isDesktop)
                  SizedBox(
                    height: desktopPanelsHeight,
                    child: Row(
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
                            query: _query,
                            onOpen: _openBranch,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _ZdLiveActivityPanel(
                            additionalRows: zoneAdditionalRows,
                            activities: visibleActivities,
                            connected: _liveActivityConnected,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Column(
                    children: [
                      SizedBox(
                        height: 610,
                        child: _ZdBranchGrid(
                          branches: _branches,
                          submissions: _submissions,
                          edits: _edits,
                          additional: _additional,
                          selectedBranch: _selectedBranch,
                          query: _query,
                          onOpen: _openBranch,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 760,
                        child: _ZdLiveActivityPanel(
                          additionalRows: zoneAdditionalRows,
                          activities: visibleActivities,
                          connected: _liveActivityConnected,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
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

const Color _zdPurple = Color(0xFF7E22CE);

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
// Pending Stock Check alert
// -----------------------------------------------------------------------------

class _ZdStockCheckAlert {
  final String batchId;
  final String title;
  final List<_ZdStockCheckBranchAlert> branches;

  const _ZdStockCheckAlert({
    required this.batchId,
    required this.title,
    required this.branches,
  });

  int get pending => branches.fold(0, (sum, branch) => sum + branch.pending);
  bool get isDanger => branches.any((branch) => branch.isDanger);
  bool get isExpired => branches.any((branch) => branch.isExpired);

  static List<_ZdStockCheckAlert> fromTasks(List<StockCheckTask> tasks) {
    final batches = <String, List<StockCheckTask>>{};
    for (final task in tasks) {
      if (!task.isPending || task.branchName.trim().isEmpty) continue;
      final batchKey = task.batchId.trim().isNotEmpty
          ? task.batchId.trim()
          : '${task.title}|${task.sentAt?.toIso8601String() ?? ''}';
      batches.putIfAbsent(batchKey, () => <StockCheckTask>[]).add(task);
    }

    final alerts = <_ZdStockCheckAlert>[];
    for (final entry in batches.entries) {
      final branchTasks = <String, List<StockCheckTask>>{};
      for (final task in entry.value) {
        branchTasks
            .putIfAbsent(task.branchName.trim(), () => <StockCheckTask>[])
            .add(task);
      }
      final branches =
          branchTasks.entries
              .map((branchEntry) {
                DateTime? sentAt;
                DateTime? expiresAt;
                for (final task in branchEntry.value) {
                  final taskSent = task.sentAt?.toLocal();
                  final taskExpiry = task.expiresAt?.toLocal();
                  if (taskSent != null &&
                      (sentAt == null || taskSent.isBefore(sentAt))) {
                    sentAt = taskSent;
                  }
                  if (taskExpiry != null &&
                      (expiresAt == null || taskExpiry.isBefore(expiresAt))) {
                    expiresAt = taskExpiry;
                  }
                }
                return _ZdStockCheckBranchAlert(
                  branchName: branchEntry.key,
                  pending: branchEntry.value.length,
                  sentAt: sentAt,
                  expiresAt: expiresAt,
                );
              })
              .toList(growable: false)
            ..sort((left, right) {
              if (left.isDanger != right.isDanger) {
                return left.isDanger ? -1 : 1;
              }
              final byExpiry = (left.expiresAt ?? DateTime(9999)).compareTo(
                right.expiresAt ?? DateTime(9999),
              );
              if (byExpiry != 0) return byExpiry;
              return left.branchName.toLowerCase().compareTo(
                right.branchName.toLowerCase(),
              );
            });
      if (branches.isEmpty) continue;
      alerts.add(
        _ZdStockCheckAlert(
          batchId: entry.key,
          title: entry.value.first.title.trim().isEmpty
              ? 'Stock Check'
              : entry.value.first.title.trim(),
          branches: branches,
        ),
      );
    }
    alerts.sort((left, right) {
      if (left.isDanger != right.isDanger) return left.isDanger ? -1 : 1;
      final leftExpiry = left.branches
          .map((branch) => branch.expiresAt)
          .whereType<DateTime>()
          .fold<DateTime?>(
            null,
            (value, date) =>
                value == null || date.isBefore(value) ? date : value,
          );
      final rightExpiry = right.branches
          .map((branch) => branch.expiresAt)
          .whereType<DateTime>()
          .fold<DateTime?>(
            null,
            (value, date) =>
                value == null || date.isBefore(value) ? date : value,
          );
      return (leftExpiry ?? DateTime(9999)).compareTo(
        rightExpiry ?? DateTime(9999),
      );
    });
    return alerts;
  }
}

class _ZdStockCheckBranchAlert {
  final String branchName;
  final int pending;
  final DateTime? sentAt;
  final DateTime? expiresAt;

  const _ZdStockCheckBranchAlert({
    required this.branchName,
    required this.pending,
    required this.sentAt,
    required this.expiresAt,
  });

  bool get isExpired =>
      expiresAt != null && !DateTime.now().isBefore(expiresAt!);

  double get elapsedFraction {
    if (sentAt == null || expiresAt == null) return 0;
    final total = expiresAt!.difference(sentAt!).inSeconds;
    if (total <= 0) return 1;
    final elapsed = DateTime.now().difference(sentAt!).inSeconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  bool get isDanger => elapsedFraction >= .5;

  String get timeLabel {
    if (expiresAt == null) return 'No deadline';
    final remaining = expiresAt!.difference(DateTime.now());
    if (remaining.isNegative || remaining == Duration.zero) return 'Expired';
    final days = remaining.inDays;
    final hours = remaining.inHours.remainder(24);
    final minutes = remaining.inMinutes.remainder(60);
    if (days > 0) return '${days}d ${hours}h left';
    if (remaining.inHours > 0) return '${remaining.inHours}h ${minutes}m left';
    return '${remaining.inMinutes.clamp(1, 59)}m left';
  }
}

class _ZdStockCheckAlertStrip extends StatefulWidget {
  final List<_ZdStockCheckAlert> alerts;
  final ValueChanged<String> onOpen;

  const _ZdStockCheckAlertStrip({required this.alerts, required this.onOpen});

  @override
  State<_ZdStockCheckAlertStrip> createState() =>
      _ZdStockCheckAlertStripState();
}

class _ZdStockCheckAlertStripState extends State<_ZdStockCheckAlertStrip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  bool get _hasDanger => widget.alerts.any((alert) => alert.isDanger);

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
      lowerBound: 0,
      upperBound: 1,
    );
    if (_hasDanger) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _ZdStockCheckAlertStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hasDanger && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!_hasDanger && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final multiple = widget.alerts.length > 1;
        final cardWidth = multiple
            ? (constraints.maxWidth < 650
                  ? constraints.maxWidth * .92
                  : (constraints.maxWidth * .72).clamp(560.0, 780.0))
            : constraints.maxWidth;
        return SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: multiple
                ? const BouncingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemCount: widget.alerts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) => SizedBox(
              width: cardWidth.toDouble(),
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => _ZdStockCheckAlertCard(
                  alert: widget.alerts[index],
                  pulse: widget.alerts[index].isDanger ? _pulse.value : 0,
                  onTap: () => widget.onOpen(widget.alerts[index].batchId),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ZdStockCheckAlertCard extends StatelessWidget {
  final _ZdStockCheckAlert alert;
  final double pulse;
  final VoidCallback onTap;

  const _ZdStockCheckAlertCard({
    required this.alert,
    required this.pulse,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final danger = alert.isDanger;
    final accent = danger ? const Color(0xFFDC2626) : const Color(0xFF0284C7);
    final background = danger
        ? const Color(0xFFFFF1F2)
        : const Color(0xFFF0F9FF);
    final border = danger ? const Color(0xFFFB7185) : const Color(0xFF7DD3FC);
    final decoration = BoxDecoration(
      gradient: LinearGradient(
        colors: [background, Colors.white],
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      ),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: border, width: danger ? 1.5 : 1),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: danger ? .10 + pulse * .16 : .08),
          blurRadius: danger ? 12 + pulse * 12 : 14,
          spreadRadius: danger ? pulse * 2 : 0,
          offset: const Offset(0, 5),
        ),
      ],
    );
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          hoverColor: accent.withValues(alpha: .045),
          splashColor: accent.withValues(alpha: .10),
          child: Ink(
            decoration: decoration,
            child: Row(
              children: [
                Container(width: 5, color: accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(
                                danger
                                    ? Icons.notification_important_rounded
                                    : Icons.fact_check_outlined,
                                color: accent,
                                size: 21,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    alert.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _zdText,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    danger
                                        ? 'Urgent: more than half of the allowed time has passed'
                                        : 'Stock Check is waiting for branch completion',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: danger ? accent : _zdTextMuted,
                                      fontSize: 11.5,
                                      fontWeight: danger
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            _ZdStockCheckSummaryBadge(
                              icon: Icons.storefront_rounded,
                              text: '${alert.branches.length} pending',
                              color: accent,
                            ),
                            const SizedBox(width: 7),
                            _ZdStockCheckSummaryBadge(
                              icon: Icons.inventory_2_outlined,
                              text: '${alert.pending} items',
                              color: accent,
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Open Stock Check project',
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: .10),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.arrow_forward_rounded,
                                  color: accent,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Expanded(
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: alert.branches.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) =>
                                _ZdStockCheckBranchChip(
                                  branch: alert.branches[index],
                                ),
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

class _ZdStockCheckSummaryBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _ZdStockCheckSummaryBadge({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ZdStockCheckBranchChip extends StatelessWidget {
  final _ZdStockCheckBranchAlert branch;

  const _ZdStockCheckBranchChip({required this.branch});

  @override
  Widget build(BuildContext context) {
    final danger = branch.isDanger;
    final color = danger ? const Color(0xFFDC2626) : const Color(0xFF0369A1);
    return Container(
      constraints: const BoxConstraints(minWidth: 245),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: danger ? const Color(0xFFFFE4E6) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: danger ? const Color(0xFFFDA4AF) : const Color(0xFFBAE6FD),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            danger ? Icons.timer_off_outlined : Icons.timer_outlined,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    branch.branchName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _zdText,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Container(
                  width: 1,
                  height: 16,
                  color: color.withValues(alpha: .22),
                ),
                const SizedBox(width: 7),
                Text(
                  '${branch.pending} pending',
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '• ${branch.timeLabel}',
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Live zone activity
// -----------------------------------------------------------------------------

class _ZoneLiveActivity {
  final String source;
  final String branchName;
  final String itemCode;
  final String itemName;
  final String title;
  final String detail;
  final DateTime occurredAt;
  final bool isDelete;
  final Map<String, dynamic> data;

  const _ZoneLiveActivity({
    required this.source,
    required this.branchName,
    required this.itemCode,
    required this.itemName,
    required this.title,
    required this.detail,
    required this.occurredAt,
    required this.data,
    this.isDelete = false,
  });

  factory _ZoneLiveActivity.fromRecord(
    String source,
    Map<String, dynamic> row, {
    DateTime? occurredAt,
    bool isDelete = false,
  }) {
    final branch = _zdString(row['branch_name']);
    final itemCode = _zdString(row['item_code']);
    final itemName = _zdString(row['item_name']);
    final timestamp =
        occurredAt ??
        DateTime.tryParse(
          _zdString(
            row[source == 'mismatch' ? 'update_date' : 'created_at'] ??
                row['update_date'] ??
                row['created_at'],
          ),
        ) ??
        DateTime(1970);

    String title;
    String detail;
    switch (source) {
      case 'max':
        title = isDelete ? 'Max adjustment removed' : 'Max adjustment changed';
        final maxValue = _zdNumberText(row['max_adjustment_30d'] ?? row['qty']);
        final type = _zdPrettyStatus(_zdString(row['adjustment_type']));
        detail = 'New max: $maxValue${type.isEmpty ? '' : ' • $type'}';
      case 'mismatch':
        title = isDelete ? 'Mismatch removed' : 'Stock mismatch updated';
        detail =
            'System ${_zdNumberText(row['system_stock'])} → Actual ${_zdNumberText(row['actual_stock'])} • Diff ${_zdNumberText(row['diff'])}';
      case 'edit':
        title = isDelete ? 'Order edit removed' : 'Daily order quantity edited';
        detail =
            '${_zdNumberText(row['old_qty'])} → ${_zdNumberText(row['new_qty'])} • Difference ${_zdNumberText(row['diff'])}';
      default:
        title = isDelete
            ? 'Additional request removed'
            : 'Additional order updated';
        final status = _zdPrettyStatus(_zdString(row['status']));
        detail =
            'Requested ${_zdNumberText(row['request_qty'])} • ${status.isEmpty ? 'Created' : status}';
    }

    return _ZoneLiveActivity(
      source: source,
      branchName: branch,
      itemCode: itemCode,
      itemName: itemName,
      title: title,
      detail: detail,
      occurredAt: timestamp,
      data: Map<String, dynamic>.unmodifiable(row),
      isDelete: isDelete,
    );
  }

  int get pageIndex => switch (source) {
    'mismatch' => 1,
    'max' => 2,
    'additional' => 4,
    _ => 5,
  };

  String get category => switch (source) {
    'mismatch' => 'MISMATCH',
    'max' => 'MAX',
    'additional' => 'ADDITIONAL',
    _ => 'ORDER EDIT',
  };

  IconData get icon => switch (source) {
    'mismatch' => Icons.warning_amber_rounded,
    'max' => Icons.trending_up_rounded,
    'additional' => Icons.add_shopping_cart_rounded,
    _ => Icons.edit_note_rounded,
  };

  Color get color => switch (source) {
    'mismatch' => _zdRed,
    'max' => _zdPurple,
    'additional' => _zdOrange,
    _ => _zdBlue,
  };

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return branchName.toLowerCase().contains(normalized) ||
        itemCode.toLowerCase().contains(normalized) ||
        itemName.toLowerCase().contains(normalized) ||
        title.toLowerCase().contains(normalized) ||
        detail.toLowerCase().contains(normalized) ||
        category.toLowerCase().contains(normalized);
  }
}

class _ZdLiveActivityPanel extends StatefulWidget {
  final List<Map<String, dynamic>> additionalRows;
  final List<_ZoneLiveActivity> activities;
  final bool connected;

  const _ZdLiveActivityPanel({
    required this.additionalRows,
    required this.activities,
    required this.connected,
  });

  @override
  State<_ZdLiveActivityPanel> createState() => _ZdLiveActivityPanelState();
}

class _ZdLiveActivityPanelState extends State<_ZdLiveActivityPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxRows = widget.activities
        .where((activity) => activity.source == 'max')
        .toList(growable: false);
    final mismatchRows = widget.activities
        .where((activity) => activity.source == 'mismatch')
        .toList(growable: false);
    final entries = <_ZdActivityEntry>[
      if (_filter == 'all' || _filter == 'additional')
        ...widget.additionalRows.map(_ZdActivityEntry.additional),
      if (_filter == 'all' || _filter == 'max')
        ...maxRows.map(_ZdActivityEntry.change),
      if (_filter == 'all' || _filter == 'mismatch')
        ...mismatchRows.map(_ZdActivityEntry.change),
    ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return Container(
      decoration: BoxDecoration(
        color: _zdSurface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _zdBorder),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: .055),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _zdBorder)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4338CA), Color(0xFF7C3AED)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: _zdPurple.withValues(alpha: .22),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.monitor_heart_outlined,
                    size: 21,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Live Branch Activity',
                        style: TextStyle(
                          color: _zdText,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Monitoring every branch in this zone',
                        style: TextStyle(
                          color: _zdTextMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final color = widget.connected ? _zdGreen : _zdAmber;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: color.withValues(alpha: .30)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7 + (_pulseController.value * 2),
                            height: 7 + (_pulseController.value * 2),
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: color.withValues(
                                    alpha: .18 + (_pulseController.value * .22),
                                  ),
                                  blurRadius: 7,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.connected ? 'LIVE' : 'CONNECTING',
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .65,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _zdBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _ZdActivityFilterChip(
                    label: 'All',
                    count:
                        widget.additionalRows.length +
                        maxRows.length +
                        mismatchRows.length,
                    icon: Icons.dashboard_customize_outlined,
                    color: _zdBlue,
                    selected: _filter == 'all',
                    onTap: () => setState(() => _filter = 'all'),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: _ZdActivityFilterChip(
                    label: 'Additional',
                    count: widget.additionalRows.length,
                    icon: Icons.add_shopping_cart_rounded,
                    color: _zdOrange,
                    selected: _filter == 'additional',
                    onTap: () => setState(() => _filter = 'additional'),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: _ZdActivityFilterChip(
                    label: 'Max',
                    count: maxRows.length,
                    icon: Icons.trending_up_rounded,
                    color: _zdPurple,
                    selected: _filter == 'max',
                    onTap: () => setState(() => _filter = 'max'),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: _ZdActivityFilterChip(
                    label: 'Mismatch',
                    count: mismatchRows.length,
                    icon: Icons.warning_amber_rounded,
                    color: _zdRed,
                    selected: _filter == 'mismatch',
                    onTap: () => setState(() => _filter = 'mismatch'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(.025, .02),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: entries.isEmpty
                  ? const _ZdEmptyLiveActivity()
                  : ListView.separated(
                      key: ValueKey(
                        '$_filter-${entries.length}-${entries.first.occurredAt.microsecondsSinceEpoch}',
                      ),
                      padding: const EdgeInsets.fromLTRB(13, 13, 13, 17),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 11),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        if (entry.additionalRow != null) {
                          return _ZdAdditionalRequestCard(
                            row: entry.additionalRow!,
                          );
                        }
                        final activity = entry.activity!;
                        return _ZdLiveActivityTile(activity: activity);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZdActivityEntry {
  final Map<String, dynamic>? additionalRow;
  final _ZoneLiveActivity? activity;
  final DateTime occurredAt;

  const _ZdActivityEntry._({
    required this.additionalRow,
    required this.activity,
    required this.occurredAt,
  });

  factory _ZdActivityEntry.additional(Map<String, dynamic> row) {
    return _ZdActivityEntry._(
      additionalRow: row,
      activity: null,
      occurredAt:
          DateTime.tryParse(_zdString(row['created_at'])) ?? DateTime(1970),
    );
  }

  factory _ZdActivityEntry.change(_ZoneLiveActivity activity) {
    return _ZdActivityEntry._(
      additionalRow: null,
      activity: activity,
      occurredAt: activity.occurredAt,
    );
  }
}

class _ZdActivityFilterChip extends StatefulWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ZdActivityFilterChip({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_ZdActivityFilterChip> createState() => _ZdActivityFilterChipState();
}

class _ZdActivityFilterChipState extends State<_ZdActivityFilterChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 190),
          height: 44,
          transform: Matrix4.translationValues(0, _hovered ? -1 : 0, 0),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? widget.color
                : (_hovered
                      ? widget.color.withValues(alpha: .07)
                      : _zdSurfaceSoft),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: widget.selected || _hovered
                  ? widget.color.withValues(alpha: .65)
                  : _zdBorder,
            ),
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: .20),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: widget.selected ? Colors.white : widget.color,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.selected ? Colors.white : _zdTextSubtle,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Container(
                constraints: const BoxConstraints(minWidth: 21),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.selected
                      ? Colors.white.withValues(alpha: .20)
                      : widget.color.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${widget.count}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: widget.selected ? Colors.white : widget.color,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZdLiveActivityTile extends StatefulWidget {
  final _ZoneLiveActivity activity;

  const _ZdLiveActivityTile({required this.activity});

  @override
  State<_ZdLiveActivityTile> createState() => _ZdLiveActivityTileState();
}

class _ZdLiveActivityTileState extends State<_ZdLiveActivityTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final activity = widget.activity;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        transform: Matrix4.translationValues(0, _hovered ? -2.5 : 0, 0),
        decoration: BoxDecoration(
          color: _hovered
              ? activity.color.withValues(alpha: .055)
              : activity.color.withValues(alpha: .022),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hovered
                ? activity.color.withValues(alpha: .55)
                : activity.color.withValues(alpha: .24),
            width: _hovered ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: activity.color.withValues(alpha: _hovered ? .13 : .035),
              blurRadius: _hovered ? 15 : 7,
              offset: Offset(0, _hovered ? 5 : 2),
            ),
          ],
        ),
        child: SelectionArea(
          child: Padding(
            padding: const EdgeInsets.all(11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: activity.color.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(activity.icon, color: activity.color, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: activity.color.withValues(alpha: .10),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              activity.category,
                              style: TextStyle(
                                color: activity.color,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .45,
                              ),
                            ),
                          ),
                          const SizedBox(width: 9),
                          const Icon(
                            Icons.storefront_rounded,
                            size: 17,
                            color: _zdTextSubtle,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              activity.branchName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _zdText,
                                fontSize: 14.5,
                                height: 1,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .1,
                              ),
                            ),
                          ),
                          Text(
                            DateFormat(
                              'HH:mm:ss',
                            ).format(activity.occurredAt.toLocal()),
                            style: const TextStyle(
                              color: _zdTextMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        activity.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _zdTextMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .15,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          if (activity.itemCode.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: activity.color.withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                  color: activity.color.withValues(alpha: .22),
                                ),
                              ),
                              child: Text(
                                activity.itemCode,
                                style: TextStyle(
                                  color: activity.color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          if (activity.itemCode.isNotEmpty)
                            const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              activity.itemName.isEmpty
                                  ? 'Unknown item'
                                  : activity.itemName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _zdText,
                                fontSize: 14,
                                height: 1.18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 11),
                      _ZdLiveValueStrip(activity: activity),
                      if (_zdString(activity.data['reason']).isNotEmpty) ...[
                        const SizedBox(height: 9),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: activity.color.withValues(alpha: .065),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: activity.color.withValues(alpha: .18),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.notes_rounded,
                                size: 15,
                                color: activity.color,
                              ),
                              const SizedBox(width: 7),
                              Text(
                                'REASON',
                                style: TextStyle(
                                  color: activity.color,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .45,
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  _zdString(activity.data['reason']),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _zdText,
                                    fontSize: 12,
                                    height: 1.25,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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

class _ZdLiveValueStrip extends StatelessWidget {
  final _ZoneLiveActivity activity;

  const _ZdLiveValueStrip({required this.activity});

  @override
  Widget build(BuildContext context) {
    final data = activity.data;
    final values = activity.source == 'mismatch'
        ? <({String label, dynamic value, Color color})>[
            (
              label: 'SYSTEM STOCK',
              value: data['system_stock'],
              color: _zdBlue,
            ),
            (
              label: 'ACTUAL STOCK',
              value: data['actual_stock'],
              color: _zdGreen,
            ),
            (label: 'DIFFERENCE', value: data['diff'], color: _zdRed),
          ]
        : <({String label, dynamic value, Color color})>[
            (
              label: 'DEMAND 30D',
              value: data['current_demand_30d'],
              color: _zdBlue,
            ),
            (
              label: 'NEW MAX',
              value: data['max_adjustment_30d'] ?? data['qty'],
              color: _zdPurple,
            ),
            (
              label: 'TYPE',
              value: _zdPrettyStatus(_zdString(data['adjustment_type'])),
              color: _zdOrange,
            ),
          ];

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: _zdSurfaceSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _zdBorder),
      ),
      child: Row(
        children: values
            .asMap()
            .entries
            .map((entry) {
              final metric = entry.value;
              final text = metric.value is String
                  ? _zdString(metric.value)
                  : _zdNumberText(metric.value);
              return Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: entry.key == values.length - 1
                        ? null
                        : const Border(right: BorderSide(color: _zdBorder)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        metric.label,
                        style: const TextStyle(
                          color: _zdTextMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        text.isEmpty ? '-' : text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: metric.color,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _ZdEmptyLiveActivity extends StatelessWidget {
  const _ZdEmptyLiveActivity();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sensors_rounded, size: 34, color: _zdTextMuted),
          SizedBox(height: 8),
          Text(
            'Waiting for branch activity…',
            style: TextStyle(
              color: _zdTextSubtle,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 3),
          Text(
            'New changes will appear here instantly.',
            style: TextStyle(
              color: _zdTextMuted,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

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
  final String query;
  final ValueChanged<String> onOpen;

  const _ZdBranchGrid({
    required this.branches,
    required this.submissions,
    required this.edits,
    required this.additional,
    required this.selectedBranch,
    required this.query,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final visibleBranches =
        branches.where((row) {
          final branchName = _zdString(row['branch_name']);
          final selected =
              selectedBranch == 'ALL' || branchName == selectedBranch;
          final matchesSearch =
              query.trim().isEmpty ||
              branchName.toLowerCase().contains(query.trim().toLowerCase());
          final orderedToday = submissions.containsKey(_zdKey(branchName));
          return selected && matchesSearch && orderedToday;
        }).toList()..sort(
          (left, right) => _zdString(left['branch_name'])
              .toLowerCase()
              .compareTo(_zdString(right['branch_name']).toLowerCase()),
        );

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
                _ZdCountBadge(count: visibleBranches.length),
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
                      mainAxisExtent: 145,
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
                        deadlineHour:
                            int.tryParse(
                              _zdString(
                                visibleBranches[index]['submit_end_hour'],
                              ),
                            ) ??
                            24,
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
  final int deadlineHour;
  final VoidCallback onTap;

  const _ZdBranchCard({
    required this.branch,
    required this.submitted,
    required this.editCount,
    required this.additionalCount,
    required this.deadlineHour,
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
                  _ZdDeadlinePill(
                    hour: widget.deadlineHour,
                    submitted: submitted,
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

class _ZdDeadlinePill extends StatelessWidget {
  final int hour;
  final bool submitted;

  const _ZdDeadlinePill({required this.hour, required this.submitted});

  @override
  Widget build(BuildContext context) {
    final color = submitted ? _zdGreenDark : _zdAmber;
    final background = submitted ? _zdGreenCard : _zdAmberSoft;
    final border = submitted ? _zdGreenBorder : _zdAmberBorder;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: border.withValues(alpha: .72)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            'Deadline ${_formatHour(hour)}',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatHour(int hour) {
    if (hour >= 24) return '12:00 AM';
    final normalized = hour.clamp(0, 23);
    final period = normalized >= 12 ? 'PM' : 'AM';
    final display = normalized % 12 == 0 ? 12 : normalized % 12;
    return '$display:00 $period';
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
          'No branches have submitted an order today.',
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
      child: SelectionArea(
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
                                  fontSize: 13,
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
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _zdOrangeSoft,
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(color: _zdOrangeBorder),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add_shopping_cart_rounded,
                                      size: 11,
                                      color: _zdOrange,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'ADDITIONAL',
                                      style: TextStyle(
                                        color: _zdOrange,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: .45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 7),
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
                                Icons.storefront_rounded,
                                size: 16,
                                color: _zdTextSubtle,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  _zdString(row['branch_name']),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _zdText,
                                    fontSize: 14.5,
                                    height: 1,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: .1,
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
                            height: 66,
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
          fontSize: 10,
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
                      fontSize: 9,
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
                fontSize: 9.5,
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
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
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
