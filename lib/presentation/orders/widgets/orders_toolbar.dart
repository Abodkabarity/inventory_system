// orders_toolbar.dart
import 'package:flutter/material.dart';

class OrdersToolbar extends StatefulWidget {
  final String search;
  final ValueChanged<String> onSearchChanged;

  final VoidCallback onOpenColumns;
  final VoidCallback onExport;

  final Widget? statusChip; // e.g. Submitted/Draft
  final Widget? extraLeft; // e.g. switches row
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border ?? Colors.transparent),
      ),
      child: child,
    );
  }

  static Widget badge({required int count, Color? bg, Color? fg}) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
  static Widget actionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    int badgeCount = 0,
    bool filled = false,
    Color? color,
    String? tooltip,
  }) {
    final btn = filled
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label),
                if (badgeCount > 0) ...[
                  const SizedBox(width: 8),
                  OrdersToolbar.badge(count: badgeCount),
                ],
              ],
            ),
            style: FilledButton.styleFrom(
              backgroundColor: color,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label),
                if (badgeCount > 0) ...[
                  const SizedBox(width: 8),
                  OrdersToolbar.badge(count: badgeCount),
                ],
              ],
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
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
          color: cs.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: LayoutBuilder(
          builder: (context, c) {
            final isNarrow = c.maxWidth < 860;

            return Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // ==========================
                // Search
                // ==========================
                SizedBox(
                  width: isNarrow ? c.maxWidth : 430,
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
                        fillColor: cs.surfaceContainerHighest.withOpacity(.55),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.primary, width: 1.4),
                        ),
                      ),
                      onChanged: widget.onSearchChanged,
                    ),
                  ),
                ),

                if (widget.statusChip != null) widget.statusChip!,
                if (widget.extraLeft != null) widget.extraLeft!,

                // ==========================
                // Columns
                // ==========================
                OutlinedButton.icon(
                  onPressed: widget.onOpenColumns,
                  icon: const Icon(Icons.view_column_outlined, size: 18),
                  label: const Text('Columns'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),

                // ==========================
                // Export
                // ==========================
                FilledButton.icon(
                  onPressed: widget.onExport,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Export'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),

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
