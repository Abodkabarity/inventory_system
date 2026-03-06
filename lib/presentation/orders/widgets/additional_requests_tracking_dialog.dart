import 'package:daily_order/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/order_bloc/orders_bloc.dart';
import '../bloc/order_bloc/orders_event.dart';
import '../bloc/order_bloc/orders_state.dart';
import 'additional_requests_tracking_cubit.dart';

enum _TrackKey { pending, sent, done, rejected, unknown }

class AdditionalTrackingDialog extends StatelessWidget {
  const AdditionalTrackingDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => TrackingFilterCubit(),
      child: const _DialogBody(),
    );
  }
}

class _DialogBody extends StatefulWidget {
  const _DialogBody();

  @override
  State<_DialogBody> createState() => _DialogBodyState();
}

class _DialogBodyState extends State<_DialogBody> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  _TrackKey _keyOfStatus(String statusRaw) {
    final s = statusRaw.trim().toLowerCase();

    // Pending variants
    if (s == 'pending' ||
        s == 'pending_inventory' ||
        s == 'pending_for_inventory' ||
        s == 'pending_for_inventory_approval') {
      return _TrackKey.pending;
    }

    // Sent variants
    if (s == 'sent' || s == 'sent_to_store' || s == 'sent_store') {
      return _TrackKey.sent;
    }

    // Done variants
    if (s == 'done' || s == 'completed' || s == 'fulfilled') {
      return _TrackKey.done;
    }

    // Rejected variants
    if (s == 'rejected' || s == 'reject' || s == 'declined') {
      return _TrackKey.rejected;
    }

