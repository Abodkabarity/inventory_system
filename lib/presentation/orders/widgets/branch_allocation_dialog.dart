import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/utils/branch_allocation_excel_exporter.dart';
import '../../../domain/entities/branch_allocation_task.dart';
import '../bloc/order_bloc/orders_bloc.dart';
import '../bloc/order_bloc/orders_event.dart';
import '../bloc/order_bloc/orders_state.dart';

class BranchAllocationHeaderButton extends StatelessWidget {
  final int pendingToSend;
  final int incomingCount;
  final bool isLoading;
  final VoidCallback onTap;

  const BranchAllocationHeaderButton({
    super.key,
    required this.pendingToSend,
    required this.incomingCount,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasPending = pendingToSend > 0;

    return Tooltip(
      message: 'Open allocation tasks',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: hasPending
                ? const Color(0xffFFF7ED)
                : const Color(0xffECFEFF),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: hasPending
                  ? const Color(0xffFDBA74)
                  : const Color(0xff67E8F9),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .04),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  Icons.account_tree_rounded,
                  size: 18,
                  color: hasPending
                      ? const Color(0xffEA580C)
                      : const Color(0xff0891B2),
                ),
              const SizedBox(width: 7),
              const Text(
                'Allocation',
                style: TextStyle(
                  color: Color(0xff0F172A),
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (pendingToSend > 0) ...[
                const SizedBox(width: 7),
                _TinyBadge(
                  value: pendingToSend.toString(),
                  color: const Color(0xffF97316),
                ),
              ],
              if (incomingCount > 0) ...[
                const SizedBox(width: 5),
                _TinyBadge(
                  value: incomingCount.toString(),
                  color: const Color(0xff0EA5E9),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class BranchAllocationPage extends StatefulWidget {
  final VoidCallback? onBack;

  const BranchAllocationPage({super.key, this.onBack});

  @override
  State<BranchAllocationPage> createState() => _BranchAllocationPageState();
}

class _BranchAllocationPageState extends State<BranchAllocationPage> {
  String? _selectedBatchId;
  String? _selectedIncomingBatchId;
  String _mode = 'to_send';
  String _outgoingFilter = 'pending';
  String _incomingFilter = 'all';
  String _outgoingBranchFilter = 'all';
  String _incomingBranchFilter = 'all';
  String _search = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OrdersBloc>().add(const OrdersLoadBranchAllocationTasks());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OrdersBloc, OrdersState>(
      builder: (context, state) {
        final batches = _buildBatches(state.outgoingAllocationTasks);
        final incomingBatches = _buildBatches(state.incomingAllocationTasks);
        if (_selectedBatchId != null &&
            !batches.any((batch) => batch.id == _selectedBatchId)) {
          _selectedBatchId = null;
        }
        if (_selectedIncomingBatchId != null &&
            !incomingBatches.any(
              (batch) => batch.id == _selectedIncomingBatchId,
            )) {
          _selectedIncomingBatchId = null;
        }

        final selectedBatch = batches
            .where((batch) => batch.id == _selectedBatchId)
            .cast<_AllocationBatch?>()
            .firstOrNull;
        final selectedIncomingBatch = incomingBatches
            .where((batch) => batch.id == _selectedIncomingBatchId)
            .cast<_AllocationBatch?>()
            .firstOrNull;
        final selectedOutgoing =
            selectedBatch?.rows ?? const <BranchAllocationTask>[];
        final selectedIncoming =
            selectedIncomingBatch?.rows ?? const <BranchAllocationTask>[];
        final outgoingBranchOptions = _branchOptions(
          selectedOutgoing,
          outgoing: true,
        );
        if (!outgoingBranchOptions.contains(_outgoingBranchFilter)) {
          _outgoingBranchFilter = 'all';
        }
        final incomingBranchOptions = _branchOptions(
          selectedIncoming,
          outgoing: false,
        );
        if (!incomingBranchOptions.contains(_incomingBranchFilter)) {
          _incomingBranchFilter = 'all';
        }
        final outgoing = _filterRows(
          selectedOutgoing,
          _outgoingFilter,
          branchFilter: _outgoingBranchFilter,
          outgoing: true,
        );
        final incoming = _filterRows(
          selectedIncoming,
          _incomingFilter,
          branchFilter: _incomingBranchFilter,
          outgoing: false,
        );

        final pending = state.outgoingAllocationTasks
            .where((task) => task.isSenderPending)
            .length;
        final noSend = state.outgoingAllocationTasks
            .where((task) => task.isNoSend)
            .length;
        final confirmed = state.outgoingAllocationTasks
            .where((task) => task.isSenderConfirmed)
            .length;

        return Scaffold(
          backgroundColor: const Color(0xffF4F8FC),
          body: SafeArea(
            child: Column(
              children: [
                _PageHeader(
                  branchName: state.branchName,
                  isLoading: state.isBranchAllocationLoading,
                  pending: pending,
                  confirmed: confirmed,
                  noSend: noSend,
                  incoming: state.incomingAllocationTasks.length,
                  onBack: widget.onBack ?? () => Navigator.pop(context),
                ),
                Expanded(
                  child: Column(
                    children: [
                      _ModeSwitch(
                        mode: _mode,
                        outgoingCount: state.outgoingAllocationTasks.length,
                        incomingCount: state.incomingAllocationTasks.length,
                        onChanged: (value) {
                          setState(() => _mode = value);
                        },
                      ),
                      Expanded(
                        child: _mode == 'to_send'
                            ? (selectedBatch == null
                                  ? _BatchOverviewPage(
                                      batches: batches,
                                      incoming: false,
                                      onOpen: (id) {
                                        setState(() => _selectedBatchId = id);
                                      },
                                    )
                                  : _OutgoingWorkspace(
                                      selectedBatch: selectedBatch,
                                      rows: outgoing,
                                      rawRows: selectedOutgoing,
                                      filter: _outgoingFilter,
                                      branchFilter: _outgoingBranchFilter,
                                      branchOptions: outgoingBranchOptions,
                                      search: _search,
                                      searchController: _searchController,
                                      onBackToBatches: () {
                                        setState(() => _selectedBatchId = null);
                                      },
                                      onFilterChanged: (value) {
                                        setState(() => _outgoingFilter = value);
                                      },
                                      onBranchFilterChanged: (value) {
                                        setState(
                                          () => _outgoingBranchFilter = value,
                                        );
                                      },
                                      onSearchChanged: (value) {
                                        setState(() => _search = value);
                                      },
                                    ))
                            : (selectedIncomingBatch == null
                                  ? _BatchOverviewPage(
                                      batches: incomingBatches,
                                      incoming: true,
                                      onOpen: (id) {
                                        setState(
                                          () => _selectedIncomingBatchId = id,
                                        );
                                      },
                                    )
                                  : _IncomingWorkspace(
                                      selectedBatch: selectedIncomingBatch,
                                      rows: incoming,
                                      rawRows: selectedIncoming,
                                      filter: _incomingFilter,
                                      branchFilter: _incomingBranchFilter,
                                      branchOptions: incomingBranchOptions,
                                      search: _search,
                                      searchController: _searchController,
                                      onBackToBatches: () {
                                        setState(
                                          () => _selectedIncomingBatchId = null,
                                        );
                                      },
                                      onFilterChanged: (value) {
                                        setState(() => _incomingFilter = value);
                                      },
                                      onBranchFilterChanged: (value) {
                                        setState(
                                          () => _incomingBranchFilter = value,
                                        );
                                      },
                                      onSearchChanged: (value) {
                                        setState(() => _search = value);
                                      },
                                    )),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<BranchAllocationTask> _filterRows(
    List<BranchAllocationTask> rows,
    String filter, {
    required String branchFilter,
    required bool outgoing,
  }) {
    var result = rows;
    if (filter == 'pending') {
      result = result.where((task) => task.isSenderPending).toList();
    } else if (filter == 'confirmed') {
      result = result.where((task) => task.isSenderConfirmed).toList();
    } else if (filter == 'no_send') {
      result = result.where((task) => task.isNoSend).toList();
    }

    final selectedBranch = branchFilter.trim().toLowerCase();
    if (selectedBranch.isNotEmpty && selectedBranch != 'all') {
      result = result.where((task) {
        final branch = outgoing ? task.toBranch : task.fromBranch;
        return branch.trim().toLowerCase() == selectedBranch;
      }).toList();
    }

    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return result;

    return result.where((task) {
      return task.itemCode.toLowerCase().contains(query) ||
          task.itemName.toLowerCase().contains(query) ||
          task.toBranch.toLowerCase().contains(query) ||
          task.fromBranch.toLowerCase().contains(query);
    }).toList();
  }

  List<String> _branchOptions(
    List<BranchAllocationTask> rows, {
    required bool outgoing,
  }) {
    final branches =
        rows
            .map((task) => outgoing ? task.toBranch : task.fromBranch)
            .where((branch) => branch.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ['all', ...branches];
  }

  List<_AllocationBatch> _buildBatches(List<BranchAllocationTask> rows) {
    final grouped = <String, List<BranchAllocationTask>>{};
    for (final row in rows) {
      final key = row.batchId.trim().isEmpty ? row.runDate : row.batchId;
      grouped.putIfAbsent(key, () => []).add(row);
    }

    final batches = grouped.entries.map((entry) {
      final rows = [...entry.value]
        ..sort((a, b) {
          final toCompare = a.toBranch.compareTo(b.toBranch);
          if (toCompare != 0) return toCompare;
          return a.itemName.compareTo(b.itemName);
        });
      return _AllocationBatch(id: entry.key, rows: rows);
    }).toList();

    batches.sort((a, b) {
      final pendingCompare = b.pendingCount.compareTo(a.pendingCount);
      if (pendingCompare != 0) return pendingCompare;
      return b.latestSentAt.compareTo(a.latestSentAt);
    });

    return batches;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _AllocationBatch {
  final String id;
  final List<BranchAllocationTask> rows;

  const _AllocationBatch({required this.id, required this.rows});

  int get total => rows.length;
  int get pendingCount => rows.where((row) => row.isSenderPending).length;
  int get confirmedCount => rows.where((row) => row.isSenderConfirmed).length;
  int get noSendCount => rows.where((row) => row.isNoSend).length;
  bool get isReadyToFinish => total > 0 && pendingCount == 0;
  bool get isFinished => total > 0 && rows.every((row) => row.isBatchFinished);

  DateTime get latestSentAt {
    final dates = rows.map((row) => row.sentAt).whereType<DateTime>().toList()
      ..sort();
    return dates.isEmpty ? DateTime(2000) : dates.last;
  }

  String get title {
    if (id.isEmpty) return 'Allocation';
    return id;
  }
}

class _PageHeader extends StatelessWidget {
  final String branchName;
  final bool isLoading;
  final int pending;
  final int confirmed;
  final int noSend;
  final int incoming;
  final VoidCallback onBack;

  const _PageHeader({
    required this.branchName,
    required this.isLoading,
    required this.pending,
    required this.confirmed,
    required this.noSend,
    required this.incoming,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xff0EA5E9), Color(0xff2563EB)],
        ),
      ),
      child: Row(
        children: [
          IconButton.filled(
            onPressed: onBack,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: .18),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 14),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: .25)),
            ),
            child: const Icon(
              Icons.account_tree_rounded,
              color: Colors.white,
              size: 31,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$branchName Allocation',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Confirm what you prepared, reject what you cannot send, and keep notes clear.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .88),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              ),
            ),
          _MetricPill(label: 'Pending', value: pending, color: Colors.orange),
          _MetricPill(
            label: 'Confirmed',
            value: confirmed,
            color: Colors.green,
          ),
          _MetricPill(label: 'No Send', value: noSend, color: Colors.red),
          _MetricPill(label: 'Incoming', value: incoming, color: Colors.cyan),
        ],
      ),
    );
  }
}

class _ModeSwitch extends StatelessWidget {
  final String mode;
  final int outgoingCount;
  final int incomingCount;
  final ValueChanged<String> onChanged;

  const _ModeSwitch({
    required this.mode,
    required this.outgoingCount,
    required this.incomingCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 14, 18, 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xffD8E5F2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .035),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeCard(
              selected: mode == 'to_send',
              icon: Icons.outbound_rounded,
              title: 'To Send',
              subtitle: 'Items your branch must prepare',
              count: outgoingCount,
              color: const Color(0xffF59E0B),
              onTap: () => onChanged('to_send'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ModeCard(
              selected: mode == 'incoming',
              icon: Icons.move_to_inbox_rounded,
              title: 'Incoming',
              subtitle: 'Items other branches will send',
              count: incomingCount,
              color: const Color(0xff0EA5E9),
              onTap: () => onChanged('incoming'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  final Color color;
  final VoidCallback onTap;

  const _ModeCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: .11)
              : const Color(0xffF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: .55)
                : const Color(0xffE2E8F0),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: selected ? color : color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: selected ? Colors.white : color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: selected ? color : const Color(0xff0F172A),
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? color.withValues(alpha: .15)
                              : const Color(0xffE2E8F0),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          count.toString(),
                          style: TextStyle(
                            color: selected ? color : const Color(0xff475569),
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff64748B),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.chevron_right_rounded,
              color: selected ? color : const Color(0xff94A3B8),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutgoingWorkspace extends StatelessWidget {
  final _AllocationBatch selectedBatch;
  final List<BranchAllocationTask> rows;
  final List<BranchAllocationTask> rawRows;
  final String filter;
  final String branchFilter;
  final List<String> branchOptions;
  final String search;
  final TextEditingController searchController;
  final VoidCallback onBackToBatches;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<String> onBranchFilterChanged;
  final ValueChanged<String> onSearchChanged;

  const _OutgoingWorkspace({
    required this.selectedBatch,
    required this.rows,
    required this.rawRows,
    required this.filter,
    required this.branchFilter,
    required this.branchOptions,
    required this.search,
    required this.searchController,
    required this.onBackToBatches,
    required this.onFilterChanged,
    required this.onBranchFilterChanged,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          _ActionBar(
            rawRows: rawRows,
            visibleRows: rows,
            selectedBatch: selectedBatch,
            onBackToBatches: onBackToBatches,
            filter: filter,
            branchFilter: branchFilter,
            branchOptions: branchOptions,
            search: search,
            searchController: searchController,
            onFilterChanged: onFilterChanged,
            onBranchFilterChanged: onBranchFilterChanged,
            onSearchChanged: onSearchChanged,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: rows.isEmpty
                ? const _EmptyState(
                    title: 'No items in this view',
                    subtitle:
                        'Choose another allocation, filter, or search term.',
                  )
                : _OutgoingAllocationTable(rows: rows),
          ),
        ],
      ),
    );
  }
}

class _BatchOverviewPage extends StatelessWidget {
  final List<_AllocationBatch> batches;
  final bool incoming;
  final ValueChanged<String> onOpen;

  const _BatchOverviewPage({
    required this.batches,
    required this.incoming,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final pending = batches.where((batch) => !batch.isFinished).length;
    final finished = batches.where((batch) => batch.isFinished).length;
    final totalItems = batches.fold<int>(0, (sum, batch) => sum + batch.total);

    final title = incoming
        ? 'Incoming Allocation Batches'
        : 'Allocation Batches';
    final subtitle = incoming
        ? 'Open one incoming batch to see which branches will send items to you.'
        : 'Open one batch, review its items, and finish it when the branch is done.';
    final emptyTitle = incoming
        ? 'No incoming allocation batches'
        : 'No allocation batches';
    final emptySubtitle = incoming
        ? 'When other branches are assigned to send items to you, they will appear here.'
        : 'When inventory sends allocation, it will appear here.';

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xffD8E5F2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .035),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: incoming
                          ? const [Color(0xff22D3EE), Color(0xff0284C7)]
                          : const [Color(0xff38BDF8), Color(0xff2563EB)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    incoming
                        ? Icons.move_to_inbox_rounded
                        : Icons.dynamic_feed_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xff0F172A),
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xff64748B),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _OverviewStat(label: 'Batches', value: batches.length),
                const SizedBox(width: 10),
                _OverviewStat(label: 'Open', value: pending),
                const SizedBox(width: 10),
                _OverviewStat(label: 'Finished', value: finished),
                const SizedBox(width: 10),
                _OverviewStat(label: 'Items', value: totalItems),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: batches.isEmpty
                ? _EmptyState(title: emptyTitle, subtitle: emptySubtitle)
                : GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 620,
                          mainAxisExtent: 268,
                          crossAxisSpacing: 18,
                          mainAxisSpacing: 18,
                        ),
                    itemCount: batches.length,
                    itemBuilder: (context, index) {
                      final batch = batches[index];
                      return _BigBatchCard(
                        batch: batch,
                        incoming: incoming,
                        onTap: () => onOpen(batch.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _BigBatchCard extends StatelessWidget {
  final _AllocationBatch batch;
  final bool incoming;
  final VoidCallback onTap;

  const _BigBatchCard({
    required this.batch,
    required this.incoming,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = batch.isFinished
        ? const Color(0xff059669)
        : incoming
        ? const Color(0xff0284C7)
        : const Color(0xffD97706);
    final statusText = batch.isFinished
        ? (incoming ? 'Received' : 'Finished')
        : batch.isReadyToFinish
        ? (incoming ? 'Ready to receive' : 'Ready')
        : (incoming ? 'Incoming' : 'Pending');
    final cardBackground = incoming ? const Color(0xffF0F9FF) : Colors.white;
    final cardBorder = batch.isFinished
        ? const Color(0xffBBF7D0)
        : incoming
        ? const Color(0xff7DD3FC)
        : statusColor.withValues(alpha: .32);
    final progress = batch.total == 0
        ? 0.0
        : (batch.confirmedCount + batch.noSendCount) / batch.total;
    final branches = batch.rows
        .map((row) => incoming ? row.fromBranch : row.toBranch)
        .toSet()
        .length;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardBackground,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: cardBorder, width: incoming ? 1.6 : 1.3),
          boxShadow: [
            BoxShadow(
              color: statusColor.withValues(alpha: .08),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    batch.isFinished
                        ? Icons.check_circle_rounded
                        : incoming
                        ? Icons.move_to_inbox_rounded
                        : Icons.pending_actions_rounded,
                    color: statusColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        batch.title,
                        maxLines: 2,
                        overflow: TextOverflow.visible,
                        style: const TextStyle(
                          color: Color(0xff0F172A),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDateTime(batch.latestSentAt),
                        style: const TextStyle(
                          color: Color(0xff64748B),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: statusColor),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: statusColor.withValues(alpha: .2)),
              ),
              child: Row(
                children: [
                  Icon(
                    batch.isFinished
                        ? Icons.task_alt_rounded
                        : batch.isReadyToFinish
                        ? (incoming
                              ? Icons.inventory_2_rounded
                              : Icons.checklist_rtl_rounded)
                        : (incoming
                              ? Icons.local_shipping_rounded
                              : Icons.pending_actions_rounded),
                    color: statusColor,
                    size: 19,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    batch.isFinished
                        ? (incoming ? 'All items received' : 'Completed')
                        : batch.isReadyToFinish
                        ? (incoming
                              ? 'Sender finished this batch'
                              : 'Ready to finish')
                        : incoming
                        ? '${batch.pendingCount} waiting from sender'
                        : '${batch.pendingCount} pending item(s)',
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 9,
                backgroundColor: const Color(0xffE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _BatchMetric(label: 'Items', value: batch.total),
                _BatchMetric(
                  label: incoming ? 'Waiting' : 'Pending',
                  value: batch.pendingCount,
                ),
                _BatchMetric(
                  label: incoming ? 'Ready' : 'Confirmed',
                  value: batch.confirmedCount,
                ),
                _BatchMetric(label: 'No Send', value: batch.noSendCount),
                _BatchMetric(
                  label: incoming ? 'From Branches' : 'To Branches',
                  value: branches,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  final String label;
  final int value;

  const _OverviewStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xffF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xff64748B),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value.toString(),
            style: const TextStyle(
              color: Color(0xff0F172A),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final List<BranchAllocationTask> rawRows;
  final List<BranchAllocationTask> visibleRows;
  final _AllocationBatch? selectedBatch;
  final VoidCallback onBackToBatches;
  final String filter;
  final String branchFilter;
  final List<String> branchOptions;
  final String search;
  final TextEditingController searchController;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<String> onBranchFilterChanged;
  final ValueChanged<String> onSearchChanged;

  const _ActionBar({
    required this.rawRows,
    required this.visibleRows,
    required this.selectedBatch,
    required this.onBackToBatches,
    required this.filter,
    required this.branchFilter,
    required this.branchOptions,
    required this.search,
    required this.searchController,
    required this.onFilterChanged,
    required this.onBranchFilterChanged,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pending = rawRows.where((row) => row.isSenderPending).length;
    final done = rawRows.length - pending;
    final batch = selectedBatch;
    final statusColor = batch == null || batch.isFinished
        ? const Color(0xff059669)
        : batch.isReadyToFinish
        ? const Color(0xff2563EB)
        : const Color(0xffD97706);
    final statusText = batch == null || batch.isFinished
        ? 'Finished'
        : batch.isReadyToFinish
        ? 'Ready'
        : 'In progress';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xffD8E5F2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: onBackToBatches,
                tooltip: 'Back to batches',
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 10),
              Container(
                width: 70,
                height: 42,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.inventory_2_rounded, color: statusColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            batch?.title ?? 'Allocation',
                            maxLines: 2,
                            overflow: TextOverflow.visible,
                            style: const TextStyle(
                              color: Color(0xff0F172A),
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _SmallStatus(text: statusText, color: statusColor),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${rawRows.length} item(s) - $pending pending - sent ${batch == null ? '-' : _formatDateTime(batch.latestSentAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 4,
                child: TextField(
                  controller: searchController,
                  onChanged: onSearchChanged,
                  decoration: _inputDecoration(
                    'Search item, code, or receiving branch...',
                    icon: Icons.search_rounded,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _BranchFilterDropdown(
                value: branchFilter,
                branches: branchOptions,
                label: 'To Branch',
                onChanged: onBranchFilterChanged,
              ),
              const SizedBox(width: 12),
              _ProgressBox(total: rawRows.length, done: done),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: visibleRows.isEmpty
                    ? null
                    : () => _exportAllocationRows(
                        context,
                        rows: visibleRows,
                        mode: 'outgoing',
                        title: selectedBatch?.title ?? 'Allocation',
                      ),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Export'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xff0F766E),
                  side: const BorderSide(color: Color(0xff99F6E4)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _FilterChipButton(
                label: 'All',
                value: 'all',
                current: filter,
                onChanged: onFilterChanged,
              ),
              const SizedBox(width: 8),
              _FilterChipButton(
                label: 'Pending',
                value: 'pending',
                current: filter,
                onChanged: onFilterChanged,
              ),
              const SizedBox(width: 8),
              _FilterChipButton(
                label: 'Confirmed',
                value: 'confirmed',
                current: filter,
                onChanged: onFilterChanged,
              ),
              const SizedBox(width: 8),
              _FilterChipButton(
                label: 'No Send',
                value: 'no_send',
                current: filter,
                onChanged: onFilterChanged,
              ),
              const Spacer(),
              Text(
                '${visibleRows.length} visible / ${rawRows.length} total',
                style: const TextStyle(
                  color: Color(0xff64748B),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OutgoingAllocationTable extends StatelessWidget {
  final List<BranchAllocationTask> rows;

  const _OutgoingAllocationTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final branchColors = _branchColors(rows.map((row) => row.toBranch).toSet());

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xffD8E5F2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 52,
            color: const Color(0xffEAF3FF),
            child: const Row(
              children: [
                _HeaderCell(width: 50, text: '#'),
                _HeaderCell(flex: 2, text: 'Item'),
                _HeaderCell(width: 190, text: 'To Branch'),
                _HeaderCell(width: 92, text: 'Qty Send'),
                _HeaderCell(width: 120, text: 'Edit Qty'),
                _HeaderCell(width: 360, text: 'Note'),
                _HeaderCell(width: 275, text: 'Action'),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                return _OutgoingTableRow(
                  key: ValueKey('${row.id}-${row.senderStatus}-${row.qtySend}'),
                  index: index + 1,
                  task: row,
                  branchColor:
                      branchColors[row.toBranch] ?? const Color(0xffF8FAFC),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Map<String, Color> _branchColors(Set<String> branches) {
    const colors = [
      Color(0xffEFF6FF),
      Color(0xffF0FDF4),
      Color(0xffFFF7ED),
      Color(0xffFDF2F8),
      Color(0xffF5F3FF),
      Color(0xffECFEFF),
      Color(0xffFEFCE8),
    ];
    final result = <String, Color>{};
    var index = 0;
    final sorted = branches.toList()..sort();
    for (final branch in sorted) {
      result[branch] = colors[index % colors.length];
      index++;
    }
    return result;
  }
}

class _OutgoingTableRow extends StatefulWidget {
  final int index;
  final BranchAllocationTask task;
  final Color branchColor;

  const _OutgoingTableRow({
    super.key,
    required this.index,
    required this.task,
    required this.branchColor,
  });

  @override
  State<_OutgoingTableRow> createState() => _OutgoingTableRowState();
}

class _OutgoingTableRowState extends State<_OutgoingTableRow> {
  late final TextEditingController _qtyController;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(
      text: _formatNum(widget.task.qtySend),
    );
    _noteController = TextEditingController(text: widget.task.senderNote);
  }

  @override
  void didUpdateWidget(covariant _OutgoingTableRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task != widget.task) {
      _qtyController.text = _formatNum(widget.task.qtySend);
      _noteController.text = widget.task.senderNote;
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;

    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xffE2E8F0))),
      ),
      child: Row(
        children: [
          _BodyCell(
            width: 50,
            child: Center(
              child: Text(
                widget.index.toString(),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          _BodyCell(flex: 2, child: _ItemBlock(task: task)),
          _BodyCell(
            width: 190,
            color: widget.branchColor,
            child: Text(
              task.toBranch,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff0F172A),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _BodyCell(
            width: 92,
            child: Center(child: _QtyPill(value: _formatNum(task.qty))),
          ),
          _BodyCell(
            width: 120,
            child: TextField(
              controller: _qtyController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              onChanged: (_) => setState(() {}),
              decoration: _compactInput(),
            ),
          ),
          _BodyCell(
            width: 360,
            child: TextField(
              controller: _noteController,
              minLines: 1,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: _compactInput(
                hint: task.isNoSend
                    ? 'Reject reason'
                    : 'Note required only if qty changed or rejected',
              ),
            ),
          ),
          _BodyCell(
            width: 275,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (task.isSenderDone) ...[
                  _StatusBadge(task: task),
                  if (_hasUnsavedChanges) ...[
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _saveDoneChanges(context),
                      icon: const Icon(Icons.save_rounded, size: 17),
                      label: const Text('Save Note'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xff0F766E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 13,
                        ),
                        minimumSize: const Size(106, 42),
                      ),
                    ),
                  ],
                ],
                if (!task.isSenderDone) ...[
                  FilledButton.icon(
                    onPressed: () => _confirm(context),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Confirm'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xff059669),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      minimumSize: const Size(112, 44),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _reject(context),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xffDC2626),
                      side: const BorderSide(color: Color(0xffFCA5A5)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      minimumSize: const Size(104, 44),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasUnsavedChanges {
    final qty = num.tryParse(_qtyController.text.trim().replaceAll(',', ''));
    final note = _noteController.text.trim();
    return qty != widget.task.qtySend || note != widget.task.senderNote.trim();
  }

  void _confirm(BuildContext context) {
    final qty = num.tryParse(_qtyController.text.trim().replaceAll(',', ''));
    final note = _noteController.text.trim();
    if (qty == null || qty < 0) {
      _showMessage(context, 'Enter a valid quantity before confirming.', false);
      return;
    }
    if (qty == 0) {
      if (note.isEmpty) {
        _showMessage(context, 'Rejected items require a clear note.', false);
        return;
      }
      context.read<OrdersBloc>().add(
        OrdersSaveBranchAllocationTask(
          id: widget.task.id,
          qtySend: 0,
          senderStatus: 'rejected',
          senderNote: note,
        ),
      );
      _showMessage(context, 'Item rejected with note.', true);
      return;
    }
    if (qty != widget.task.qty && note.isEmpty) {
      _showMessage(context, 'Quantity changes require a note.', false);
      return;
    }

    context.read<OrdersBloc>().add(
      OrdersSaveBranchAllocationTask(
        id: widget.task.id,
        qtySend: qty,
        senderStatus: 'confirmed',
        senderNote: note,
      ),
    );
    _showMessage(context, 'Item confirmed.', true);
  }

  void _saveDoneChanges(BuildContext context) {
    final qty = num.tryParse(_qtyController.text.trim().replaceAll(',', ''));
    final note = _noteController.text.trim();
    final currentStatus = widget.task.normalizedSenderStatus;
    final status = qty == 0 ? 'rejected' : currentStatus;

    if (qty == null || qty < 0) {
      _showMessage(context, 'Enter a valid quantity before saving.', false);
      return;
    }
    if ((status == 'no_send' || status == 'rejected' || status == 'reject') &&
        note.isEmpty) {
      _showMessage(context, 'Rejected items require a clear note.', false);
      return;
    }
    if (qty != widget.task.qty && note.isEmpty) {
      _showMessage(context, 'Quantity changes require a note.', false);
      return;
    }

    context.read<OrdersBloc>().add(
      OrdersSaveBranchAllocationTask(
        id: widget.task.id,
        qtySend: qty,
        senderStatus: status,
        senderNote: note,
      ),
    );
    _showMessage(context, 'Allocation note saved.', true);
  }

  void _reject(BuildContext context) {
    final note = _noteController.text.trim();
    if (note.isEmpty) {
      _showMessage(context, 'Reject requires a clear note.', false);
      return;
    }

    _qtyController.text = '0';
    context.read<OrdersBloc>().add(
      OrdersSaveBranchAllocationTask(
        id: widget.task.id,
        qtySend: 0,
        senderStatus: 'rejected',
        senderNote: note,
      ),
    );
    _showMessage(context, 'Item rejected with note.', true);
  }
}

class _IncomingWorkspace extends StatelessWidget {
  final _AllocationBatch selectedBatch;
  final List<BranchAllocationTask> rows;
  final List<BranchAllocationTask> rawRows;
  final String filter;
  final String branchFilter;
  final List<String> branchOptions;
  final String search;
  final TextEditingController searchController;
  final VoidCallback onBackToBatches;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<String> onBranchFilterChanged;
  final ValueChanged<String> onSearchChanged;

  const _IncomingWorkspace({
    required this.selectedBatch,
    required this.rows,
    required this.rawRows,
    required this.filter,
    required this.branchFilter,
    required this.branchOptions,
    required this.search,
    required this.searchController,
    required this.onBackToBatches,
    required this.onFilterChanged,
    required this.onBranchFilterChanged,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    final done = rawRows.where((row) => row.isSenderDone).length;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xffD8E5F2)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: onBackToBatches,
                      tooltip: 'Back to incoming batches',
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      width: 56,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xffE0F2FE),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.move_to_inbox_rounded,
                        color: Color(0xff0284C7),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedBatch.title,
                            maxLines: 2,
                            overflow: TextOverflow.visible,
                            style: const TextStyle(
                              color: Color(0xff0F172A),
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${rawRows.length} incoming item(s) - $done completed - sent ${_formatDateTime(selectedBatch.latestSentAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xff64748B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: TextField(
                        controller: searchController,
                        onChanged: onSearchChanged,
                        decoration: _inputDecoration(
                          'Search item, code, or sending branch...',
                          icon: Icons.search_rounded,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _BranchFilterDropdown(
                      value: branchFilter,
                      branches: branchOptions,
                      label: 'From Branch',
                      onChanged: onBranchFilterChanged,
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: rows.isEmpty
                          ? null
                          : () => _exportAllocationRows(
                              context,
                              rows: rows,
                              mode: 'incoming',
                              title: selectedBatch.title,
                            ),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Export'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xff0284C7),
                        side: const BorderSide(color: Color(0xffBAE6FD)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _FilterChipButton(
                      label: 'All',
                      value: 'all',
                      current: filter,
                      onChanged: onFilterChanged,
                    ),
                    const SizedBox(width: 8),
                    _FilterChipButton(
                      label: 'Pending',
                      value: 'pending',
                      current: filter,
                      onChanged: onFilterChanged,
                    ),
                    const SizedBox(width: 8),
                    _FilterChipButton(
                      label: 'Confirmed',
                      value: 'confirmed',
                      current: filter,
                      onChanged: onFilterChanged,
                    ),
                    const SizedBox(width: 8),
                    _FilterChipButton(
                      label: 'No Send',
                      value: 'no_send',
                      current: filter,
                      onChanged: onFilterChanged,
                    ),
                    const Spacer(),
                    Text(
                      '${rows.length} visible / ${rawRows.length} total',
                      style: const TextStyle(
                        color: Color(0xff64748B),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: rows.isEmpty
                ? const _EmptyState(
                    title: 'No incoming allocation items',
                    subtitle:
                        'Items other branches send to you will appear here.',
                  )
                : _IncomingTable(rows: rows),
          ),
        ],
      ),
    );
  }
}

class _IncomingTable extends StatelessWidget {
  final List<BranchAllocationTask> rows;

  const _IncomingTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    final sorted = [...rows]
      ..sort((a, b) {
        final fromCompare = a.fromBranch.compareTo(b.fromBranch);
        if (fromCompare != 0) return fromCompare;
        return a.itemName.compareTo(b.itemName);
      });

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xffD8E5F2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 52,
            color: const Color(0xffEAF3FF),
            child: const Row(
              children: [
                _HeaderCell(width: 50, text: '#'),
                _HeaderCell(flex: 2, text: 'Item'),
                _HeaderCell(width: 190, text: 'From Branch'),
                _HeaderCell(width: 90, text: 'Qty Send'),
                _HeaderCell(width: 90, text: 'Final Qty'),
                _HeaderCell(width: 130, text: 'Status'),
                _HeaderCell(flex: 2, text: 'Sender Note'),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: sorted.length,
              itemBuilder: (context, index) {
                final task = sorted[index];
                return Container(
                  constraints: const BoxConstraints(minHeight: 70),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xffE2E8F0)),
                    ),
                  ),
                  child: Row(
                    children: [
                      _BodyCell(
                        width: 50,
                        child: Center(child: Text('${index + 1}')),
                      ),
                      _BodyCell(flex: 2, child: _ItemBlock(task: task)),
                      _BodyCell(
                        width: 190,
                        color: const Color(0xffEFF6FF),
                        child: Text(
                          task.fromBranch,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      _BodyCell(
                        width: 90,
                        child: Center(child: Text(_formatNum(task.qty))),
                      ),
                      _BodyCell(
                        width: 90,
                        child: Center(child: Text(_formatNum(task.qtySend))),
                      ),
                      _BodyCell(width: 130, child: _StatusBadge(task: task)),
                      _BodyCell(
                        flex: 2,
                        child: Text(
                          task.senderNote.trim().isEmpty
                              ? '-'
                              : task.senderNote,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xff475569)),
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
  }
}

class _HeaderCell extends StatelessWidget {
  final String text;
  final double? width;
  final int flex;

  const _HeaderCell({required this.text, this.width, this.flex = 1});

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xff334155),
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
    if (width != null) return SizedBox(width: width, child: child);
    return Expanded(flex: flex, child: child);
  }
}

class _BodyCell extends StatelessWidget {
  final Widget child;
  final double? width;
  final int flex;
  final Color? color;

  const _BodyCell({required this.child, this.width, this.flex = 1, this.color});

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      color: color,
      alignment: Alignment.centerLeft,
      child: child,
    );
    if (width != null) return SizedBox(width: width, child: content);
    return Expanded(flex: flex, child: content);
  }
}

class _ItemBlock extends StatelessWidget {
  final BranchAllocationTask task;

  const _ItemBlock({required this.task});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          task.itemName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xff0F172A),
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          task.itemCode,
          style: const TextStyle(
            color: Color(0xff64748B),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _QtyPill extends StatelessWidget {
  final String value;

  const _QtyPill({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xffF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffE2E8F0)),
      ),
      child: Text(
        value,
        style: const TextStyle(
          color: Color(0xff0F172A),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final BranchAllocationTask task;

  const _StatusBadge({required this.task});

  @override
  Widget build(BuildContext context) {
    final text = task.isNoSend
        ? 'REJECTED'
        : task.isSenderConfirmed
        ? 'CONFIRMED'
        : 'PENDING';
    final color = task.isNoSend
        ? const Color(0xffDC2626)
        : task.isSenderConfirmed
        ? const Color(0xff059669)
        : const Color(0xffD97706);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ProgressBox extends StatelessWidget {
  final int total;
  final int done;

  const _ProgressBox({required this.total, required this.done});

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : done / total;
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xffF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$done / $total completed',
            style: const TextStyle(
              color: Color(0xff0F172A),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: ratio,
              color: const Color(0xff059669),
              backgroundColor: const Color(0xffE2E8F0),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final ValueChanged<String> onChanged;

  const _FilterChipButton({
    required this.label,
    required this.value,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == current;
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      selectedColor: const Color(0xffDBEAFE),
      labelStyle: TextStyle(
        color: selected ? const Color(0xff1D4ED8) : const Color(0xff64748B),
        fontWeight: FontWeight.w900,
      ),
      onSelected: (_) => onChanged(value),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xffD8E5F2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: Color(0xff94A3B8),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xff0F172A),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xff64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _MetricPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: .25)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .86),
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            value.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyBadge extends StatelessWidget {
  final String value;
  final Color color;

  const _TinyBadge({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _BranchFilterDropdown extends StatelessWidget {
  final String value;
  final List<String> branches;
  final String label;
  final ValueChanged<String> onChanged;

  const _BranchFilterDropdown({
    required this.value,
    required this.branches,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final options = branches.isEmpty ? const ['all'] : branches;
    final selected = options.contains(value) ? value : 'all';

    return SizedBox(
      width: 230,
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        isExpanded: true,
        decoration: _inputDecoration(label, icon: Icons.storefront_rounded),
        items: options.map((branch) {
          return DropdownMenuItem<String>(
            value: branch,
            child: Text(
              branch == 'all' ? 'All Branches' : branch,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          );
        }).toList(),
        onChanged: (branch) {
          if (branch == null) return;
          onChanged(branch);
        },
      ),
    );
  }
}

class _SmallStatus extends StatelessWidget {
  final String text;
  final Color color;

  const _SmallStatus({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _BatchMetric extends StatelessWidget {
  final String label;
  final int value;

  const _BatchMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xffF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value.toString(),
            style: const TextStyle(
              color: Color(0xff0F172A),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xff64748B),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _inputDecoration(String label, {IconData? icon}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: icon == null ? null : Icon(icon),
    filled: true,
    fillColor: const Color(0xffF8FAFC),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xffCBD5E1)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xffCBD5E1)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xff0EA5E9), width: 1.4),
    ),
  );
}

InputDecoration _compactInput({String? hint}) {
  return InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: const Color(0xffF8FAFC),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xffCBD5E1)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xffCBD5E1)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xff0EA5E9), width: 1.4),
    ),
  );
}

String _formatNum(num value) {
  if (value % 1 == 0) return value.toInt().toString();
  return value.toString();
}

String _formatDateTime(DateTime date) {
  final d = date.toLocal();
  final day = d.day.toString().padLeft(2, '0');
  final month = d.month.toString().padLeft(2, '0');
  final hour = d.hour.toString().padLeft(2, '0');
  final minute = d.minute.toString().padLeft(2, '0');
  return '$day-$month-${d.year} $hour:$minute';
}

Future<void> _exportAllocationRows(
  BuildContext context, {
  required List<BranchAllocationTask> rows,
  required String mode,
  required String title,
}) async {
  try {
    final branchName = context.read<OrdersBloc>().state.branchName;
    await BranchAllocationExcelExporter.export(
      rows: rows,
      mode: mode,
      branchName: branchName,
      title: title,
    );
    if (!context.mounted) return;
    _showMessage(context, 'Allocation export downloaded.', true);
  } catch (e) {
    if (!context.mounted) return;
    _showMessage(context, 'Export failed: $e', false);
  }
}

void _showMessage(BuildContext context, String message, bool success) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success
            ? const Color(0xff059669)
            : const Color(0xffDC2626),
        behavior: SnackBarBehavior.floating,
      ),
    );
}
