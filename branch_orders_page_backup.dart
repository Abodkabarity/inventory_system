/*
// branch_orders_page.dart
// Full file. No Arabic inside code.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/daily_order_row.dart';
import '../bloc/order_bloc/orders_bloc.dart';
import '../bloc/order_bloc/orders_bloc_factory.dart';
import '../bloc/order_bloc/orders_event.dart';
import '../bloc/order_bloc/orders_state.dart';
import '../final_reorder/widgets/final_reorder_side_panel.dart';
import '../widgets/additional_request_side_panel.dart';
import '../widgets/orders_grid_controller.dart';
import '../widgets/orders_table.dart';
import '../widgets/orders_toolbar.dart';
import '../widgets/review_changes_dialog.dart';
import 'branch_widgets/columns_panel.dart';

class BranchOrdersPage extends StatelessWidget {
  final String runDate;
  final String branchName;

  const BranchOrdersPage({
    super.key,
    required this.runDate,
    required this.branchName,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          OrdersBlocFactory.create(runDate: runDate, branchName: branchName),
      child: _BranchOrdersView(branchName: branchName),
    );
  }
}

class _BranchOrdersView extends StatefulWidget {
  final String branchName;
  const _BranchOrdersView({required this.branchName});

  @override
  State<_BranchOrdersView> createState() => _BranchOrdersViewState();
}

class _BranchOrdersViewState extends State<_BranchOrdersView> {
  late final OrdersGridController _grid;

  String? _zone;
  bool _loadingZone = false;

  @override
  void initState() {
    super.initState();
    _grid = OrdersGridController();
    _loadZoneOnce();
  }

  Future<void> _loadZoneOnce() async {
    if (_loadingZone) return;
    _loadingZone = true;

    try {
      final client = Supabase.instance.client;

      final res = await client
          .from('branches')
          .select('zone')
          .eq('branch_name', widget.branchName)
          .maybeSingle();

      final z = (res == null) ? '' : (res['zone'] ?? '').toString().trim();
      if (!mounted) return;
      setState(() => _zone = z.isEmpty ? null : z);
    } catch (_) {
      if (!mounted) return;
      setState(() => _zone = null);
    } finally {
      _loadingZone = false;
    }
  }

  List<String> _orderedVisibleColumns(OrdersState s) {
    final order = s.columnOrder;
    final visible = s.visibleColumns;

    final out = <String>[];

    if (!out.contains('row_no')) out.add('row_no');

    for (final k in order) {
      if (visible.contains(k)) out.add(k);
    }

    if (!out.contains('item_code')) out.insert(1, 'item_code');
    if (!out.contains('item_name')) out.insert(2, 'item_name');

    return out;
  }

  Future<void> _openTrackingDialog(BuildContext context) async {
    // خذي نفس البلوك من الصفحة
    final bloc = context.read<OrdersBloc>();

    // Refresh tracking before showing
    bloc.add(const OrdersLoadAdditionalTracking());

    await showDialog(
      context: context,
      useRootNavigator: false,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return BlocProvider.value(
          value: bloc,
          child: const AdditionalTrackingDialog(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OrdersBloc, OrdersState>(
      builder: (context, s) {
        final isBusy = s.isBusy;

        final statsAll = _calcStats(s.rows);
        final categories = _extractCategories(s.rows);
        final orderedColumns = _orderedVisibleColumns(s);

        final zoneReady = (_zone != null && _zone!.trim().isNotEmpty);

        final draftAddCount = s.additionalCount;
        final sentAddCount = s.sentAdditionalQtyByItemCode.length;

        return Scaffold(
          backgroundColor: const Color(0xFFF6F7FB),
          endDrawer: const ColumnsPanel(),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TopHeader(
                    title: widget.branchName,
                    subtitle: 'Orders • ${s.runDate}',
                    right: Row(
                      children: [
                        _StatusChip(isSubmitted: s.isSubmitted),
                        const SizedBox(width: 10),
                        _ZoneChip(zone: _zone),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (s.isInitial)
                    Expanded(
                      child: Center(
                        child: _GenerateCard(
                          isBusy: isBusy,
                          progress: s.progress,
                          message: s.progressMessage,
                          error: s.status == OrdersStatus.failure
                              ? s.error
                              : null,
                          onGenerate: () => context.read<OrdersBloc>().add(
                            const OrdersPressedGenerate(),
                          ),
                        ),
                      ),
                    )
                  else ...[
                    if (s.status == OrdersStatus.generating ||
                        s.status == OrdersStatus.loading)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ProgressStrip(
                          progress: s.progress,
                          message: s.progressMessage ?? 'Working...',
                        ),
                      ),
                    if (s.status == OrdersStatus.failure && s.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          s.error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 320,
                          child: _KpiCard(
                            title: 'Total Products',
                            value: _formatInt(statsAll.totalProducts),
                            subtitle: 'All items loaded for this branch',
                            icon: Icons.list_alt_outlined,
                          ),
                        ),
                        SizedBox(
                          width: 320,
                          child: _KpiCard(
                            title: 'Products in Order',
                            value: _formatInt(statsAll.sumFinalReorder),
                            subtitle: 'Sum of numeric final reorder only',
                            icon: Icons.inventory_2_outlined,
                          ),
                        ),
                        SizedBox(
                          width: 320,
                          child: _KpiCard(
                            title: 'Essential',
                            value: '${statsAll.essential}',
                            subtitle: 'Branch formulary = ESSENTIAL',
                            icon: Icons.star_border,
                          ),
                        ),
                        SizedBox(
                          width: 320,
                          child: _KpiCard(
                            title: 'Non',
                            value: '${statsAll.non}',
                            subtitle: 'Branch formulary = NON',
                            icon: Icons.layers_outlined,
                          ),
                        ),

                        // Additional Orders KPI
                        SizedBox(
                          width: 320,
                          child: _KpiCard(
                            title: 'Additional Orders',
                            value: '$sentAddCount',
                            subtitle: 'Sent additional requests (today)',
                            icon: Icons.add_box_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _FiltersBar(
                      categories: categories,
                      selectedCategory: s.categoryFilter,
                      selectedFormulary: s.formularyFilter,
                      nonWithSales45Only: s.nonWithSales45Only,
                      numericFinalOnly: s.numericFinalOnly,
                      additionalOnly: s.additionalOnly,
                      onCategoryChanged: (v) => context.read<OrdersBloc>().add(
                        OrdersCategoryChanged(v),
                      ),
                      onFormularyChanged: (v) => context.read<OrdersBloc>().add(
                        OrdersFormularyChanged(v),
                      ),
                      onNonWithSales45Changed: (v) => context
                          .read<OrdersBloc>()
                          .add(OrdersNonWithSales45Toggled(v)),
                      onNumericFinalOnlyChanged: (v) => context
                          .read<OrdersBloc>()
                          .add(OrdersNumericFinalOnlyToggled(v)),
                      onAdditionalOnlyChanged: (v) => context
                          .read<OrdersBloc>()
                          .add(OrdersAdditionalOnlyToggled(v)),
                      onClearAll: () {
                        context.read<OrdersBloc>().add(
                          const OrdersClearAllFilters(),
                        );
                        _grid.resetGridUi();
                      },
                    ),
                    const SizedBox(height: 12),
                    BlocSelector<OrdersBloc, OrdersState, String>(
                      selector: (s) => s.search,
                      builder: (context, search) {
                        return OrdersToolbar(
                          search: search,
                          onSearchChanged: (v) => context
                              .read<OrdersBloc>()
                              .add(OrdersSearchChanged(v)),
                          onOpenColumns: () =>
                              Scaffold.of(context).openEndDrawer(),
                          onExport: () {},
                          statusChip: null,
                          actions: [
                            // Track button (shows dialog)
                            OrdersToolbar.actionButton(
                              label: 'Track',
                              icon: Icons.track_changes_outlined,
                              badgeCount: s.trackingPending,
                              tooltip: 'Track additional requests status',
                              onPressed: (s.isSubmitted && !isBusy)
                                  ? () => _openTrackingDialog(context)
                                  : null,
                            ),

                            // Hide Review button after submit
                            if (s.hasEdits && !s.isSubmitted)
                              _ReviewEditsButton(
                                count: s.editsCount,
                                onPressed: () => _openReviewDialog(
                                  context: context,
                                  state: s,
                                ),
                              ),

                            // Send additional requests (allowed even if submitted)
                            FilledButton.tonalIcon(
                              onPressed:
                                  (!zoneReady ||
                                      s.additionalEdits.isEmpty ||
                                      isBusy)
                                  ? null
                                  : () {
                                      context.read<OrdersBloc>().add(
                                        OrdersSendAdditionalRequestsPressed(
                                          zone: _zone!,
                                        ),
                                      );
                                    },
                              icon: const Icon(Icons.add_box_outlined),
                              label: Text('Send Additional ($draftAddCount)'),
                            ),

                            // Submit order (disabled if already submitted)
                            FilledButton.icon(
                              onPressed: (!zoneReady || s.isSubmitted || isBusy)
                                  ? null
                                  : () {
                                      context.read<OrdersBloc>().add(
                                        OrdersSubmitOrderPressed(zone: _zone!),
                                      );
                                    },
                              icon: const Icon(Icons.check_circle_outline),
                              label: Text(
                                s.isSubmitted ? 'Submitted' : 'Submit',
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE6E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _TableTitle(),
                            const SizedBox(height: 10),
                            Expanded(
                              child: OrdersTable(
                                rows: s.viewRows,
                                isLoading: isBusy,
                                orderedColumns: orderedColumns,
                                columnWidths: s.columnWidths,
                                finalEdits: s.finalEdits,
                                onTapFinalReorder: (row) => _openSidePanel(
                                  context: context,
                                  state: s,
                                  row: row,
                                ),
                                additionalEdits: s.additionalEdits,
                                sentAdditionalQtyByItemCode:
                                    s.sentAdditionalQtyByItemCode,
                                onTapAdditionalRequest: (row) =>
                                    _openAdditionalSidePanel(
                                      context: context,
                                      state: s,
                                      row: row,
                                    ),
                                controller: _grid.controller,
                                gridController: _grid,
                                onColumnResized: (key, width) {
                                  context.read<OrdersBloc>().add(
                                    OrdersColumnResized(
                                      columnKey: key,
                                      width: width,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openReviewDialog({
    required BuildContext context,
    required OrdersState state,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => ReviewChangesDialog(
        rows: state.rows,
        edits: state.finalEdits,
        onEdit: (itemCode) {
          Navigator.of(context).pop();
          final row = state.rows.firstWhere((r) => r.itemCode == itemCode);
          _openSidePanel(context: context, state: state, row: row);
        },
        onReset: (itemCode) {
          context.read<OrdersBloc>().add(OrdersResetFinalEdit(itemCode));
        },
        onClearAll: () {
          context.read<OrdersBloc>().add(const OrdersClearAllEdits());
        },
      ),
    );
  }

  Future<void> _openSidePanel({
    required BuildContext context,
    required OrdersState state,
    required DailyOrderRow row,
  }) async {
    final itemCode = row.itemCode;

    final oldQty = _extractNumericFinalReorder(
      row.finalReorderQtyStoreStockGt0,
    ).round();

    final edit = state.finalEdits[itemCode];
    final initialQty = edit?.newQty ?? oldQty;
    final initialReason = edit?.reason ?? '';

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Edit Final Reorder',
      barrierColor: Colors.black.withOpacity(0.18),
      pageBuilder: (_, __, ___) {
        return Align(
          alignment: Alignment.centerRight,
          child: FinalReorderSidePanel(
            row: row,
            oldQty: oldQty,
            initialQty: initialQty,
            initialReason: initialReason,
            onClose: () => Navigator.of(context).pop(),
            onSave: (newQty, reason) {
              context.read<OrdersBloc>().add(
                OrdersApplyFinalEdit(
                  itemCode: itemCode,
                  oldQty: oldQty,
                  newQty: newQty,
                  reason: reason,
                ),
              );
              Navigator.of(context).pop();
            },
            onReset: () {
              context.read<OrdersBloc>().add(OrdersResetFinalEdit(itemCode));
              Navigator.of(context).pop();
            },
          ),
        );
      },
    );
  }

  Future<void> _openAdditionalSidePanel({
    required BuildContext context,
    required OrdersState state,
    required DailyOrderRow row,
  }) async {
    final itemCode = row.itemCode;

    final draft = state.additionalEdits[itemCode];
    final rawHistory =
        state.sentAdditionalHistoryByItemCode[itemCode] ?? const [];
    final sentHistory = rawHistory.map((r) {
      final v = r['request_qty'];
      final qty = (v is num) ? v : (num.tryParse((v ?? '').toString()) ?? 0);
      final reason = (r['reason'] ?? '').toString();
      final createdAtStr = (r['created_at'] ?? '').toString();
      final createdAt = DateTime.tryParse(createdAtStr) ?? DateTime.now();

      return SentAdditionalRequest(
        qty: qty,
        reason: reason,
        createdAt: createdAt,
      );
    }).toList();

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Additional Request',
      barrierColor: Colors.black.withOpacity(0.18),
      pageBuilder: (_, __, ___) {
        return Align(
          alignment: Alignment.centerRight,
          child: AdditionalRequestSidePanel(
            row: row,
            initialQty: draft?.requestQty,
            initialReason: draft?.reason ?? '',
            onClose: () => Navigator.of(context).pop(),
            onSave: (qty, reason) {
              context.read<OrdersBloc>().add(
                OrdersApplyAdditionalRequest(
                  itemCode: itemCode,
                  itemName: row.itemName,
                  requestQty: qty,
                  reason: reason,
                ),
              );
              Navigator.of(context).pop();
            },
            onRemove: () {
              context.read<OrdersBloc>().add(
                OrdersRemoveAdditionalRequest(itemCode),
              );
              Navigator.of(context).pop();
            },
            sentHistory: sentHistory,
          ),
        );
      },
    );
  }

  _Stats _calcStats(List<DailyOrderRow> rows) {
    int essential = 0;
    int non = 0;
    num sumFinal = 0;

    for (final row in rows) {
      sumFinal += _extractNumericFinalReorder(row.finalReorderQtyStoreStockGt0);

      final f = (row.branchFormulary ?? '').toString().trim().toUpperCase();
      if (f == 'ESSENTIAL') essential++;
      if (f == 'NON') non++;
    }

    return _Stats(
      totalProducts: rows.length,
      sumFinalReorder: sumFinal,
      essential: essential,
      non: non,
    );
  }

  num _extractNumericFinalReorder(String? v) {
    final s = (v ?? '').toString().trim();
    if (s.isEmpty) return 0;

    final direct = num.tryParse(s.replaceAll(',', ''));
    if (direct != null) return direct;

    final m = RegExp(r'[-+]?\d*\.?\d+').firstMatch(s);
    if (m == null) return 0;
    return num.tryParse(m.group(0) ?? '') ?? 0;
  }

  List<String> _extractCategories(List<DailyOrderRow> rows) {
    final set = <String>{};
    for (final r in rows) {
      final cat = (r.category ?? '').toString().trim();
      if (cat.isNotEmpty) set.add(cat);
    }
    final list = set.toList()..sort();
    return ['ALL', ...list];
  }

  String _formatInt(num v) => v.round().toString();
}

class _Stats {
  final int totalProducts;
  final num sumFinalReorder;
  final int essential;
  final int non;

  const _Stats({
    required this.totalProducts,
    required this.sumFinalReorder,
    required this.essential,
    required this.non,
  });
}

class _StatusChip extends StatelessWidget {
  final bool isSubmitted;
  const _StatusChip({required this.isSubmitted});

  @override
  Widget build(BuildContext context) {
    final bg = isSubmitted ? const Color(0xFFECFDF3) : const Color(0xFFFFFBEB);
    final br = isSubmitted ? const Color(0xFFABEFC6) : const Color(0xFFFDE68A);
    final fg = isSubmitted ? const Color(0xFF027A48) : const Color(0xFF92400E);
    final text = isSubmitted ? 'Submitted' : 'Draft';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: br),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSubmitted ? Icons.check_circle : Icons.edit_outlined,
            size: 16,
            color: fg,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(fontWeight: FontWeight.w900, color: fg),
          ),
        ],
      ),
    );
  }
}

class _ZoneChip extends StatelessWidget {
  final String? zone;
  const _ZoneChip({required this.zone});

  @override
  Widget build(BuildContext context) {
    final z = (zone ?? '').trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.place_outlined, size: 16, color: Color(0xFF111827)),
          const SizedBox(width: 6),
          Text(
            z.isEmpty ? 'Zone: -' : 'Zone: $z',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _ReviewEditsButton extends StatelessWidget {
  final int count;
  final VoidCallback onPressed;

  const _ReviewEditsButton({required this.count, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: const Icon(Icons.fact_check_outlined),
      label: Text('Review Changes ($count)'),
    );
  }
}

class _TopHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? right;

  const _TopHeader({required this.title, required this.subtitle, this.right});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ),
        if (right != null) right!,
      ],
    );
  }
}

class _GenerateCard extends StatelessWidget {
  final bool isBusy;
  final int progress;
  final String? message;
  final String? error;
  final VoidCallback onGenerate;

  const _GenerateCard({
    required this.isBusy,
    required this.progress,
    required this.message,
    required this.error,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 520,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE6E8F0)),
            ),
            child: const Icon(Icons.bolt, color: Color(0xFF4338CA), size: 30),
          ),
          const SizedBox(height: 14),
          const Text(
            'Generate Branch Order',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Press generate to build the order, then we will load all items for this branch.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 16),
          if (isBusy) ...[
            _ProgressStrip(
              progress: progress,
              message: message ?? 'Working...',
            ),
            const SizedBox(height: 12),
          ],
          if (error != null) ...[
            Text(error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton.icon(
              onPressed: isBusy ? null : onGenerate,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Generate Order'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  final int progress;
  final String message;

  const _ProgressStrip({required this.progress, required this.message});

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0, 100);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sync, size: 18, color: AppColors.primaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '$p/100',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: p / 100.0,
              minHeight: 8,
              backgroundColor: const Color(0xFFE5E7EB),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 98,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE6E8F0)),
            ),
            child: Icon(icon, color: const Color(0xFF4338CA)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
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
    );
  }
}

class _FiltersBar extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final String selectedFormulary;
  final bool nonWithSales45Only;
  final bool numericFinalOnly;

  final bool additionalOnly;
  final ValueChanged<bool> onAdditionalOnlyChanged;

  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onFormularyChanged;
  final ValueChanged<bool> onNonWithSales45Changed;
  final ValueChanged<bool> onNumericFinalOnlyChanged;

  final VoidCallback onClearAll;

  const _FiltersBar({
    required this.categories,
    required this.selectedCategory,
    required this.selectedFormulary,
    required this.nonWithSales45Only,
    required this.numericFinalOnly,
    required this.additionalOnly,
    required this.onAdditionalOnlyChanged,
    required this.onCategoryChanged,
    required this.onFormularyChanged,
    required this.onNonWithSales45Changed,
    required this.onNumericFinalOnlyChanged,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModernDropdown(
              label: 'Category',
              value: selectedCategory,
              items: categories,
              onChanged: onCategoryChanged,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ModernDropdown(
              label: 'Formulary',
              value: selectedFormulary,
              items: const ['ALL', 'ESSENTIAL', 'NON'],
              onChanged: onFormularyChanged,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _SwitchTile(
              title: 'NON + Sales (45d)',
              subtitle: 'Show NON items with sales > 0',
              value: nonWithSales45Only,
              onChanged: onNonWithSales45Changed,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _SwitchTile(
              title: 'Items you Will Received',
              subtitle: 'Available Item in Order',
              value: numericFinalOnly,
              onChanged: onNumericFinalOnlyChanged,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _SwitchTile(
              title: 'Additional Only',
              subtitle: 'Show items with additional requests',
              value: additionalOnly,
              onChanged: onAdditionalOnlyChanged,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 56,
            child: OutlinedButton.icon(
              onPressed: onClearAll,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Clear All Filters'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModernDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  const _ModernDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE6E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE6E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF4338CA), width: 1.4),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            onChanged(v);
          },
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _TableTitle extends StatelessWidget {
  const _TableTitle();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.table_rows_outlined, color: AppColors.primaryColor),
        SizedBox(width: 8),
        Text(
          'Main Table',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
      ],
    );
  }
}

// =========================================================
// Tracking Dialog (Additional Requests)
// =========================================================

enum _TrackTab { all, pending, sent, done }

class AdditionalTrackingDialog extends StatefulWidget {
  const AdditionalTrackingDialog({super.key});

  @override
  State<AdditionalTrackingDialog> createState() =>
      _AdditionalTrackingDialogState();
}

class _AdditionalTrackingDialogState extends State<AdditionalTrackingDialog> {
  _TrackTab _tab = _TrackTab.all;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
          border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.08),
              blurRadius: 30,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: BlocBuilder<OrdersBloc, OrdersState>(
          buildWhen: (p, n) =>
              p.additionalTrackingRows != n.additionalTrackingRows ||
              p.status != n.status,
          builder: (context, s) {
            final q = _searchCtrl.text.trim().toLowerCase();
            final base = s.additionalTrackingRows;

            List<AdditionalRequestRow> filtered = base;

            if (_tab != _TrackTab.all) {
              final want = switch (_tab) {
                _TrackTab.pending => 'pending',
                _TrackTab.sent => 'sent_to_store',
                _TrackTab.done => 'done',
                _TrackTab.all => '',
              };
              filtered = filtered
                  .where((r) => r.status.trim().toLowerCase() == want)
                  .toList();
            }

            if (q.isNotEmpty) {
              bool hit(AdditionalRequestRow r) {
                return r.itemCode.toLowerCase().contains(q) ||
                    r.itemName.toLowerCase().contains(q) ||
                    r.reason.toLowerCase().contains(q);
              }

              filtered = filtered.where(hit).toList();
            }

            return Column(
              children: [
                _TrackHeader(
                  title: 'Additional Requests Tracking',
                  subtitle: 'Status, fulfilled quantity, and store notes',
                  onClose: () => Navigator.of(context).pop(),
                  onRefresh: () => context.read<OrdersBloc>().add(
                    const OrdersLoadAdditionalTracking(),
                  ),
                  total: s.trackingTotal,
                  pending: s.trackingPending,
                  sent: s.trackingSentToStore,
                  done: s.trackingDone,
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
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Search item code / name / reason...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchCtrl.text.trim().isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear',
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.close),
                                  ),
                            filled: true,
                            fillColor: cs.surfaceContainerHighest.withOpacity(
                              .55,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _TabPills(
                        tab: _tab,
                        onChanged: (t) => setState(() => _tab = t),
                        counts: _TabCounts(
                          all: s.trackingTotal,
                          pending: s.trackingPending,
                          sent: s.trackingSentToStore,
                          done: s.trackingDone,
                        ),
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
                          separatorBuilder: (_, __) =>
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
    required this.modified,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
            icon: Icon(Icons.refresh, color: cs.primary),
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
  const _TabCounts({
    required this.all,
    required this.pending,
    required this.sent,
    required this.done,
  });
}

class _TabPills extends StatelessWidget {
  final _TrackTab tab;
  final ValueChanged<_TrackTab> onChanged;
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
                        ? Colors.white.withOpacity(.85)
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
          active: tab == _TrackTab.all,
          count: counts.all,
          onTap: () => onChanged(_TrackTab.all),
        ),
        pill(
          text: 'Pending',
          active: tab == _TrackTab.pending,
          count: counts.pending,
          activeBg: const Color(0xFFFFFBEB),
          activeFg: const Color(0xFF92400E),
          onTap: () => onChanged(_TrackTab.pending),
        ),
        pill(
          text: 'Sent',
          active: tab == _TrackTab.sent,
          count: counts.sent,
          activeBg: const Color(0xFFEFF6FF),
          activeFg: const Color(0xFF1D4ED8),
          onTap: () => onChanged(_TrackTab.sent),
        ),
        pill(
          text: 'Done',
          active: tab == _TrackTab.done,
          count: counts.done,
          activeBg: const Color(0xFFECFDF3),
          activeFg: const Color(0xFF027A48),
          onTap: () => onChanged(_TrackTab.done),
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
    if (s == 'pending') {
      return (
        bg: const Color(0xFFFFFBEB),
        fg: const Color(0xFF92400E),
        label: 'Pending',
        icon: Icons.hourglass_bottom,
      );
    }
    if (s == 'sent_to_store') {
      return (
        bg: const Color(0xFFEFF6FF),
        fg: const Color(0xFF1D4ED8),
        label: 'Sent to store',
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
            color: Colors.black.withOpacity(.03),
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
*/
