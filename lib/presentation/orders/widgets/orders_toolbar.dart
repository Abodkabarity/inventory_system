// orders_toolbar.dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';

class OrdersToolbar extends StatefulWidget {
  final String search;
  final ValueChanged<String> onSearchChanged;

  final VoidCallback onOpenColumns;
  final VoidCallback onExport;
  final VoidCallback addMismatch;
  final VoidCallback addMax;
  final VoidCallback onClearAll;

  final Widget? statusChip;
  final Widget? extraLeft;
  final List<Widget> actions;

  const OrdersToolbar({
    super.key,
    required this.search,
    required this.onSearchChanged,
    required this.onOpenColumns,
    required this.onExport,
    this.statusChip,
    this.extraLeft,
    required this.actions,
    required this.onClearAll,
    required this.addMismatch,
    required this.addMax,
  });

  @override
  State<OrdersToolbar> createState() => _OrdersToolbarState();

  // ==========================
  // Optional helpers (use outside)
  // ==========================
  static Widget pill({
    required Widget child,
    Color? bg,
    Color? border,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 12,
      vertical: 10,
    ),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: border ?? Colors.transparent),
      ),
      child: child,
    );
  }

  static Widget badge({required int count, Color? bg, Color? fg}) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: bg ?? const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE6E8F0)),
      ),
      child: Text(
        count.toString(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
          color: fg ?? const Color(0xFF1D4ED8),
          height: 1.1,
        ),
      ),
    );
  }

  /// Modern action button you can use in `actions`.
  /// ✅ UPDATED: now matches "Clear All Filters" button style.
  static Widget actionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    int badgeCount = 0,
    bool filled = true, // default filled like Clear
    Color? color,
    String? tooltip,
  }) {
    final bg = color ?? AppColors.primaryColor;

    final labelWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        if (badgeCount > 0) ...[
          const SizedBox(width: 8),
          OrdersToolbar.badge(
            count: badgeCount,
            bg: Colors.white.withValues(alpha: .22),
            fg: Colors.white,
          ),
        ],
      ],
    );

    final btn = SizedBox(
      child: filled
          ? ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18, color: Colors.white),
              label: labelWidget,
              style: ElevatedButton.styleFrom(
                backgroundColor: bg,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 18, color: bg),
              label: DefaultTextStyle.merge(
                style: TextStyle(color: bg, fontWeight: FontWeight.bold),
                child: labelWidget,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: bg,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                side: BorderSide(color: bg),
              ),
            ),
    );

    if (tooltip == null) return btn;
    return Tooltip(message: tooltip, child: btn);
  }
}

class _OrdersToolbarState extends State<OrdersToolbar> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.search);
    _focus = FocusNode();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant OrdersToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.search != widget.search &&
        widget.search != _controller.text) {
      final sel = _controller.selection;
      _controller.text = widget.search;

      final offset = sel.baseOffset.clamp(0, _controller.text.length);
      _controller.selection = TextSelection.collapsed(offset: offset);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    // refresh suffix clear icon
    if (mounted) setState(() {});
  }

  void _clearSearch() {
    if (_controller.text.isEmpty) return;
    _controller.clear();
    widget.onSearchChanged('');
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18.r),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: .55)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: LayoutBuilder(
          builder: (context, c) {
            return Row(
              children: [
                // ==========================
                // Search
                // ==========================
                Expanded(
                  flex: 2,
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,

                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search item code / name / barcode...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _controller.text.trim().isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                onPressed: _clearSearch,
                                icon: const Icon(Icons.close),
                              ),
                        filled: true,
                        fillColor: AppColors.backgroundWidget,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14.w,
                          vertical: 12.h,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14.r),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14.r),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14.r),
                          borderSide: BorderSide(color: cs.primary, width: 1.4),
                        ),
                      ),
                      onChanged: widget.onSearchChanged,
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                if (widget.statusChip != null) widget.statusChip!,
                if (widget.extraLeft != null) widget.extraLeft!,

                // ==========================
                // Columns
                // ==========================
                SizedBox(
                  width: 175.w,
                  child: OutlinedButton.icon(
                    onPressed: widget.onOpenColumns,
                    icon: const Icon(
                      Icons.view_column_outlined,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Add Columns',
                      style: TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      padding: EdgeInsets.symmetric(
                        horizontal: 14.w,
                        vertical: 12.h,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 175.w,
                  child: FilledButton.icon(
                    onPressed: widget.addMismatch,

                    icon: const Icon(Icons.list, size: 18),
                    label: const Text(
                      'Add Mismatch',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.deepOrangeAccent,
                      padding: EdgeInsets.symmetric(
                        horizontal: 14.w,
                        vertical: 12.h,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 175.w,
                  child: FilledButton.icon(
                    onPressed: widget.addMax,

                    icon: const Icon(Icons.format_indent_increase, size: 18),
                    label: const Text(
                      'Add Max',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.yellow.shade800,
                      padding: EdgeInsets.symmetric(
                        horizontal: 14.w,
                        vertical: 12.h,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // ==========================
                // Export
                // ==========================
                SizedBox(
                  width: 175.w,
                  child: FilledButton.icon(
                    onPressed: widget.onExport,

                    icon: const Icon(Icons.download, size: 18),
                    label: const Text(
                      'Export',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blueGrey,
                      padding: EdgeInsets.symmetric(
                        horizontal: 14.w,
                        vertical: 12.h,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // ==========================
                // Clear All Filters (reference style)
                // ==========================
                SizedBox(
                  width: 175.w,
                  child: ElevatedButton.icon(
                    onPressed: widget.onClearAll,
                    icon: const Icon(
                      Icons.filter_alt_off_outlined,
                      color: AppColors.white,
                    ),
                    label: const Text(
                      'Clear All Filters',
                      style: TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: AppColors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // ==========================
                // Extra actions (Track / Send / Submitted ...)
                // ==========================
                ...widget.actions,
              ],
            );
          },
        ),
      ),
    );
  }
}
