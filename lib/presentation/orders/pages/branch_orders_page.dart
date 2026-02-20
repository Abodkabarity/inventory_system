import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/daily_order_row.dart';
import '../bloc/orders_bloc.dart';
import '../bloc/orders_bloc_factory.dart';
import '../bloc/orders_event.dart';
import '../bloc/orders_state.dart';
// ✅ NEW widgets (لا تغير منطقك القديم، بس UI)
import '../widgets/final_reorder_side_panel.dart';
import '../widgets/orders_table.dart';
import '../widgets/orders_toolbar.dart';
import '../widgets/review_changes_dialog.dart';

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

class _BranchOrdersView extends StatelessWidget {
  final String branchName;
  const _BranchOrdersView({required this.branchName});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OrdersBloc, OrdersState>(
      builder: (context, s) {
        final isBusy = s.isBusy;

        // ✅ stats على كامل rows (مش viewRows)
        final statsAll = _calcStats(s.rows);

        // ✅ categories من كامل rows
        final categories = _extractCategories(s.rows);

        return Scaffold(
          backgroundColor: const Color(0xFFF6F7FB),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TopHeader(
                    title: branchName,
                    subtitle: 'Orders • ${s.runDate}',
                  ),
                  const SizedBox(height: 14),

                  // ==========================
                  // Initial screen (Generate center)
                  // ==========================
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
                    // ==========================
                    // Progress strip while generating/loading
                    // ==========================
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

                    // KPI cards
                    Row(
                      children: [
                        Expanded(
                          child: _KpiCard(
                            title: 'Products in Order',
                            value: _formatInt(statsAll.sumFinalReorder),
                            subtitle: 'Sum of numeric final reorder only',
                            icon: Icons.inventory_2_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _KpiCard(
                            title: 'Essential',
                            value: '${statsAll.essential}',
                            subtitle: 'Branch formulary = ESSENTIAL',
                            icon: Icons.star_border,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _KpiCard(
                            title: 'Non',
                            value: '${statsAll.non}',
                            subtitle: 'Branch formulary = NON',
                            icon: Icons.layers_outlined,
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
                      onCategoryChanged: (v) => context.read<OrdersBloc>().add(
                        OrdersCategoryChanged(v),
                      ),
                      onFormularyChanged: (v) => context.read<OrdersBloc>().add(
                        OrdersFormularyChanged(v),
                      ),
                      onNonWithSales45Changed: (v) => context
                          .read<OrdersBloc>()
                          .add(OrdersNonWithSales45Toggled(v)),
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

                          // ✅ NEW: Review Changes button (بدون عمود Actions بالجدول)
                          actions: [
                            if (s.hasEdits)
                              _ReviewEditsButton(
                                count: s.editsCount,
                                onPressed: () => _openReviewDialog(
                                  context: context,
                                  state: s,
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
                                visibleOptionalColumns:
                                    s.visibleOptionalColumns,

                                // ✅ NEW
                                finalEdits: s.finalEdits,

                                // ✅ click على final reorder cell يفتح Side Panel
                                onTapFinalReorder: (row) => _openSidePanel(
                                  context: context,
                                  state: s,
                                  row: row,
                                ),
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

  // ==========================
  // ✅ Review dialog (آخر مراجعة للتعديلات)
  // ==========================
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

  // ==========================
  // ✅ Side Panel (فتح عند click على خلية Final Reorder)
  // ==========================
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

    final isLimitedStock = (row.isLimitedStock ?? false);

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
            isLimitedStock: isLimitedStock,
            onClose: () => Navigator.of(context).pop(),

            onSave: (newQty) {
              context.read<OrdersBloc>().add(
                OrdersApplyFinalEdit(
                  itemCode: itemCode,
                  oldQty: oldQty,
                  newQty: newQty,
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

  // ==========================
  // ✅ STATS
  // ==========================
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

    return _Stats(sumFinalReorder: sumFinal, essential: essential, non: non);
  }

  // يأخذ "4" أو "4.5" أو "  3 " => رقم
  // يأخذ "NON FORMULARY" أو "" => 0
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

  String _formatInt(num v) {
    final n = v.round();
    return n.toString();
  }
}

class _Stats {
  final num sumFinalReorder;
  final int essential;
  final int non;

  const _Stats({
    required this.sumFinalReorder,
    required this.essential,
    required this.non,
  });
}

// ✅ NEW small widget for toolbar action
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

  const _TopHeader({required this.title, required this.subtitle});

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
  final int progress; // 0..100
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
              const Icon(Icons.sync, size: 18, color: AppColors.blueDark),
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

  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onFormularyChanged;
  final ValueChanged<bool> onNonWithSales45Changed;

  const _FiltersBar({
    required this.categories,
    required this.selectedCategory,
    required this.selectedFormulary,
    required this.nonWithSales45Only,
    required this.onCategoryChanged,
    required this.onFormularyChanged,
    required this.onNonWithSales45Changed,
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
        Icon(Icons.table_rows_outlined, color: AppColors.blueDark),
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
