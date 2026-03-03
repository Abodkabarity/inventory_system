import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../bloc/order_bloc/orders_bloc.dart';
import '../bloc/order_bloc/orders_event.dart';
import '../bloc/order_bloc/orders_state.dart';
import '../widgets/branch_zone_cubit.dart';
import '../widgets/orders_grid_controller.dart';
import '../widgets/orders_table.dart';
import '../widgets/orders_toolbar.dart';
import 'branch_orders_actions.dart';
import 'branch_orders_selectors.dart';
import 'branch_widgets/columns_panel.dart';

class BranchOrdersScreen extends StatefulWidget {
  const BranchOrdersScreen({super.key});

  @override
  State<BranchOrdersScreen> createState() => _BranchOrdersScreenState();
}

class _BranchOrdersScreenState extends State<BranchOrdersScreen> {
  late final OrdersGridController _grid;

  @override
  void initState() {
    super.initState();
    _grid = OrdersGridController();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OrdersBloc, OrdersState>(
      builder: (context, s) {
        final isBusy = s.isBusy;

        final statsAll = BranchOrdersSelectors.calcStats(s.rows);
        final categories = BranchOrdersSelectors.extractCategories(s.rows);
        final orderedColumns = BranchOrdersSelectors.orderedVisibleColumns(s);

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
                  BlocBuilder<BranchZoneCubit, BranchZoneState>(
                    builder: (context, zs) {
                      return _TopHeader(
                        title: s.branchName,
                        subtitle: 'Orders • ${s.runDate}',
                        right: Row(
                          children: [
                            _StatusChip(isSubmitted: s.isSubmitted),
                            const SizedBox(width: 10),
                            _ZoneChip(zone: zs.zone),
                          ],
                        ),
                      );
                    },
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
                            value: statsAll.totalProducts.toString(),
                            subtitle: 'All items loaded for this branch',
                            icon: Icons.list_alt_outlined,
                          ),
                        ),
                        SizedBox(
                          width: 320,
                          child: _KpiCard(
                            title: 'Products in Order',
                            value: statsAll.sumFinalReorder.round().toString(),
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
                        return BlocBuilder<BranchZoneCubit, BranchZoneState>(
                          builder: (context, zs) {
                            final zoneReady =
                                zs.zone != null && zs.zone!.trim().isNotEmpty;

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
                                OrdersToolbar.actionButton(
                                  label: 'Track',
                                  icon: Icons.track_changes_outlined,
                                  badgeCount: s.trackingPending,
                                  tooltip: 'Track additional requests status',
                                  onPressed: (s.isSubmitted && !isBusy)
                                      ? () =>
                                            BranchOrdersActions.openTrackingDialog(
                                              context,
                                            )
                                      : null,
                                ),

                                if (s.hasEdits && !s.isSubmitted)
                                  _ReviewEditsButton(
                                    count: s.editsCount,
                                    onPressed: () =>
                                        BranchOrdersActions.openReviewDialog(
                                          context: context,
                                          state: s,
                                        ),
                                  ),

                                FilledButton.tonalIcon(
                                  onPressed:
                                      (!zoneReady ||
                                          s.additionalEdits.isEmpty ||
                                          isBusy)
                                      ? null
                                      : () {
                                          context.read<OrdersBloc>().add(
                                            OrdersSendAdditionalRequestsPressed(
                                              zone: zs.zone!,
                                            ),
                                          );
                                        },
                                  icon: const Icon(Icons.add_box_outlined),
                                  label: Text(
                                    'Send Additional ($draftAddCount)',
                                  ),
                                ),

                                FilledButton.icon(
                                  onPressed:
                                      (!zoneReady || s.isSubmitted || isBusy)
                                      ? null
                                      : () {
                                          context.read<OrdersBloc>().add(
                                            OrdersSubmitOrderPressed(
                                              zone: zs.zone!,
                                            ),
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

                            // ✅ BranchOrdersScreen change (only the OrdersTable constructor part)
                            // IMPORTANT: add isSubmitted: s.isSubmitted
                            Expanded(
                              child: OrdersTable(
                                rows: s.viewRows,
                                isLoading: isBusy,
                                orderedColumns: orderedColumns,
                                columnWidths: s.columnWidths,
                                finalEdits: s.finalEdits,
                                onTapFinalReorder: (row) =>
                                    BranchOrdersActions.openFinalSidePanel(
                                      context: context,
                                      state: s,
                                      row: row,
                                    ),
                                additionalEdits: s.additionalEdits,
                                sentAdditionalQtyByItemCode:
                                    s.sentAdditionalQtyByItemCode,
                                onTapAdditionalRequest: (row) =>
                                    BranchOrdersActions.openAdditionalSidePanel(
                                      context: context,
                                      state: s,
                                      row: row,
                                    ),
                                isSubmitted: s.isSubmitted, // ✅ NEW
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
