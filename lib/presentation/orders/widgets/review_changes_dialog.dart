import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/daily_order_row.dart';
import '../bloc/order_bloc/orders_state.dart';

class ReviewChangesDialog extends StatefulWidget {
  final List<DailyOrderRow> rows;
  final Map<String, FinalReorderEdit> edits;

  final ValueChanged<String> onEdit;
  final ValueChanged<String> onReset;
  final VoidCallback onClearAll;

  const ReviewChangesDialog({
    super.key,
    required this.rows,
    required this.edits,
    required this.onEdit,
    required this.onReset,
    required this.onClearAll,
  });

  @override
  State<ReviewChangesDialog> createState() => _ReviewChangesDialogState();
}

class _ReviewChangesDialogState extends State<ReviewChangesDialog> {
  late Map<String, FinalReorderEdit> _localEdits;

  @override
  void initState() {
    super.initState();
    // ✅ local copy so UI updates immediately on Reset/Clear without waiting for outer rebuild
    _localEdits = Map<String, FinalReorderEdit>.from(widget.edits);
  }

  @override
  void didUpdateWidget(covariant ReviewChangesDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If parent sends new edits map, refresh local copy
    if (oldWidget.edits != widget.edits) {
      _localEdits = Map<String, FinalReorderEdit>.from(widget.edits);
    }
  }

  DailyOrderRow? _rowByItem(String itemCode) {
    try {
      return widget.rows.firstWhere((r) => r.itemCode == itemCode);
    } catch (_) {
      return null;
    }
  }

  List<FinalReorderEdit> _sortedList() {
    final list = _localEdits.values.toList()
      ..sort((a, b) => a.itemCode.compareTo(b.itemCode));
    return list;
  }

  Future<void> _handleReset(String itemCode) async {
    // 1) call your external logic (bloc/db/etc)
    widget.onReset(itemCode);

    // 2) remove locally for instant UI feedback
    if (mounted) {
      setState(() {
        _localEdits.remove(itemCode);
      });
    }
  }