    return _TrackKey.unknown;
  }

  bool _matchTab(AdditionalRequestRow r, TrackTab tab) {
    final k = _keyOfStatus(r.status);

    switch (tab) {
      case TrackTab.all:
        return true;
      case TrackTab.pending:
        return k == _TrackKey.pending;
      case TrackTab.sent:
        return k == _TrackKey.sent;
      case TrackTab.done:
        return k == _TrackKey.done;
      case TrackTab.rejected:
        return k == _TrackKey.rejected;
    }
  }

  bool _matchQuery(AdditionalRequestRow r, String qLower) {
    if (qLower.trim().isEmpty) return true;

    final code = r.itemCode.toLowerCase();
    final name = r.itemName.toLowerCase();
    final reason = r.reason.toLowerCase();
    final note = (r.storeNote ?? '').toLowerCase();

    return code.contains(qLower) ||
        name.contains(qLower) ||
        reason.contains(qLower) ||
        note.contains(qLower);
  }

  _TabCounts _computeCounts(List<AdditionalRequestRow> rows) {
    int p = 0, s = 0, d = 0, rj = 0;

    for (final x in rows) {
      final k = _keyOfStatus(x.status);
      if (k == _TrackKey.pending) p++;
      if (k == _TrackKey.sent) s++;
      if (k == _TrackKey.done) d++;
      if (k == _TrackKey.rejected) rj++;
    }

    return _TabCounts(
      all: rows.length,
      pending: p,
      sent: s,
      done: d,
      rejected: rj,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: .55)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .08),
              blurRadius: 30,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: BlocBuilder<OrdersBloc, OrdersState>(
          buildWhen: (p, n) =>
              p.additionalTrackingRows != n.additionalTrackingRows ||
              p.status != n.status ||
              p.trackingModifiedQty != n.trackingModifiedQty,
          builder: (context, s) {
            return BlocBuilder<TrackingFilterCubit, TrackingFilterState>(
              builder: (context, fs) {
                final base = s.additionalTrackingRows;
                final counts = _computeCounts(base);
                final qLower = fs.query.toLowerCase().trim();

                final filtered = base
                    .where((r) => _matchTab(r, fs.tab))
                    .where((r) => _matchQuery(r, qLower))
                    .toList();

                return Column(
                  children: [
                    _TrackHeader(
                      title: 'Additional Requests Tracking',
                      subtitle: 'Status, fulfilled quantity, and store notes',
                      onClose: () => Navigator.of(context).pop(),
                      onRefresh: () => context.read<OrdersBloc>().add(
                        const OrdersLoadAdditionalTracking(),
                      ),
                      total: counts.all,
                      pending: counts.pending,
                      sent: counts.sent,
                      done: counts.done,
                      rejected: counts.rejected,
                      modified: s.trackingModifiedQty,
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              onChanged: (v) => context
                                  .read<TrackingFilterCubit>()
                                  .setQuery(v),
                              decoration: InputDecoration(
                                hintText: 'Search item code / name / reason...',
                                prefixIcon: const Icon(Icons.search),
                                suffixIcon: fs.query.trim().isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Clear',
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          context
                                              .read<TrackingFilterCubit>()
                                              .clearQuery();
                                        },
                                        icon: const Icon(Icons.close),
                                      ),
                                filled: true,
                                fillColor: AppColors.backgroundWidget,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: AppColors.primaryColor,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _TabPills(
                            tab: fs.tab,
                            onChanged: (t) =>
                                context.read<TrackingFilterCubit>().setTab(t),
                            counts: counts,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: filtered.isEmpty
                          ? const _EmptyTrack()
                          : ListView.separated(
                              padding: const EdgeInsets.all(14),
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final r = filtered[i];
                                return _TrackRowCard(row: r);
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _TrackHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final VoidCallback onRefresh;

  final int total;
  final int pending;
  final int sent;
  final int done;
  final int rejected;
  final int modified;

  const _TrackHeader({
    required this.title,
    required this.subtitle,
    required this.onClose,
    required this.onRefresh,
    required this.total,
    required this.pending,
    required this.sent,
    required this.done,
    required this.rejected,
    required this.modified,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MiniStat(
                      label: 'Total',
                      value: '$total',
                      bg: const Color(0xFFF3F4F6),
                    ),
                    _MiniStat(
                      label: 'Pending',
                      value: '$pending',
                      bg: const Color(0xFFFFFBEB),
                      fg: const Color(0xFF92400E),
                    ),
                    _MiniStat(
                      label: 'Sent',
                      value: '$sent',
                      bg: const Color(0xFFEFF6FF),
                      fg: const Color(0xFF1D4ED8),
                    ),
                    _MiniStat(
                      label: 'Done',
                      value: '$done',
                      bg: const Color(0xFFECFDF3),
                      fg: const Color(0xFF027A48),
                    ),
                    _MiniStat(
                      label: 'Rejected',
                      value: '$rejected',
                      bg: const Color(0xFFFEF2F2),
                      fg: const Color(0xFFB91C1C),
                    ),
                    if (modified > 0)
                      _MiniStat(
                        label: 'Qty changed',
                        value: '$modified',
                        bg: const Color(0xFFF3F0FF),
                        fg: const Color(0xFF5B21B6),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          IconButton(
            tooltip: 'Refresh',
            onPressed: onRefresh,
            icon: Icon(Icons.refresh, color: AppColors.secondaryColor),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: onClose,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color bg;
  final Color fg;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.bg,
    this.fg = const Color(0xFF111827),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabCounts {
  final int all;
  final int pending;
  final int sent;
  final int done;
  final int rejected;

  const _TabCounts({
    required this.all,
    required this.pending,
    required this.sent,
    required this.done,
    required this.rejected,
  });
}

class _TabPills extends StatelessWidget {
  final TrackTab tab;
  final ValueChanged<TrackTab> onChanged;
  final _TabCounts counts;

  const _TabPills({
    required this.tab,
    required this.onChanged,
    required this.counts,
  });

  @override
  Widget build(BuildContext context) {
    Widget pill({
      required String text,
      required bool active,
      required VoidCallback onTap,
      Color? activeBg,
      Color? activeFg,
      int? count,
    }) {
      final bg = active
          ? (activeBg ?? const Color(0xFFEEF2FF))
          : const Color(0xFFF9FAFB);
      final fg = active
          ? (activeFg ?? const Color(0xFF4338CA))
          : const Color(0xFF111827);

      return InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFE6E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                text,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: fg,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white.withValues(alpha: .85)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFE6E8F0)),
                  ),
                  child: Text(
                    count.toString(),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        pill(
          text: 'All',
          active: tab == TrackTab.all,
          count: counts.all,
          activeFg: AppColors.primaryColor,
          onTap: () => onChanged(TrackTab.all),
        ),
        pill(
          text: 'Pending',
          active: tab == TrackTab.pending,
          count: counts.pending,
          activeBg: const Color(0xFFFFFBEB),
          activeFg: const Color(0xFF92400E),
          onTap: () => onChanged(TrackTab.pending),
        ),
        pill(
          text: 'Sent',
          active: tab == TrackTab.sent,
          count: counts.sent,
          activeBg: const Color(0xFFEFF6FF),
          activeFg: const Color(0xFF1D4ED8),
          onTap: () => onChanged(TrackTab.sent),
        ),
        pill(
          text: 'Done',
          active: tab == TrackTab.done,
          count: counts.done,
          activeBg: const Color(0xFFECFDF3),
          activeFg: const Color(0xFF027A48),
          onTap: () => onChanged(TrackTab.done),
        ),
        pill(
          text: 'Rejected',
          active: tab == TrackTab.rejected,
          count: counts.rejected,
          activeBg: const Color(0xFFFEF2F2),
          activeFg: const Color(0xFFB91C1C),
          onTap: () => onChanged(TrackTab.rejected),
        ),
      ],
    );
  }
}

class _EmptyTrack extends StatelessWidget {
  const _EmptyTrack();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 42, color: Color(0xFF9CA3AF)),
          SizedBox(height: 10),
          Text(
            'No tracking rows',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Send additional requests to see them here.',
            style: TextStyle(color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

class _TrackRowCard extends StatelessWidget {
  final AdditionalRequestRow row;
  const _TrackRowCard({required this.row});

  String _fmtDt(DateTime? d) {
    if (d == null) return '-';
    final yy = d.year.toString().padLeft(4, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$yy-$mm-$dd $hh:$mi';
  }

  ({Color bg, Color fg, String label, IconData icon}) _statusStyle(
    String status,
  ) {
    final s = status.trim().toLowerCase();

    if (s == 'pending_inventory' ||
        s == 'pending' ||
        s == 'pending_for_inventory_approval') {
      return (
        bg: const Color(0xFFFFFBEB),
        fg: const Color(0xFF92400E),
        label: 'Pending For Inventory Approval',
        icon: Icons.hourglass_bottom,
      );
    }

    if (s == 'sent_to_store' || s == 'sent') {
      return (
        bg: const Color(0xFFEFF6FF),
        fg: const Color(0xFF1D4ED8),
        label: 'Sent To Store',
        icon: Icons.local_shipping_outlined,
      );
    }

    if (s == 'done') {
      return (
        bg: const Color(0xFFECFDF3),
        fg: const Color(0xFF027A48),
        label: 'Done',
        icon: Icons.check_circle_outline,
      );
    }

    if (s == 'rejected' || s == 'reject') {
      return (
        bg: const Color(0xFFFEF2F2),
        fg: const Color(0xFFB91C1C),
        label: 'Rejected',
        icon: Icons.cancel_outlined,
      );
    }

    return (
      bg: const Color(0xFFF3F4F6),
      fg: const Color(0xFF111827),
      label: status,
      icon: Icons.info_outline,
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = _statusStyle(row.status);
    final requested = row.requestQty;
    final fulfilled = row.fulfilledQty;

    final qtyLine = (fulfilled == null)
        ? 'Requested: $requested'
        : (fulfilled == requested
              ? 'Requested: $requested  •  Fulfilled: $fulfilled'
              : 'Requested: $requested  •  Fulfilled: $fulfilled (changed)');

    final changedQty = row.isModifiedQty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .03),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: st.bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE6E8F0)),
            ),
            child: Icon(st.icon, color: st.fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      row.itemCode,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: st.bg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFE6E8F0)),
                      ),
                      child: Text(
                        st.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: st.fg,
                        ),
                      ),
                    ),
                    if (changedQty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F0FF),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFE6E8F0)),
                        ),
                        child: const Text(
                          'Qty changed',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF5B21B6),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  row.itemName,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  qtyLine,
                  style: const TextStyle(
                    fontSize: 12.2,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 6),
                if (row.reason.trim().isNotEmpty)
                  Text(
                    'Reason: ${row.reason}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if ((row.storeNote ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Store note: ${row.storeNote}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF374151),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _MetaChip(label: 'Created', value: _fmtDt(row.createdAt)),
                    _MetaChip(label: 'Sent', value: _fmtDt(row.sentToStoreAt)),
                    _MetaChip(label: 'Done', value: _fmtDt(row.doneAt)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetaChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label:',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }
}
