import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/remote/items_tracker_remote_ds.dart';
import '../../../domain/entities/items_tracker_record.dart';
import '../../../domain/repositories/items_tracker_repository.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../widgets/items_tracker_dialogs.dart';
import '../widgets/items_tracker_grid.dart';

class ItemsTrackerPage extends StatefulWidget {
  final String role;
  final bool embedded;
  final bool showBackButton;
  final ItemsTrackerRepository? repository;

  const ItemsTrackerPage({
    super.key,
    required this.role,
    this.embedded = false,
    this.showBackButton = false,
    this.repository,
  });

  @override
  State<ItemsTrackerPage> createState() => _ItemsTrackerPageState();
}

class _ItemsTrackerPageState extends State<ItemsTrackerPage> {
  late final ItemsTrackerRepository _repository;
  late final String _role;

  final _searchController = TextEditingController();
  final _gridController = ItemsTrackerGridController();

  Timer? _searchDebounce;
  Timer? _realtimeDebounce;
  RealtimeChannel? _channel;

  List<ItemsTrackerRecord> _records = const [];
  List<ItemsTrackerRecord> _visibleRecords = const [];
  Map<String, String> _searchIndex = const {};
  List<String> _itemStatuses = const [];

  String _departmentFilter = 'all';
  String _caseStatusFilter = 'all';
  bool _myQueueOnly = false;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  bool get _canEditInventory => ItemsTrackerRoles.canEditInventoryFields(_role);

  @override
  void initState() {
    super.initState();
    _role = ItemsTrackerRoles.normalize(widget.role);
    _repository =
        widget.repository ?? ItemsTrackerRemoteDs(Supabase.instance.client);
    _load();
    if (widget.repository == null) _startRealtime();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _realtimeDebounce?.cancel();
    _searchController.dispose();
    if (_channel != null) {
      Supabase.instance.client.removeChannel(_channel!);
    }
    super.dispose();
  }

  void _startRealtime() {
    void changed(PostgresChangePayload _) {
      _realtimeDebounce?.cancel();
      _realtimeDebounce = Timer(const Duration(milliseconds: 420), () {
        if (mounted) unawaited(_load(silent: true));
      });
    }

    _channel = Supabase.instance.client
        .channel('items-tracker-$_role-${identityHashCode(this)}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'items_tracker_items',
          callback: changed,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'items_tracker_events',
          callback: changed,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'items_tracker_comments',
          callback: changed,
        )
        .subscribe();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else if (mounted) {
      setState(() => _refreshing = true);
    }

    try {
      final result = await Future.wait([
        _repository.fetchRecords(),
        _repository.fetchItemStatuses(),
      ]).timeout(const Duration(seconds: 30));

      if (!mounted) return;

      final records = [...result[0] as List<ItemsTrackerRecord>]
        ..sort(_compareRecords);

      setState(() {
        _records = records;
        _itemStatuses = result[1] as List<String>;
        _searchIndex = {
          for (final record in records)
            record.id: [
              record.itemCode,
              record.itemName,
              record.category,
              record.supplier,
              record.company,
              record.sourceItemStatus,
              record.inventoryNote,
              record.statusUpdatedTo,
              record.followUpRole,
              record.caseStatus,
              record.displayedLastAction,
              record.latestComment,
              record.commentByRole,
            ].join('\u0000').toLowerCase(),
        };
        _applyFilters();
        _loading = false;
        _refreshing = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        if (_records.isEmpty) _error = _friendlyError(error);
      });
      if (_records.isNotEmpty && !silent) {
        _showMessage(_friendlyError(error), isError: true);
      }
    }
  }

  int _compareRecords(ItemsTrackerRecord left, ItemsTrackerRecord right) {
    final leftMine = left.canAct(_role) ? 0 : 1;
    final rightMine = right.canAct(_role) ? 0 : 1;
    final mineComparison = leftMine.compareTo(rightMine);
    if (mineComparison != 0) return mineComparison;

    final leftClosed = left.caseStatus == ItemsTrackerCaseStatuses.closed
        ? 1
        : 0;
    final rightClosed = right.caseStatus == ItemsTrackerCaseStatuses.closed
        ? 1
        : 0;
    final closedComparison = leftClosed.compareTo(rightClosed);
    if (closedComparison != 0) return closedComparison;

    return right.updatedAt.compareTo(left.updatedAt);
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    _visibleRecords = _records
        .where((record) {
          if (_departmentFilter != 'all' &&
              record.followUpRole != _departmentFilter) {
            return false;
          }
          if (_caseStatusFilter != 'all' &&
              record.caseStatus != _caseStatusFilter) {
            return false;
          }
          if (_myQueueOnly && !record.canAct(_role)) return false;
          return query.isEmpty ||
              (_searchIndex[record.id]?.contains(query) ?? false);
        })
        .toList(growable: false);
  }

