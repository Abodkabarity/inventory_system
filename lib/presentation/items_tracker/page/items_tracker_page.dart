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
              record.displayedLastActivity,
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
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                widget.embedded ? 24 : 28,
                20,
                28,
                26,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          label: 'Tracked items',
                          value: '${_records.length}',
                          icon: Icons.inventory_2_outlined,
                          color: AppColors.primaryColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          label: 'My queue',
                          value: '$myQueueCount',
                          icon: Icons.assignment_ind_outlined,
                          color: const Color(0xff087e9b),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          label: 'Pending',
                          value: '$pendingCount',
                          icon: Icons.pending_actions_rounded,
                          color: const Color(0xffd4770a),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          label: 'Resolved / closed',
                          value: '$resolvedCount',
                          icon: Icons.task_alt_rounded,
                          color: const Color(0xff0f8f78),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xffe1e8ef)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x10102d42),
                            blurRadius: 24,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _Filters(
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
                          const Divider(height: 1),
                          Expanded(child: _buildContent()),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final themed = Theme(data: _trackerTheme(Theme.of(context)), child: body);
    if (widget.embedded) {
      return Material(color: const Color(0xfff4f7fb), child: themed);
    }
    return Scaffold(backgroundColor: const Color(0xfff4f7fb), body: themed);
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
    return Container(
      height: 88,
      padding: EdgeInsets.fromLTRB(embedded ? 58 : 26, 0, 26, 0),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xff102d42), Color(0xff17637a)],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x25102d42),
            blurRadius: 18,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          if (showBackButton) ...[
            IconButton(
              tooltip: 'Back to Purchase Status',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
            const SizedBox(width: 6),
          ],
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xffffd955), Color(0xff63d8e9)],
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.track_changes_rounded,
              color: AppColors.secondaryColor,
              size: 27,
            ),
          ),
          const SizedBox(width: 14),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Items Tracker',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'Inventory escalation, ownership, actions and team comments',
                style: TextStyle(color: Color(0xffc4d7e1), fontSize: 11.5),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: .16)),
            ),
            child: Text(
              ItemsTrackerRoles.label(role).toUpperCase(),
              style: const TextStyle(
                color: Color(0xffffdf6d),
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: .5,
              ),
            ),
          ),
          const Spacer(),
          if (!canAdd)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xffc4d7e1),
                    size: 17,
                  ),
                  SizedBox(width: 7),
                  Text(
                    'Assigned items are editable; all comments are open',
                    style: TextStyle(color: Color(0xffc4d7e1), fontSize: 10.5),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Refresh',
            onPressed: refreshing ? null : onRefresh,
            icon: refreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
          if (canAdd) ...[
            const SizedBox(width: 8),
            FilledButton.icon(
              key: const ValueKey('itemsTrackerAddItem'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xffffcf3e),
                foregroundColor: AppColors.secondaryColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 19,
                  vertical: 17,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Add Item',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
          if (onLogout != null) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Sign out',
              onPressed: onLogout,
              icon: const Icon(Icons.logout_rounded, color: Color(0xffc4d7e1)),
            ),
          ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: TextField(
              key: const ValueKey('itemsTrackerSearch'),
              controller: searchController,
              onChanged: (_) => onSearch(),
              decoration: const InputDecoration(
                hintText: 'Search item, supplier, action or comment…',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              initialValue: department,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Follow-up team',
                isDense: true,
              ),
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
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              initialValue: caseStatus,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Case status',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(
                  value: 'all',
                  child: Text('All statuses'),
                ),
                ...ItemsTrackerCaseStatuses.values.map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(ItemsTrackerCaseStatuses.label(value)),
                  ),
                ),
              ],
              onChanged: onCaseStatusChanged,
            ),
          ),
          const SizedBox(width: 12),
          FilterChip(
            selected: myQueueOnly,
            avatar: Icon(
              myQueueOnly
                  ? Icons.assignment_turned_in_outlined
                  : Icons.assignment_ind_outlined,
              size: 18,
            ),
            label: Text('My queue • ${ItemsTrackerRoles.label(role)}'),
            onSelected: onMyQueueChanged,
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Clear page and Excel-style column filters',
            child: OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: const Text('Clear'),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xffeef6fa),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$visibleCount visible',
              style: const TextStyle(
                color: AppColors.secondaryColor,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86,
      padding: const EdgeInsets.symmetric(horizontal: 17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xffe1e8ef)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0b102d42),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 13),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.subText,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: List.generate(
          6,
          (index) => Container(
            height: 58,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: index.isEven
                  ? const Color(0xfff1f6f9)
                  : const Color(0xfff8fafb),
              borderRadius: BorderRadius.circular(10),
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
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xfffff4bf), Color(0xffdef4fa)],
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(icon, size: 34, color: AppColors.secondaryColor),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.subText, height: 1.45),
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
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.primaryColor,
      secondary: const Color(0xff7650b7),
      surface: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xfffbfcfd),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primaryColor, width: 1.6),
      ),
      labelStyle: const TextStyle(color: AppColors.subText, fontSize: 12),
      hintStyle: const TextStyle(color: Color(0xff9aa6b1), fontSize: 12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.secondaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.secondaryColor,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

String _friendlyError(Object error) {
  final text = error.toString();
  if (text.contains('item_tracker_grid') ||
      text.contains('item_tracker_status_options')) {
    return 'Run supabase/sql/items_tracker_module.sql in Supabase, then refresh this page.';
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
