import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';

class StockWorkspaceExportButton extends StatelessWidget {
  final bool busy;
  final VoidCallback? onPressed;
  const StockWorkspaceExportButton({
    super.key,
    required this.busy,
    this.onPressed,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Export matching rows in the current table order',
    child: SizedBox(
      height: 46,
      child: FilledButton.icon(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryColor,
          foregroundColor: Colors.white,
          iconColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
        icon: Icon(
          busy ? Icons.hourglass_top_rounded : Icons.download_rounded,
          size: 18,
        ),
        label: Text(busy ? 'Exporting…' : 'Export Excel'),
      ),
    ),
  );
}

/// Visual building blocks shared by Stock Management workspaces.
class StockWorkspaceStyle {
  static const ink = Color(0xFF142C40);
  static const teal = Color(0xFF008A83);
  static const line = Color(0xFFE9E2D8);
  static const background = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFF8EE), Color(0xFFF4F8F5), Color(0xFFF8F5F0)],
    ),
  );
}

class StockWorkspaceBanner extends StatelessWidget {
  final Widget child;
  final bool compact;

  const StockWorkspaceBanner({
    super.key,
    required this.child,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16, vertical: 10),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF183D42), Color(0xFF142D40)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: StockWorkspaceStyle.ink.withValues(alpha: .12),
          blurRadius: 22,
          offset: const Offset(0, 7),
        ),
      ],
    ),
    child: child,
  );
}

class StockWorkspaceMetricCard extends StatefulWidget {
  final String label, caption;
  final double? value;
  final Color color;
  final IconData icon;
  final bool selected;
  final bool stackValue;
  final VoidCallback onTap;

  const StockWorkspaceMetricCard({
    super.key,
    required this.label,
    required this.caption,
    required this.value,
    required this.color,
    required this.icon,
    required this.selected,
    this.stackValue = false,
    required this.onTap,
  });

  @override
  State<StockWorkspaceMetricCard> createState() =>
      _StockWorkspaceMetricCardState();
}

class _StockWorkspaceMetricCardState extends State<StockWorkspaceMetricCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final motion = MediaQuery.disableAnimationsOf(context);
    final duration = motion ? Duration.zero : const Duration(milliseconds: 180);
    return Semantics(
      button: true,
      selected: widget.selected,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedScale(
          scale: _hover ? 1.01 : 1,
          duration: duration,
          child: AnimatedContainer(
            duration: duration,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    widget.color.withValues(alpha: .105),
                    Colors.white,
                  ),
                  Color.alphaBlend(
                    widget.color.withValues(alpha: .025),
                    Colors.white,
                  ),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: widget.selected
                    ? widget.color.withValues(alpha: .6)
                    : _hover
                    ? widget.color.withValues(alpha: .3)
                    : StockWorkspaceStyle.line,
                width: widget.selected ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      (_hover || widget.selected
                              ? widget.color
                              : StockWorkspaceStyle.ink)
                          .withValues(alpha: _hover ? .12 : .04),
                  blurRadius: _hover ? 20 : 12,
                  offset: Offset(0, _hover ? 6 : 3),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  child: Tooltip(
                    message: widget.caption,
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: widget.color,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            widget.icon,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (widget.stackValue)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: StockWorkspaceStyle.ink,
                                    fontSize: 13,
                                    height: 1,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                _animatedValue(context),
                              ],
                            ),
                          )
                        else ...[
                          Expanded(
                            child: Text(
                              widget.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: StockWorkspaceStyle.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _animatedValue(context),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _animatedValue(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: widget.value ?? 0),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 400),
    builder: (_, value, _) => Text(
      widget.value == null ? '—' : NumberFormat('#,##0').format(value),
      style: TextStyle(
        color: widget.color,
        fontSize: widget.stackValue ? 22 : 25,
        height: widget.stackValue ? 1 : 1.1,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class StockWorkspaceRegisterFrame extends StatelessWidget {
  final Widget child;

  const StockWorkspaceRegisterFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(1),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: StockWorkspaceStyle.line),
      boxShadow: [
        BoxShadow(
          color: StockWorkspaceStyle.ink.withValues(alpha: .05),
          blurRadius: 22,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );
}

class StockWorkspaceFilterSurface extends StatelessWidget {
  final Widget child;

  const StockWorkspaceFilterSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: StockWorkspaceStyle.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}