  void _scheduleSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 140), () {
      if (mounted) setState(_applyFilters);
    });
  }

  void _clearFilters() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _gridController.clearFilters();
    setState(() {
      _departmentFilter = 'all';
      _caseStatusFilter = 'all';
      _myQueueOnly = false;
      _applyFilters();
    });
  }

  Future<void> _openEditor([ItemsTrackerRecord? record]) async {
    if (!_canEditInventory) return;
    final changed = await showItemsTrackerEditorDialog(
      context: context,
      repository: _repository,
      statusOptions: _itemStatuses,
      record: record,
    );
    if (changed) {
      _showMessage(record == null ? 'Item added to tracker.' : 'Item updated.');
      await _load(silent: true);
    }
  }

  Future<bool> _updateStatusUpdatedTo(
    ItemsTrackerRecord record,
    String value,
  ) async {
    if (!_canEditInventory) {
      _showMessage(
        'Only Inventory can change Status Updated To.',
        isError: true,
      );
      return false;
    }

    final cleaned = value.trim();
    if (cleaned.isEmpty) return false;
    if (cleaned.toLowerCase() == record.statusUpdatedTo.trim().toLowerCase()) {
      return true;
    }

    try {
      await _repository.updateStatusUpdatedTo(
        UpdateItemsTrackerStatus(
          itemId: record.id,
          statusUpdatedTo: cleaned,
          expectedVersion: record.rowVersion,
        ),
      );
      if (!mounted) return true;
      _showMessage('Status Updated To changed to $cleaned.');
      await _load(silent: true);
      return true;
    } catch (error) {
      if (mounted) _showMessage(_friendlyError(error), isError: true);
      return false;
    }
  }

  Future<void> _openAction(ItemsTrackerRecord record) async {
    if (!record.canAct(_role)) {
      _showMessage(
        'This item is assigned to ${ItemsTrackerRoles.label(record.followUpRole)}.',
        isError: true,
      );
      return;
    }

    final changed = await showItemsTrackerActivityDialog(
      context: context,
      repository: _repository,
      record: record,
      role: _role,
    );
    if (changed) {
      _showMessage('Activity saved to the permanent timeline.');
      await _load(silent: true);
    }
  }

  Future<void> _openHistory(ItemsTrackerRecord record) {
    return showItemsTrackerTimelineDialog(
      context: context,
      repository: _repository,
      record: record,
    );
  }

  Future<void> _openComments(ItemsTrackerRecord record) async {
    final changed = await showItemsTrackerCommentsDialog(
      context: context,
      repository: _repository,
      record: record,
      role: _role,
    );
    if (changed) await _load(silent: true);
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(message),
        backgroundColor: isError
            ? const Color(0xffb63b3b)
            : const Color(0xff0d806e),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _records
        .where(
          (record) => record.caseStatus == ItemsTrackerCaseStatuses.pending,
        )
        .length;
    final myQueueCount = _records
        .where((record) => record.canAct(_role))
        .length;
    final resolvedCount = _records
        .where(
          (record) =>
              record.caseStatus == ItemsTrackerCaseStatuses.resolved ||
              record.caseStatus == ItemsTrackerCaseStatuses.closed,
        )
        .length;

    final body = SafeArea(
      child: Column(
        children: [
          _TopBar(
            role: _role,
            embedded: widget.embedded,
            showBackButton: widget.showBackButton,
            refreshing: _refreshing,
            canAdd: _canEditInventory,
            onBack: widget.showBackButton && Navigator.canPop(context)
                ? () => Navigator.pop(context)
                : null,
            onRefresh: () => _load(silent: _records.isNotEmpty),
            onAdd: _canEditInventory ? () => _openEditor() : null,
            onLogout: !widget.embedded && !widget.showBackButton
                ? () => context.read<AuthBloc>().add(AuthLogoutRequested())
                : null,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 980;
                final horizontalPadding = compact ? 14.0 : 24.0;
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    widget.embedded ? horizontalPadding + 8 : horizontalPadding,
                    compact ? 14 : 20,
                    horizontalPadding,
                    compact ? 14 : 22,
                  ),
                  child: Column(
                    children: [
                      _MetricsStrip(
                        tracked: _records.length,
                        myQueue: myQueueCount,
                        pending: pendingCount,
                        resolved: resolvedCount,
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: _WorkspacePanel(
                          role: _role,
                          canEditInventory: _canEditInventory,
                          visibleCount: _visibleRecords.length,
                          totalCount: _records.length,
                          filters: _Filters(
                            searchController: _searchController,
                            role: _role,
                            department: _departmentFilter,
                            caseStatus: _caseStatusFilter,
                            myQueueOnly: _myQueueOnly,
                            visibleCount: _visibleRecords.length,
                            onSearch: _scheduleSearch,
                            onDepartmentChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _departmentFilter = value;
                                _applyFilters();
                              });
                            },
                            onCaseStatusChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _caseStatusFilter = value;
                                _applyFilters();
                              });
                            },
                            onMyQueueChanged: (value) {
                              setState(() {
                                _myQueueOnly = value;
                                _applyFilters();
                              });
                            },
                            onClear: _clearFilters,
                          ),
                          child: _buildContent(),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    final themed = Theme(data: _trackerTheme(Theme.of(context)), child: body);
    const background = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xfff6f8fb), Color(0xffedf3f6)],
      ),
    );

    if (widget.embedded) {
      return DecoratedBox(decoration: background, child: themed);
    }
    return Scaffold(
      backgroundColor: const Color(0xfff1f5f7),
      body: DecoratedBox(decoration: background, child: themed),
    );
  }

  Widget _buildContent() {
    if (_loading) return const _LoadingState();

    if (_error != null) {
      return _EmptyState(
        icon: Icons.storage_rounded,
        title: 'Items Tracker is not ready',
        message: _error!,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }

    if (_visibleRecords.isEmpty) {
      return _EmptyState(
        icon: _records.isEmpty
            ? Icons.playlist_add_rounded
            : Icons.filter_alt_off_rounded,
        title: _records.isEmpty
            ? 'Start the Items Tracker'
            : 'No matching items',
        message: _records.isEmpty
            ? _canEditInventory
                  ? 'Add the first item. Catalog details and the first follow-up assignment will be recorded automatically.'
                  : 'Inventory has not added any tracked items yet.'
            : 'Try changing the search text or clearing the filters.',
        actionLabel: _records.isEmpty && _canEditInventory ? 'Add item' : null,
        onAction: _records.isEmpty && _canEditInventory
            ? () => _openEditor()
            : null,
      );
    }

    return ItemsTrackerGrid(
      controller: _gridController,
      records: _visibleRecords,
      role: _role,
      statusOptions: _itemStatuses,
      onStatusUpdatedToChanged: _updateStatusUpdatedTo,
      onEditInventory: _openEditor,
      onAction: _openAction,
      onHistory: _openHistory,
      onComment: _openComments,
    );
  }
}