  Future<void> _handleClearAll() async {
    widget.onClearAll();
    if (mounted) {
      setState(() {
        _localEdits.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = _sortedList();

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE6E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 26,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Header(
                  count: list.length,
                  onClearAll: list.isEmpty ? null : _handleClearAll,
                  onClose: () => Navigator.of(context).pop(),
                ),
                const Divider(height: 1),

                // Body
                Flexible(
                  child: ConstrainedBox(
                    // ✅ keep dialog height reasonable when many items
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.70,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: list.isEmpty
                          ? _EmptyState(
                              onClose: () => Navigator.of(context).pop(),
                            )
                          : LayoutBuilder(
                              builder: (context, c) {
                                // ✅ 3 cols on wide, 2 on medium, 1 on small
                                int crossAxisCount = 1;

                                if (c.maxWidth >= 1080) crossAxisCount = 3;
                                if (c.maxWidth >= 760 && c.maxWidth < 1080) {
                                  crossAxisCount = 2;
                                }

                                return Scrollbar(
                                  child: GridView.builder(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: crossAxisCount,
                                          crossAxisSpacing: 10,
                                          mainAxisSpacing: 10,
                                          // ✅ compact card ratio
                                          childAspectRatio: crossAxisCount == 1
                                              ? 1
                                              : 1.6,
                                        ),
                                    itemCount: list.length,
                                    itemBuilder: (context, index) {
                                      final e = list[index];
                                      final r = _rowByItem(e.itemCode);

                                      return _CompactChangeCard(
                                        itemCode: r?.itemCode ?? e.itemCode,
                                        itemName: r?.itemName ?? '',
                                        oldQty: e.oldQty,
                                        newQty: e.newQty,
                                        diff: e.diff,
                                        reason: e.reason,
                                        accent: cs.primary,
                                        onEdit: () => widget.onEdit(e.itemCode),
                                        onReset: () => _handleReset(e.itemCode),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ),

                const Divider(height: 1),

                // Footer
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          list.isEmpty
                              ? 'No changes to review'
                              : '${list.length} change(s) ready',
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text(
                          'Done',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
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

class _Header extends StatelessWidget {
  final int count;
  final VoidCallback? onClearAll;
  final VoidCallback onClose;

  const _Header({
    required this.count,
    required this.onClearAll,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE6E8F0)),
            ),
            child: Icon(
              Icons.fact_check_outlined,
              color: AppColors.primaryColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Review Changes',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count == 0
                      ? 'No edits yet'
                      : '$count item(s) edited. Confirm or reset.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
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

class _EmptyState extends StatelessWidget {
  final VoidCallback onClose;

  const _EmptyState({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE6E8F0)),
              ),
              child: Icon(Icons.done_all_rounded, color: cs.primary, size: 28),
            ),
            const SizedBox(height: 10),
            const Text(
              'No changes',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'You did not edit any items yet.',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onClose,
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.primary,
                side: BorderSide(color: cs.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
              child: const Text(
                'Close',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactChangeCard extends StatelessWidget {
  final String itemCode;
  final String itemName;

  final int oldQty;
  final int newQty;
  final int diff;
  final String reason;

  final Color accent;

  final VoidCallback onEdit;
  final VoidCallback onReset;

  const _CompactChangeCard({
    required this.itemCode,
    required this.itemName,
    required this.oldQty,
    required this.newQty,
    required this.diff,
    required this.reason,
    required this.accent,
    required this.onEdit,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final safeReason = reason.trim().isEmpty ? '—' : reason.trim();
    final diffText = diff == 0 ? '0' : (diff > 0 ? '+$diff' : '$diff');

    final diffBg = diff > 0
        ? const Color(0xFFECFDF3)
        : diff < 0
        ? const Color(0xFFFFF1F2)
        : const Color(0xFFF3F4F6);

    final diffFg = diff > 0
        ? const Color(0xFF027A48)
        : diff < 0
        ? const Color(0xFFB42318)
        : const Color(0xFF374151);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top row: title + diff
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ItemTitleCompact(code: itemCode, name: itemName),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: diffBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFE6E8F0)),
                ),
                child: Text(
                  'Diff $diffText',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: diffFg,
                    height: 1,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Qty row (compact)
          Row(
            children: [
              Expanded(
                child: _QtyPill(
                  label: 'Default',
                  value: oldQty.toString(),
                  icon: Icons.auto_awesome_outlined,
                  accent: accent,
                  emphasize: false,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _QtyPill(
                  label: 'New',
                  value: newQty.toString(),
                  icon: Icons.edit_outlined,
                  accent: accent,
                  emphasize: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),

          // Reason (compact)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.backgroundWidget,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE6E8F0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.message_outlined,
                  size: 16,
                  color: AppColors.primaryColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    safeReason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      fontSize: 12.8,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Actions row (consistent)
          OutlinedButton.icon(
            onPressed: onEdit,
            icon: Icon(Icons.edit_rounded, size: 18, color: AppColors.white),
            label: Text(
              'Edit',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.white,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: accent.withValues(alpha: 0.40)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),

              backgroundColor: AppColors.primaryColor,
              padding: EdgeInsets.symmetric(horizontal: 75.w, vertical: 16.h),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemTitleCompact extends StatelessWidget {
  final String code;
  final String name;

  const _ItemTitleCompact({required this.code, required this.name});

  @override
  Widget build(BuildContext context) {
    final hasName = name.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          code,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          hasName ? name : '—',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14.6,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
            height: 1.15,
          ),
        ),
      ],
    );
  }
}

class _QtyPill extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final bool emphasize;

  const _QtyPill({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.emphasize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: emphasize ? const Color(0xFFEEF2FF) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE6E8F0)),
            ),
            child: Icon(icon, size: 16, color: AppColors.primaryColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                    height: 1,
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