class _TopBar extends StatelessWidget {
  final String role;
  final bool embedded;
  final bool showBackButton;
  final bool refreshing;
  final bool canAdd;
  final VoidCallback? onBack;
  final VoidCallback onRefresh;
  final VoidCallback? onAdd;
  final VoidCallback? onLogout;

  const _TopBar({
    required this.role,
    required this.embedded,
    required this.showBackButton,
    required this.refreshing,
    required this.canAdd,
    required this.onBack,
    required this.onRefresh,
    required this.onAdd,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final normalizedRole = ItemsTrackerRoles.normalize(role);
    final colors = switch (normalizedRole) {
      ItemsTrackerRoles.inventory => const [
        Color(0xff073f4b),
        Color(0xff08746f),
      ],
      ItemsTrackerRoles.purchase => const [
        Color(0xff153f67),
        Color(0xff177aa2),
      ],
      ItemsTrackerRoles.category => const [
        Color(0xff412b5d),
        Color(0xff7853a3),
      ],
      _ => const [Color(0xff173247), Color(0xff285c70)],
    };

    return Container(
      height: 90,
      padding: EdgeInsets.fromLTRB(embedded ? 54 : 22, 0, 22, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: colors,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x300b3040),
            blurRadius: 22,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;

          return Row(
            children: [
              if (showBackButton) ...[
                _HeaderIconButton(
                  tooltip: 'Back',
                  icon: Icons.arrow_back_rounded,
                  onPressed: onBack,
                ),
                const SizedBox(width: 10),
              ],
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .94),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.track_changes_rounded,
                  color: colors.last,
                  size: 27,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Items Tracker',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.25,
                            ),
                          ),
                          if (!compact)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                'Track escalations, ownership, actions and follow-up clearly',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Color(0xffd8e8ec),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    _RoleBadge(role: role),
                  ],
                ),
              ),
              if (!compact) ...[
                _LiveBadge(canEditInventory: canAdd),
                const SizedBox(width: 10),
              ],
              _HeaderIconButton(
                tooltip: 'Refresh',
                icon: Icons.refresh_rounded,
                loading: refreshing,
                onPressed: refreshing ? null : onRefresh,
              ),
              if (canAdd) ...[
                const SizedBox(width: 10),
                FilledButton.icon(
                  key: const ValueKey('itemsTrackerAddItem'),
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    backgroundColor: const Color(0xffffcf4d),
                    foregroundColor: const Color(0xff173247),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 19,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 21),
                  label: Text(
                    compact ? 'Add' : 'Add Item',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
              if (onLogout != null) ...[
                const SizedBox(width: 8),
                _HeaderIconButton(
                  tooltip: 'Sign out',
                  icon: Icons.logout_rounded,
                  onPressed: onLogout,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;

  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox.square(
            dimension: 43,
            child: Center(
              child: loading
                  ? const SizedBox.square(
                      dimension: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(icon, color: Colors.white, size: 21),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;

  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final normalized = ItemsTrackerRoles.normalize(role);

    final background = switch (normalized) {
      ItemsTrackerRoles.inventory => const Color(0xffffcf4d),
      ItemsTrackerRoles.purchase => const Color(0xff85d9ff),
      ItemsTrackerRoles.category => const Color(0xffd8b5ff),
      _ => const Color(0xffd7e3e8),
    };

    final foreground = switch (normalized) {
      ItemsTrackerRoles.inventory => const Color(0xff4f3900),
      ItemsTrackerRoles.purchase => const Color(0xff063d59),
      ItemsTrackerRoles.category => const Color(0xff43245f),
      _ => const Color(0xff294454),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1f000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        ItemsTrackerRoles.label(role).toUpperCase(),
        style: TextStyle(
          color: foreground,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: .55,
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  final bool canEditInventory;

  const _LiveBadge({required this.canEditInventory});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xff67e2c0),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            canEditInventory ? 'Inventory controls enabled' : 'Live workspace',
            style: const TextStyle(
              color: Color(0xffd5e3e8),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsStrip extends StatelessWidget {
  final int tracked;
  final int myQueue;
  final int pending;
  final int resolved;

  const _MetricsStrip({
    required this.tracked,
    required this.myQueue,
    required this.pending,
    required this.resolved,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1040
            ? 4
            : constraints.maxWidth >= 600
            ? 2
            : 1;
        final spacing = 12.0;
        final width =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            _MetricCard(
              width: width,
              label: 'Tracked items',
              helper: 'All active records',
              value: '$tracked',
              icon: Icons.inventory_2_outlined,
              color: const Color(0xff2d91b5),
            ),
            _MetricCard(
              width: width,
              label: 'My queue',
              helper: 'Needs your team',
              value: '$myQueue',
              icon: Icons.assignment_ind_outlined,
              color: const Color(0xff137f95),
            ),
            _MetricCard(
              width: width,
              label: 'Pending',
              helper: 'Waiting for action',
              value: '$pending',
              icon: Icons.pending_actions_rounded,
              color: const Color(0xffce7a18),
            ),
            _MetricCard(
              width: width,
              label: 'Resolved / closed',
              helper: 'Completed records',
              value: '$resolved',
              icon: Icons.task_alt_rounded,
              color: const Color(0xff168873),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatefulWidget {
  final double width;
  final String label;
  final String helper;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.width,
    required this.label,
    required this.helper,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  State<_MetricCard> createState() => _MetricCardState();
}

class _MetricCardState extends State<_MetricCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: widget.width,
        height: 92,
        transform: Matrix4.translationValues(0, _hovered ? -3 : 0, 0),
        padding: const EdgeInsets.symmetric(horizontal: 17),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: _hovered
                ? widget.color.withValues(alpha: .35)
                : const Color(0xffdfe7ec),
          ),
          boxShadow: [
            BoxShadow(
              color: _hovered
                  ? widget.color.withValues(alpha: .13)
                  : const Color(0x0b102d42),
              blurRadius: _hovered ? 20 : 13,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(widget.icon, color: widget.color, size: 23),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.value,
                    style: const TextStyle(
                      color: Color(0xff173247),
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff344c5d),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    widget.helper,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff8796a1),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 4,
              height: 36,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: .72),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspacePanel extends StatelessWidget {
  final String role;
  final bool canEditInventory;
  final int visibleCount;
  final int totalCount;
  final Widget filters;
  final Widget child;

  const _WorkspacePanel({
    required this.role,
    required this.canEditInventory,
    required this.visibleCount,
    required this.totalCount,
    required this.filters,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xffdce5ea)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11102d42),
            blurRadius: 24,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        children: [
          _WorkspaceHeader(
            role: role,
            canEditInventory: canEditInventory,
            visibleCount: visibleCount,
            totalCount: totalCount,
          ),
          const Divider(height: 1, color: Color(0xffe6ecef)),
          filters,
          const Divider(height: 1, color: Color(0xffe6ecef)),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  final String role;
  final bool canEditInventory;
  final int visibleCount;
  final int totalCount;

  const _WorkspaceHeader({
    required this.role,
    required this.canEditInventory,
    required this.visibleCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 13),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xffe8f4f7),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.view_list_rounded,
              size: 20,
              color: Color(0xff176b7c),
            ),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Items workspace',
                  style: TextStyle(
                    color: Color(0xff173247),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Prioritized workflow view — drag, resize, sort or filter any column',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xff7c8b96),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (canEditInventory)
            Container(
              margin: const EdgeInsets.only(right: 9),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xfffff7dd),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xffffe38a)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 15,
                    color: Color(0xff9a6b00),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Inventory edit access',
                    style: TextStyle(
                      color: Color(0xff8a6200),
                      fontSize: 9.8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xffeef5f8),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$visibleCount of $totalCount',
              style: const TextStyle(
                color: Color(0xff275268),
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  final TextEditingController searchController;
  final String role;
  final String department;
  final String caseStatus;
  final bool myQueueOnly;
  final int visibleCount;
  final VoidCallback onSearch;
  final ValueChanged<String?> onDepartmentChanged;
  final ValueChanged<String?> onCaseStatusChanged;
  final ValueChanged<bool> onMyQueueChanged;
  final VoidCallback onClear;

  const _Filters({
    required this.searchController,
    required this.role,
    required this.department,
    required this.caseStatus,
    required this.myQueueOnly,
    required this.visibleCount,
    required this.onSearch,
    required this.onDepartmentChanged,
    required this.onCaseStatusChanged,
    required this.onMyQueueChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1150;
        final medium = constraints.maxWidth >= 760;

        final search = TextField(
          key: const ValueKey('itemsTrackerSearch'),
          controller: searchController,
          onChanged: (_) => onSearch(),
          decoration: InputDecoration(
            hintText: 'Search item, supplier, action, status or comment…',
            prefixIcon: Icon(Icons.search_rounded, size: 20),
            isDense: true,
            fillColor: AppColors.backgroundWidget,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: AppColors.primaryColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: AppColors.primaryColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide(color: AppColors.primaryColor),
            ),
          ),
        );

        final departmentField = _FilterSelect(
          width: 185,
          label: 'Follow-up team',
          icon: Icons.groups_2_outlined,
          value: department,

          items: [
            const DropdownMenuItem(value: 'all', child: Text('All teams')),
            ...ItemsTrackerRoles.allowed.map(
              (value) => DropdownMenuItem(
                value: value,
                child: Text(ItemsTrackerRoles.label(value)),
              ),
            ),
          ],
          onChanged: onDepartmentChanged,
        );

        /*  final statusField = _FilterSelect(
          width: 175,
          label: 'Case status',
          icon: Icons.flag_outlined,
          value: caseStatus,
          items: [
            const DropdownMenuItem(value: 'all', child: Text('All statuses')),
            ...ItemsTrackerCaseStatuses.values.map(
              (value) => DropdownMenuItem(
                value: value,
                child: Text(ItemsTrackerCaseStatuses.label(value)),
              ),
            ),
          ],
          onChanged: onCaseStatusChanged,
        );*/

        /*       final queue = _QueueToggle(
          role: role,
          selected: myQueueOnly,
          onChanged: onMyQueueChanged,
        );
*/
        final clear = Tooltip(
          message: 'Clear page and column filters',
          child: OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
            label: const Text('Clear'),
          ),
        );

        if (wide) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: 10),
                departmentField,
                /*   const SizedBox(width: 10),
                statusField,*/
                /* const SizedBox(width: 10),
                queue,*/
                const SizedBox(width: 8),
                clear,
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            children: [
              SizedBox(width: double.infinity, child: search),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    departmentField,
                    //statusField,
                    //  queue,
                    clear,
                    if (!medium)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xffeef5f8),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$visibleCount visible',
                          style: const TextStyle(
                            color: Color(0xff275268),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
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

class _FilterSelect extends StatelessWidget {
  final double width;
  final String label;
  final IconData icon;
  final String value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  const _FilterSelect({
    required this.width,
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$value'),
        initialValue: value,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18),
          isDense: true,
          filled: true,
          fillColor: AppColors.backgroundWidget,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: AppColors.primaryColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: AppColors.primaryColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: AppColors.primaryColor),
          ),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }
}

class _QueueToggle extends StatelessWidget {
  final String role;
  final bool selected;
  final ValueChanged<bool> onChanged;

  const _QueueToggle({
    required this.role,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      avatar: Icon(
        selected
            ? Icons.assignment_turned_in_rounded
            : Icons.assignment_ind_outlined,
        size: 17,
      ),
      label: Text('My queue · ${ItemsTrackerRoles.label(role)}'),
      onSelected: onChanged,
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: List.generate(
          6,
          (index) => Container(
            height: 66,
            margin: const EdgeInsets.only(bottom: 9),
            decoration: BoxDecoration(
              color: index.isEven
                  ? const Color(0xfff1f5f7)
                  : const Color(0xfff7f9fa),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xfffff4bf), Color(0xffdef4fa)],
                  ),
                  borderRadius: BorderRadius.circular(23),
                ),
                child: Icon(icon, size: 35, color: const Color(0xff1b6073)),
              ),
              const SizedBox(height: 17),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xff173247),
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xff70808b), height: 1.45),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

ThemeData _trackerTheme(ThemeData base) {
  const primary = Color(0xff0b7180);
  const text = Color(0xff1d3342);
  const subText = Color(0xff5f7380);
  const border = Color(0xffd7e2e8);

  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: primary,
      secondary: const Color(0xff7650b7),
      surface: Colors.white,
    ),
    textTheme: base.textTheme.copyWith(
      bodyLarge: const TextStyle(
        color: text,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: const TextStyle(
        color: text,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      bodySmall: const TextStyle(
        color: subText,
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: primary, width: 1.7),
      ),
      labelStyle: const TextStyle(
        color: subText,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: const TextStyle(
        color: Color(0xff899aa4),
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
      ),
      prefixIconColor: const Color(0xff55727f),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        backgroundColor: const Color(0xff183f56),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xff284c61),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        side: const BorderSide(color: border),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: Color(0xfff2f7f9),
      selectedColor: Color(0xffdff1f4),
      checkmarkColor: Color(0xff0b7180),
      labelStyle: TextStyle(
        color: Color(0xff304b5b),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      secondaryLabelStyle: TextStyle(
        color: Color(0xff075f6b),
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
      side: BorderSide(color: border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(11)),
      ),
      padding: EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    ),
  );
}

String _friendlyError(Object error) {
  final text = error.toString();
  if (text.contains('item_tracker_grid') ||
      text.contains('item_tracker_status_options')) {
    return 'Run supabase/sql/items_tracker_module.sql in Supabase, then refresh this page.';
  }
  if (text.contains('ITEM_TRACKER_STALE_VERSION') ||
      text.contains('STALE_ITEM_VERSION')) {
    return 'This item was changed by another user. Refresh and try again.';
  }
  if (text.contains('ITEM_TRACKER_INVENTORY_ONLY') ||
      text.contains('INVENTORY_PERMISSION_REQUIRED')) {
    return 'Only Inventory can change this field.';
  }
  if (text.contains('INVALID_ITEM_STATUS')) {
    return 'This status is no longer available in item_report.';
  }
  if (text.contains('permission denied')) {
    return 'Your account does not have Items Tracker access. Confirm that app_users.role is inventory, purchase, or category.';
  }
  return text
      .replaceFirst('PostgrestException(message: ', '')
      .replaceFirst('Exception: ', '')
      .split(', code:')
      .first
      .trim();
}
